import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:i_zerak_app/models/subscription_dao.dart';
import 'package:i_zerak_app/services/sync/sync_snapshot.dart';

/// Synchronisation entre appareils par un dossier partage (Syncthing).
///
/// Chaque appareil garde sa propre base Hive et n'ecrit que son propre
/// fichier, `izerak-<deviceId>.json`, dans le dossier. Il lit ceux des autres
/// et fusionne entree par entree : la plus recente l'emporte. Personne
/// n'ecrivant dans le fichier d'un autre, Syncthing n'a jamais de conflit a
/// trancher.
///
/// Les boites elles-memes ne sont jamais copiees : Hive les garde ouvertes et
/// y ajoute au fil de l'eau, et un fichier recopie en pleine ecriture serait
/// corrompu.
enum SyncPhase {
  /// Aucun dossier choisi, ou plateforme sans systeme de fichiers (web).
  disabled,
  idle,
  syncing,
  error,
}

/// Un autre appareil vu dans le dossier.
@immutable
class SyncPeer {
  const SyncPeer({required this.deviceId, required this.name, required this.writtenAt});

  final String deviceId;
  final String name;

  /// Quand cet appareil a ecrit son fichier pour la derniere fois.
  final DateTime writtenAt;
}

@immutable
class SyncStatus {
  const SyncStatus({
    required this.phase,
    this.lastSync,
    this.error,
    this.peers = const [],
    this.generation = 0,
  });

  static const SyncStatus disabled = SyncStatus(phase: SyncPhase.disabled);

  final SyncPhase phase;

  /// Fin de la derniere synchronisation reussie.
  final DateTime? lastSync;

  /// Message brut de la derniere erreur, a afficher tel quel.
  final String? error;

  final List<SyncPeer> peers;

  /// Augmente chaque fois qu'une importation a modifie les donnees locales :
  /// l'interface s'en sert pour recharger la page ouverte.
  final int generation;
}

/// Une boite Hive vue comme des chaines, quelle que soit sa nature.
abstract class SyncedBox {
  /// Prefixe des cles dans le fichier partage : `<name>/<cle>`.
  String get name;

  /// Les evenements d'ecriture et de suppression de la boite.
  Stream<BoxEvent> watch();

  Iterable<String> get keys;

  /// La valeur serialisee, ou `null` si la cle n'existe pas.
  String? read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);

  /// Une `Box<String>` : la valeur est deja une chaine.
  factory SyncedBox.strings(String name, Box<String> box) = _StringBox;

  /// Les abonnements : la valeur est le JSON de `Subscription.toJson`, relu
  /// par `Subscription.fromJson(cle, ...)`.
  factory SyncedBox.subscriptions(String name, Box<Subscription> box) = _SubscriptionBox;
}

/// Ce que les deux sortes de boites ont en commun. Chaque ecriture est suivie
/// d'un `flush`, pour la meme raison que dans les depots.
abstract class _HiveSyncedBox<T> implements SyncedBox {
  _HiveSyncedBox(this.name, this.box);

  @override
  final String name;
  final Box<T> box;

  @override
  Stream<BoxEvent> watch() => box.watch();

  /// Les cles non textuelles n'existent pas dans les depots synchronises ;
  /// elles sont tenues a l'ecart plutot que reecrites sous une autre forme.
  @override
  Iterable<String> get keys => box.keys.whereType<String>();

  @override
  Future<void> delete(String key) async {
    await box.delete(key);
    await box.flush();
  }
}

class _StringBox extends _HiveSyncedBox<String> {
  _StringBox(super.name, super.box);

  @override
  String? read(String key) => box.get(key);

  @override
  Future<void> write(String key, String value) async {
    await box.put(key, value);
    await box.flush();
  }
}

class _SubscriptionBox extends _HiveSyncedBox<Subscription> {
  _SubscriptionBox(super.name, super.box);

  @override
  String? read(String key) {
    final subscription = box.get(key);
    return subscription == null ? null : json.encode(subscription.toJson());
  }

