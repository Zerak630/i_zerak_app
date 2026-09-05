import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:i_zerak_app/services/qbittorrent/qb_client.dart';
import 'package:i_zerak_app/services/qbittorrent/qb_exceptions.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../../__mocks__/http_client_mock.dart' as mocks;

@GenerateMocks([http.Client])
void main() {
  final baseUri = Uri.parse('https://nas.lan:8080');
  final loginUri = Uri.parse('https://nas.lan:8080/api/v2/auth/login');

  late mocks.MockClient client;

  QbClient buildClient({Duration? timeout}) => QbClient(
        baseUri: baseUri,
        username: 'admin',
        password: 'secret',
        client: client,
        timeout: timeout ?? const Duration(seconds: 8),
      );

  void stubLogin({
    int statusCode = 200,
    String body = 'Ok.',
    String? setCookie = 'SID=abc123; HttpOnly; path=/',
  }) {
    when(client.post(
      loginUri,
      headers: anyNamed('headers'),
      body: anyNamed('body'),
      encoding: anyNamed('encoding'),
    )).thenAnswer((_) async => http.Response(
          body,
          statusCode,
          headers: setCookie == null ? const {} : {'set-cookie': setCookie},
        ));
  }

  setUp(() {
    client = mocks.MockClient();
  });

  test('la connexion propage le cookie de session et les en-tetes CSRF', () async {
    stubLogin();
    when(client.get(any, headers: anyNamed('headers')))
        .thenAnswer((_) async => http.Response('[]', 200));

    final qb = buildClient();
    await qb.get('torrents/info');

    final headers =
        verify(client.get(any, headers: captureAnyNamed('headers'))).captured.single
            as Map<String, String>;

    // package:http ne gere aucun cookie : le SID doit avoir ete extrait puis
    // reinjecte a la main.
    expect(headers['Cookie'], 'SID=abc123');
    // qBittorrent rejette les requetes dont Referer ne designe pas l'hote vise.
    expect(headers['Referer'], 'https://nas.lan:8080');
    expect(headers['Origin'], 'https://nas.lan:8080');
  });

  test('un refus d identifiants leve QbAuthException', () async {
    // Le serveur repond 200 meme lorsqu'il refuse : seul le corps distingue.
    stubLogin(body: 'Fails.');

    expect(buildClient().login(), throwsA(isA<QbAuthException>()));
  });

  test('un cookie absent leve plutot que de laisser passer', () async {
    stubLogin(setCookie: null);

    expect(buildClient().login(), throwsA(isA<QbAuthException>()));
  });

  test('un bannissement se distingue d un refus d identifiants', () async {
    // La conduite a tenir differe : il faut attendre, pas ressaisir le mot de
    // passe. D'ou deux types d'exception.
    stubLogin(statusCode: 403, body: '');

    expect(buildClient().login(), throwsA(isA<QbBannedException>()));
  });

  test('une session expiree declenche une reconnexion et un rejeu', () async {
    stubLogin();
    var calls = 0;
    when(client.get(any, headers: anyNamed('headers'))).thenAnswer((_) async {
      calls++;
      return calls == 1 ? http.Response('', 403) : http.Response('[]', 200);
    });

    final response = await buildClient().get('torrents/info');

    expect(response.statusCode, 200);
    // Connexion initiale, puis reconnexion apres le refus.
    verify(client.post(loginUri,
            headers: anyNamed('headers'),
            body: anyNamed('body'),
            encoding: anyNamed('encoding')))
        .called(2);
    verify(client.get(any, headers: anyNamed('headers'))).called(2);
  });

  test('un refus persistant ne boucle pas', () async {
    stubLogin();
    when(client.get(any, headers: anyNamed('headers')))
        .thenAnswer((_) async => http.Response('', 403));

    await expectLater(
      buildClient().get('torrents/info'),
      throwsA(isA<QbAuthException>()),
    );

    // Exactement deux connexions : c'est le test qui protege du bannissement
    // de l'adresse. qBittorrent bannit au bout de cinq echecs.
    verify(client.post(loginUri,
            headers: anyNamed('headers'),
            body: anyNamed('body'),
            encoding: anyNamed('encoding')))
        .called(2);
  });

  test('un endpoint absent est signale a part, pour permettre la bascule', () async {
    stubLogin();
    when(client.post(argThat(isNot(loginUri)),
            headers: anyNamed('headers'),
            body: anyNamed('body'),
            encoding: anyNamed('encoding')))
        .thenAnswer((_) async => http.Response('', 404));

    expect(
      buildClient().postForm('torrents/stop', const {'hashes': 'abc'}),
      throwsA(isA<QbUnsupportedEndpointException>()),
    );
  });

  test('une panne reseau devient une exception typee', () async {
    stubLogin();
    when(client.get(any, headers: anyNamed('headers')))
        .thenThrow(const SocketException('Connexion refusee'));

    expect(buildClient().get('torrents/info'), throwsA(isA<QbNetworkException>()));
  });

  test('un certificat refuse se distingue d une panne reseau', () async {
    stubLogin();
    when(client.get(any, headers: anyNamed('headers')))
        .thenThrow(http.ClientException('HandshakeException: certificate verify failed'));

    expect(buildClient().get('torrents/info'), throwsA(isA<QbCertificateException>()));
  });

  test('un depassement de delai devient QbTimeoutException', () async {
    stubLogin();
    when(client.get(any, headers: anyNamed('headers'))).thenAnswer(
      (_) => Future.delayed(const Duration(seconds: 5), () => http.Response('[]', 200)),
    );

    expect(
      buildClient(timeout: const Duration(milliseconds: 50)).get('torrents/info'),
      throwsA(isA<QbTimeoutException>()),
    );
  });

  test('les connexions concurrentes sont serialisees', () async {
    stubLogin();
    when(client.get(any, headers: anyNamed('headers')))
        .thenAnswer((_) async => http.Response('[]', 200));

    final qb = buildClient();
    // Sans serialisation, trois requetes simultanees ouvriraient trois
    // sessions et rapprocheraient d'autant le bannissement.
    await Future.wait([
      qb.get('torrents/info'),
      qb.get('transfer/info'),
      qb.get('app/version'),
    ]);

    verify(client.post(loginUri,
            headers: anyNamed('headers'),
            body: anyNamed('body'),
            encoding: anyNamed('encoding')))
        .called(1);
  });
}
