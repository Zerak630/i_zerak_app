import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:i_zerak_app/models/server_config_dao.dart';
import 'package:i_zerak_app/services/qbittorrent/qb_service.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_credentials.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_server_config.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../../__mocks__/http_client_mock.dart' as mocks;

/// Les deux interfaces n'ont que trois methodes chacune : un faux ecrit a la
/// main coute moins cher qu'un mock genere.
class _FakeConfig implements IServerConfig {
  _FakeConfig(this._config);
  final ServerConfig? _config;

  @override
  Future<ServerConfig?> read() async => _config;

  @override
  Future<void> save(ServerConfig config) async {}

  @override
  Future<void> clear() async {}
}

class _FakeCredentials implements ICredentials {
  @override
  Future<String?> read(SecretKey key) async => 'secret';

  @override
  Future<void> write(SecretKey key, String value) async {}

  @override
  Future<void> delete(SecretKey key) async {}
}

void main() {
  final loginUri = Uri.parse('https://nas.lan:8080/api/v2/auth/login');

  late mocks.MockClient client;

  QbService buildService() => QbService(
        config: _FakeConfig(ServerConfig(host: 'nas.lan', port: 8080)),
        credentials: _FakeCredentials(),
        clientFactory: (_) => client,
      );

  void stubLogin() {
    when(client.post(
      loginUri,
      headers: anyNamed('headers'),
      body: anyNamed('body'),
      encoding: anyNamed('encoding'),
    )).thenAnswer((_) async => http.Response(
          'Ok.',
          200,
          headers: const {'set-cookie': 'SID=abc123; HttpOnly; path=/'},
        ));
  }

  /// `torrents/add` passe par une requete multipart, donc par `send`.
  void stubSend() {
    when(client.send(any)).thenAnswer((_) async => http.StreamedResponse(
          const Stream<List<int>>.empty(),
          200,
        ));
  }

  /// Les champs effectivement transmis a qBittorrent.
  Future<Map<String, String>> capturedFields() async {
    final request = verify(client.send(captureAny)).captured.single as http.MultipartRequest;
    return request.fields;
  }

  setUp(() {
    client = mocks.MockClient();
    stubLogin();
    stubSend();
  });

  test('l ajout vise torrents/add et porte les en-tetes anti-CSRF', () async {
    await buildService().addMagnet('magnet:?xt=urn:btih:abc');

    final request = verify(client.send(captureAny)).captured.single as http.MultipartRequest;
    expect(request.url.path, '/api/v2/torrents/add');
    expect(request.fields['urls'], 'magnet:?xt=urn:btih:abc');
    // qBittorrent refuse toute requete dont le Referer ne correspond pas a
    // l'hote vise : c'est sa protection contre le CSRF depuis un autre site.
    expect(request.headers['Referer'], 'https://nas.lan:8080');
    expect(request.headers['Origin'], 'https://nas.lan:8080');
  });

  test('autoTMM vaut false des qu un chemin est impose', () async {
    // Sans ce champ, un serveur regle en gestion automatique ignore savepath
    // en silence, au profit du chemin de la categorie : le dossier Emby est
    // perdu, sans le moindre message d'erreur.
    await buildService().addMagnet(
      'magnet:?xt=urn:btih:abc',
      savePath: '/srv/nas1/Emby/Films/Un film (2024) [tmdbid=42]',
      category: 'Films',
      autoTmm: false,
      createSubfolder: false,
    );

    final fields = await capturedFields();
    expect(fields['savepath'], '/srv/nas1/Emby/Films/Un film (2024) [tmdbid=42]');
    expect(fields['category'], 'Films');
    expect(fields['autoTMM'], 'false');
    expect(fields['root_folder'], 'false');
  });

  test('un tri-etat nul est absent des champs, il ne vaut pas false', () async {
    // Cote qBittorrent, autoTMM et root_folder sont des tri-etats : un champ
    // absent laisse le reglage de session decider. Envoyer 'false' par defaut
    // changerait le comportement du serveur.
    await buildService().addMagnet('magnet:?xt=urn:btih:abc', category: 'Autres');

    final fields = await capturedFields();
    expect(fields.containsKey('autoTMM'), isFalse);
    expect(fields.containsKey('root_folder'), isFalse);
  });

  test('autoTMM vaut true quand on rend la main au serveur', () async {
    await buildService().addMagnet(
      'magnet:?xt=urn:btih:abc',
      category: 'Series',
      autoTmm: true,
    );

    final fields = await capturedFields();
    expect(fields['autoTMM'], 'true');
    expect(fields.containsKey('savepath'), isFalse);
  });

  test('les champs vides ne sont pas transmis', () async {
    await buildService().addMagnet('magnet:?xt=urn:btih:abc', savePath: '', category: '');

    final fields = await capturedFields();
    expect(fields.containsKey('savepath'), isFalse);
    expect(fields.containsKey('category'), isFalse);
    expect(fields.keys, ['urls']);
  });
}
