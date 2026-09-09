import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:i_zerak_app/models/server_config_dao.dart';
import 'package:i_zerak_app/models/torrent_dao.dart';
import 'package:i_zerak_app/models/transfer_info_dao.dart';
import 'package:i_zerak_app/services/qbittorrent/qb_client.dart';
import 'package:i_zerak_app/services/qbittorrent/qb_exceptions.dart';
import 'package:i_zerak_app/services/qbittorrent/qb_http_client_factory.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_credentials.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_server_config.dart';

/// Instantane complet de l'etat des transferts.
typedef TorrentsSnapshot = ({List<TorrentDao> torrents, TransferInfoDao transfer});

/// API typee de qBittorrent, au-dessus de [QbClient].
///
/// Resout la configuration et le mot de passe a la demande, et conserve le
/// client construit jusqu'au prochain [invalidate].
class QbService {
  QbService({
    required IServerConfig config,
    required ICredentials credentials,
    http.Client Function(ServerConfig config)? clientFactory,
  })  : _config = config,
        _credentials = credentials,
        _clientFactory = clientFactory;

  final IServerConfig _config;
  final ICredentials _credentials;

  /// Injectable pour les tests : permet de substituer un `http.Client` simule
  /// au client epingle.
  final http.Client Function(ServerConfig config)? _clientFactory;

  QbClient? _cached;

  /// Nom d'endpoint retenu apres le premier succes, pour ne pas retenter la
  /// bascule a chaque action.
  String? _resolvedPause;
  String? _resolvedResume;

  /// A appeler des que la configuration change : vide la session et le client
  /// mis en cache.
  void invalidate() {
    _cached?.resetSession();
    _cached = null;
    _resolvedPause = null;
    _resolvedResume = null;
  }

  Future<QbClient> _resolve() async {
    final cached = _cached;
    if (cached != null) {
      return cached;
    }

    final config = await _config.read();
    if (config == null || !config.isComplete) {
      throw const QbNotConfiguredException();
    }
    final password = await _credentials.read(SecretKey.qbPassword);
    if (password == null || password.isEmpty) {
      throw const QbNotConfiguredException('Mot de passe absent');
    }

    return _cached = _buildClient(config, password);
  }

  QbClient _buildClient(ServerConfig config, String password) => QbClient(
        baseUri: config.baseUri,
        username: config.username,
        password: password,
        client: _clientFactory?.call(config) ?? _defaultClient(config),
      );

  http.Client _defaultClient(ServerConfig config) {
    if (!config.useHttps) {
      return buildPlainClient();
    }
    return buildPinnedClient(pinnedSha256: config.pinnedCertSha256);
  }

  /// Version du serveur, renvoyee en texte brut et non en JSON.
  Future<String> appVersion() async {
    final client = await _resolve();
    final response = await client.get('app/version');
    return response.body.trim();
  }

  /// Verifie une configuration sans l'enregistrer ni toucher au client en
  /// cache, pour que l'ecran de reglages puisse tester avant de valider.
  ///
  /// En cas de certificat non approuve, l'exception porte l'empreinte presentee
  /// afin que l'interface puisse proposer son adoption.
  Future<String> testConnection(ServerConfig config, String password) async {
    String? presented;
    final httpClient = _clientFactory?.call(config) ??
        (config.useHttps
            ? buildPinnedClient(
                pinnedSha256: config.pinnedCertSha256,
                onUntrustedCertificate: (fingerprint) => presented = fingerprint,
              )
            : buildPlainClient());

    final client = QbClient(
      baseUri: config.baseUri,
      username: config.username,
      password: password,
      client: httpClient,
    );

    try {
      await client.login();
      final response = await client.get('app/version');
      return response.body.trim();
    } on QbCertificateException catch (error) {
      throw QbCertificateException(error.message, presentedFingerprint: presented);
    } on QbNetworkException catch (error) {
      // Selon la plateforme, un certificat refuse peut remonter en panne
      // reseau ordinaire. L'empreinte captee tranche sans ambiguite.
      if (presented != null) {
        throw QbCertificateException(error.message, presentedFingerprint: presented);
      }
      rethrow;
    } finally {
      client.close();
    }
  }

  Future<List<TorrentDao>> torrents({String filter = 'all', String sort = 'name'}) async {
    final client = await _resolve();
    final response = await client.get('torrents/info', {'filter': filter, 'sort': sort});
    return TorrentDao.listFromBody(response.body);
  }

