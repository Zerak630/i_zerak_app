/// Le format du fichier partage, et la regle qui tranche entre deux versions.
///
/// Dart pur : ni Hive ni systeme de fichiers, la fusion se teste seule.
library;

import 'dart:convert';

/// Version du format. Un fichier d'une version inconnue est ignore plutot que
/// mal relu.
const int syncFormat = 1;

/// Horodatage pose avant toute synchro sur les entrees deja presentes.
///
/// Le plus petit possible : n'importe quelle ecriture reelle, sur n'importe
/// quel appareil, l'emporte sur lui. Deux appareils qui ont chacun des donnees
/// anterieures gardent les leurs (egalite) au lieu de s'ecraser l'un l'autre.
const int legacyStamp = 1;

/// Ce que l'on sait d'une entree : quand elle a change, et si c'etait une
/// suppression.
class SyncStamp {
  const SyncStamp(this.t, {this.deleted = false});

  final int t;
  final bool deleted;

  static SyncStamp? fromJson(Object? raw) {
    if (raw is! Map || raw['t'] is! int) {
      return null;
    }
    return SyncStamp(raw['t'] as int, deleted: raw['d'] == true);
  }

  Map<String, Object?> toJson() => {'t': t, if (deleted) 'd': true};
}

/// Une entree du fichier : son horodatage, et sa valeur si elle existe.
class SyncEntry {
  const SyncEntry(this.stamp, this.value);

  final SyncStamp stamp;

  /// Nulle pour une suppression.
  final String? value;

  Map<String, Object?> toJson() => {...stamp.toJson(), if (value != null) 'v': value};

  static SyncEntry? fromJson(Object? raw) {
    final stamp = SyncStamp.fromJson(raw);
    if (stamp == null) {
      return null;
    }
    final value = (raw as Map)['v'];
    // Une entree ni supprimee ni porteuse d'une chaine n'a rien a appliquer.
    if (!stamp.deleted && value is! String) {
      return null;
    }
    return SyncEntry(stamp, stamp.deleted ? null : value as String);
  }
}

/// Le fichier d'un appareil : qui il est, quand il a ecrit, et tout ce qu'il
/// sait, suppressions comprises.
class DeviceSnapshot {
  const DeviceSnapshot({
    required this.device,
    required this.name,
    required this.writtenAt,
    required this.entries,
  });

  final String device;
  final String name;
  final DateTime writtenAt;

  /// Indexees par `<boite>/<cle>`.
  final Map<String, SyncEntry> entries;

  String encode() => json.encode({
        'format': syncFormat,
        'device': device,
        'name': name,
        'writtenAt': writtenAt.toUtc().toIso8601String(),
        'entries': {for (final e in entries.entries) e.key: e.value.toJson()},
      });

  /// Nul si le fichier est illisible, d'un autre format, ou sans appareil.
  /// Une entree abimee est sautee sans faire tomber les autres.
  static DeviceSnapshot? decode(String source) {
    Object? raw;
    try {
      raw = json.decode(source);
    } on FormatException {
      return null;
    }
    if (raw is! Map || raw['format'] != syncFormat || raw['device'] is! String) {
      return null;
    }
    final entries = <String, SyncEntry>{};
    final rawEntries = raw['entries'];
    if (rawEntries is Map) {
      for (final e in rawEntries.entries) {
        if (e.key case final String id) {
          if (SyncEntry.fromJson(e.value) case final SyncEntry entry) {
            entries[id] = entry;
          }
        }
      }
    }
    return DeviceSnapshot(
      device: raw['device'] as String,
      name: raw['name'] is String ? raw['name'] as String : raw['device'] as String,
      writtenAt: DateTime.tryParse('${raw['writtenAt']}') ?? DateTime.fromMillisecondsSinceEpoch(0),
      entries: entries,
    );
  }
}

/// La version distante remplace la locale seulement si elle est strictement
/// plus recente. A egalite, rien ne bouge : c'est ce qui rend l'importation
/// idempotente, et ce qui protege les donnees anterieures a la synchro.
bool remoteWins(SyncStamp? local, SyncStamp remote) => local == null || remote.t > local.t;