  @override
  Future<void> write(String key, String value) async {
    final raw = json.decode(value);
    if (raw is! Map<String, Object?>) {
      return;
    }
    await box.put(key, Subscription.fromJson(key, raw));
    await box.flush();
  }
}

class SyncService {
  /// [settings] retient le dossier, l'identifiant et le nom de l'appareil ;
  /// [meta] l'horodatage de chaque entree, suppressions comprises.
  /// [supported] vaut `false` sur le web : le service reste alors `disabled`.
  SyncService({
    required Box<String> settings,
    required Box<String> meta,
    required List<SyncedBox> boxes,
    bool supported = true,
    DateTime Function()? clock,
  })  : _settings = settings,
        _meta = meta,
        _boxes = {for (final box in boxes) box.name: box},
        _supported = supported,
        _clock = clock ?? DateTime.now;

  final Box<String> _settings;
  final Box<String> _meta;
  final Map<String, SyncedBox> _boxes;
  final bool _supported;
  final DateTime Function() _clock;

  final ValueNotifier<SyncStatus> _status = ValueNotifier(SyncStatus.disabled);
  final List<StreamSubscription<BoxEvent>> _watches = [];
  Timer? _exportTimer;

  /// Les entrees que l'importation est en train d'ecrire : leur evenement ne
  /// doit pas les reposer a l'heure locale, elles portent deja l'heure de
  /// l'appareil d'origine.
  final Set<String> _applying = {};

  /// Une seule synchronisation a la fois : la suivante attend la precedente.
  Future<void> _queue = Future.value();

  static const String _folderKey = 'folder';
  static const String _deviceIdKey = 'deviceId';
  static const String _deviceNameKey = 'deviceName';
  static const String _filePrefix = 'izerak-';
  static const Duration _exportDelay = Duration(seconds: 2);

  ValueListenable<SyncStatus> get status => _status;

  bool get supported => _supported;

  /// Le dossier partage, ou `null` tant qu'il n'est pas choisi.
  String? get folder {
    final raw = _settings.get(_folderKey)?.trim();
    return raw == null || raw.isEmpty ? null : raw;
  }

  /// Tire au hasard au premier lancement, puis fixe.
  String get deviceId => _settings.get(_deviceIdKey) ?? '';

  /// Par defaut « Téléphone » sur Android, « PC » ailleurs ; modifiable.
  String get deviceName {
    final raw = _settings.get(_deviceNameKey)?.trim();
    if (raw != null && raw.isNotEmpty) {
      return raw;
    }
    return defaultTargetPlatform == TargetPlatform.android ? 'Téléphone' : 'PC';
  }

  bool get _enabled => _supported && folder != null;

  String get _ownFile => '$_filePrefix$deviceId.json';

  /// Enregistre les choix des reglages. Un [folder] vide desactive la synchro.
  /// Un changement de dossier relance une synchronisation complete.
  Future<void> configure({String? folder, String? deviceName}) async {
    final before = this.folder;
    final nameBefore = this.deviceName;
    if (folder != null) {
      final trimmed = folder.trim();
      if (trimmed.isEmpty) {
        await _settings.delete(_folderKey);
      } else {
        await _settings.put(_folderKey, trimmed);
      }
    }
    if (deviceName != null) {
      final trimmed = deviceName.trim();
      if (trimmed.isEmpty) {
        await _settings.delete(_deviceNameKey);
      } else {
        await _settings.put(_deviceNameKey, trimmed);
      }
    }
    await _settings.flush();

    if (!_enabled) {
      _exportTimer?.cancel();
      _status.value = SyncStatus(phase: SyncPhase.disabled, generation: _status.value.generation);
      return;
    }
    if (this.folder != before || this.deviceName != nameBefore) {
      await syncNow();
    }
  }