  Future<TransferInfoDao> transferInfo() async {
    final client = await _resolve();
    final response = await client.get('transfer/info');
    return TransferInfoDao.fromBody(response.body);
  }

  /// Les deux appels du rafraichissement, groupes derriere une signature unique
  /// pour qu'une implementation fondee sur `sync/maindata` puisse s'y
  /// substituer sans toucher aux appelants.
  Future<TorrentsSnapshot> snapshot({String filter = 'all'}) async {
    final torrentList = await torrents(filter: filter);
    final transfer = await transferInfo();
    return (torrents: torrentList, transfer: transfer);
  }

  /// Ajoute un magnet, ou une URL de fichier torrent.
  ///
  /// `autoTmm` et `createSubfolder` sont **nullables a dessein** : cote
  /// qBittorrent, `autoTMM` et `root_folder` sont des tri-etats, et un champ
  /// absent laisse le reglage de session decider. Envoyer `false` par defaut
  /// « pour faire propre » changerait le comportement du serveur.
  ///
  /// L'inverse est tout aussi vrai : quand on fournit un `savePath`, il faut
  /// envoyer `autoTMM=false` explicitement. Un serveur regle en gestion
  /// automatique ignore sinon `savepath` **en silence**, au profit du chemin de
  /// la categorie. Voir `resolveAddOptions` dans `torrent_destination.dart`,
  /// qui est le seul endroit ou cette decision se prend.
  Future<void> addMagnet(
    String magnet, {
    String? savePath,
    String? category,
    bool? autoTmm,
    bool? createSubfolder,
  }) async {
    final client = await _resolve();
    final fields = <String, String>{'urls': magnet};
    if (savePath != null && savePath.isNotEmpty) {
      fields['savepath'] = savePath;
    }
    if (category != null && category.isNotEmpty) {
      fields['category'] = category;
    }
    if (autoTmm != null) {
      fields['autoTMM'] = autoTmm ? 'true' : 'false';
    }
    if (createSubfolder != null) {
      // `root_folder` est le nom du champ jusqu'a qBittorrent 4.3.1 ; le Pi
      // tourne en 4.2.5, verifie sur le binaire installe. Les versions plus
      // recentes lisent `contentLayout` a la place et ignorent silencieusement
      // les champs qu'elles ne connaissent pas.
      fields['root_folder'] = createSubfolder ? 'true' : 'false';
    }
    await client.postMultipart('torrents/add', fields);
  }

  Future<void> pause(List<String> hashes) async {
    _resolvedPause = await _callWithLegacyFallback(
      modern: 'torrents/stop',
      legacy: 'torrents/pause',
      resolved: _resolvedPause,
      fields: {'hashes': hashes.join('|')},
    );
  }

  Future<void> resume(List<String> hashes) async {
    _resolvedResume = await _callWithLegacyFallback(
      modern: 'torrents/start',
      legacy: 'torrents/resume',
      resolved: _resolvedResume,
      fields: {'hashes': hashes.join('|')},
    );
  }

  Future<void> delete(List<String> hashes, {required bool deleteFiles}) async {
    final client = await _resolve();
    await client.postForm('torrents/delete', {
      'hashes': hashes.join('|'),
      // Attendu comme chaine, pas comme booleen JSON.
      'deleteFiles': deleteFiles ? 'true' : 'false',
    });
  }

  /// qBittorrent 5 a renomme `torrents/pause` en `torrents/stop` et
  /// `torrents/resume` en `torrents/start`. La version du serveur n'etant pas
  /// connue d'avance, on tente le nom moderne, on retombe sur l'ancien, et on
  /// retient celui qui a fonctionne.
  Future<String> _callWithLegacyFallback({
    required String modern,
    required String legacy,
    required String? resolved,
    required Map<String, String> fields,
  }) async {
    final client = await _resolve();

    if (resolved != null) {
      await client.postForm(resolved, fields);
      return resolved;
    }

    try {
      await client.postForm(modern, fields);
      return modern;
    } on QbUnsupportedEndpointException {
      await client.postForm(legacy, fields);
      return legacy;
    }
  }

  /// Espace disque libre annonce par le serveur, en octets. Null si la version
  /// en place ne l'expose pas.
  Future<int?> freeSpaceOnDisk() async {
    final client = await _resolve();
    final response = await client.get('sync/maindata', {'rid': '0'});
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    final serverState = decoded['server_state'];
    if (serverState is! Map<String, dynamic>) {
      return null;
    }
    return (serverState['free_space_on_disk'] as num?)?.toInt();
  }
}