  /// A appeler une fois au demarrage : horodate les entrees anterieures a la
  /// synchro, importe, exporte, puis suit les ecritures locales.
  ///
  /// Le suivi commence meme sans dossier choisi : une journee saisie avant que
  /// la synchro soit reglee garde ainsi sa vraie date, et l'emporte sur une
  /// donnee plus ancienne d'un autre appareil.
  Future<void> start() async {
    if (!_supported) {
      _status.value = SyncStatus.disabled;
      return;
    }
    if (deviceId.isEmpty) {
      await _settings.put(_deviceIdKey, _newDeviceId());
      await _settings.flush();
    }
    await _stampLegacy();
    for (final box in _boxes.values) {
      _watches.add(box.watch().listen((event) => _onLocalChange(box, event)));
    }
    if (_enabled) {
      await syncNow();
    }
  }

  /// Importe les fichiers des autres appareils, puis reecrit le sien.
  Future<void> syncNow() {
    final run = _queue.then((_) => _sync());
    // Une erreur est deja rapportee dans le statut : elle ne doit pas bloquer
    // les synchronisations suivantes.
    _queue = run.catchError((_) {});
    return run;
  }

  Future<void> dispose() async {
    _exportTimer?.cancel();
    for (final watch in _watches) {
      await watch.cancel();
    }
    _watches.clear();
  }

  Future<void> _sync() async {
    if (!_enabled) {
      _status.value = SyncStatus(phase: SyncPhase.disabled, generation: _status.value.generation);
      return;
    }
    final current = _status.value;
    _status.value = SyncStatus(
      phase: SyncPhase.syncing,
      lastSync: current.lastSync,
      peers: current.peers,
      generation: current.generation,
    );
    try {
      final directory = Directory(folder!);
      await directory.create(recursive: true);
      final (:changed, :peers) = await _import(directory);
      await _export(directory);
      _status.value = SyncStatus(
        phase: SyncPhase.idle,
        lastSync: _clock(),
        peers: peers,
        generation: current.generation + (changed ? 1 : 0),
      );
    } catch (error) {
      _status.value = SyncStatus(
        phase: SyncPhase.error,
        lastSync: current.lastSync,
        error: '$error',
        peers: current.peers,
        generation: current.generation,
      );
    }
  }

  /// Les entrees deja la avant la synchro recoivent la plus petite date qui
  /// soit : toute modification reelle, d'ou qu'elle vienne, passe devant.
  Future<void> _stampLegacy() async {
    final missing = <String, String>{
      for (final box in _boxes.values)
        for (final key in box.keys)
          if (!_meta.containsKey(_id(box, key)))
            _id(box, key): json.encode(const SyncStamp(legacyStamp).toJson()),
    };
    if (missing.isNotEmpty) {
      await _meta.putAll(missing);
      await _meta.flush();
    }
  }

  Future<void> _onLocalChange(SyncedBox box, BoxEvent event) async {
    if (event.key is! String) {
      return;
    }
    final id = _id(box, event.key as String);
    if (_applying.remove(id)) {
      return;
    }
    final stamp = SyncStamp(_clock().millisecondsSinceEpoch, deleted: event.deleted);
    await _meta.put(id, json.encode(stamp.toJson()));
    await _meta.flush();
    if (_enabled) {
      _exportTimer?.cancel();
      _exportTimer = Timer(_exportDelay, () {
        final directory = Directory(folder!);
        _queue = _queue.then((_) => _export(directory)).catchError((Object error) {
          final current = _status.value;
          _status.value = SyncStatus(
            phase: SyncPhase.error,
            lastSync: current.lastSync,
            error: '$error',
            peers: current.peers,
            generation: current.generation,
          );
        });
      });
    }
  }

  Future<({bool changed, List<SyncPeer> peers})> _import(Directory directory) async {
    final peers = <String, SyncPeer>{};
    var changed = false;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      final name = entity.uri.pathSegments.last;
      if (!name.startsWith(_filePrefix) || !name.endsWith('.json') || name == _ownFile) {
        continue;
      }
      DeviceSnapshot? snapshot;
      try {
        snapshot = DeviceSnapshot.decode(await entity.readAsString());
      } on FileSystemException {
        snapshot = null;
      } on FormatException {
        snapshot = null;
      }
      // Un fichier illisible, ou une copie de conflit de notre propre fichier,
      // n'apprend rien : on passe au suivant.
      if (snapshot == null || snapshot.device == deviceId) {
        continue;
      }
      final known = peers[snapshot.device];
      if (known == null || snapshot.writtenAt.isAfter(known.writtenAt)) {
        peers[snapshot.device] = SyncPeer(
          deviceId: snapshot.device,
          name: snapshot.name,
          writtenAt: snapshot.writtenAt,
        );
      }
      for (final entry in snapshot.entries.entries) {
        if (await _apply(entry.key, entry.value)) {
          changed = true;
        }
      }
    }
    return (changed: changed, peers: peers.values.toList());
  }

  /// Applique une entree distante si elle est plus recente. Vrai si les
  /// donnees locales ont change.
  Future<bool> _apply(String id, SyncEntry entry) async {
    final slash = id.indexOf('/');
    if (slash <= 0) {
      return false;
    }
    final box = _boxes[id.substring(0, slash)];
    final key = id.substring(slash + 1);
    if (box == null || key.isEmpty) {
      return false;
    }
    if (!remoteWins(SyncStamp.fromJson(_decode(_meta.get(id))), entry.stamp)) {
      return false;
    }

    // L'horodatage distant d'abord : s'il manquait, un evenement local tardif
    // ne doit pas pouvoir le remplacer par l'heure d'ici.
    await _meta.put(id, json.encode(entry.stamp.toJson()));
    await _meta.flush();

    // Une ecriture sans effet ne produirait qu'un evenement a ignorer, et
    // ferait recharger la page pour rien.
    final current = box.read(key);
    if (entry.stamp.deleted) {
      if (current == null) {
        return false;
      }
      _applying.add(id);
      await box.delete(key);
      return true;
    }
    if (current == entry.value) {
      return false;
    }
    _applying.add(id);
    await box.write(key, entry.value!);
    return true;
  }

  Future<void> _export(Directory directory) async {
    if (!_enabled) {
      return;
    }
    final entries = <String, SyncEntry>{};
    for (final id in _meta.keys.whereType<String>()) {
      final stamp = SyncStamp.fromJson(_decode(_meta.get(id)));
      final slash = id.indexOf('/');
      if (stamp == null || slash <= 0) {
        continue;
      }
      final box = _boxes[id.substring(0, slash)];
      if (box == null) {
        continue;
      }
      if (stamp.deleted) {
        entries[id] = SyncEntry(stamp, null);
        continue;
      }
      final value = box.read(id.substring(slash + 1));
      if (value != null) {
        entries[id] = SyncEntry(stamp, value);
      }
    }
    final snapshot = DeviceSnapshot(
      device: deviceId,
      name: deviceName,
      writtenAt: _clock(),
      entries: entries,
    );

    // Ecrit a cote puis renomme : Syncthing ne doit jamais voir un fichier a
    // moitie ecrit. Le nom temporaire, cache, ne ressemble pas a un fichier
    // d'appareil et n'est donc jamais relu.
    // La barre oblique convient aussi a Windows, et evite `Platform`.
    final target = File('${directory.path}/$_ownFile');
    final temporary = File('${directory.path}/.$_ownFile.tmp');
    await temporary.writeAsString(snapshot.encode(), flush: true);
    await temporary.rename(target.path);
  }

  String _id(SyncedBox box, String key) => '${box.name}/$key';

  Object? _decode(String? raw) {
    if (raw == null) {
      return null;
    }
    try {
      return json.decode(raw);
    } on FormatException {
      return null;
    }
  }

  static String _newDeviceId() {
    final random = Random.secure();
    return List.generate(10, (_) => random.nextInt(36).toRadixString(36)).join();
  }
}
