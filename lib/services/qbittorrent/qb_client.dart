import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:i_zerak_app/services/qbittorrent/qb_exceptions.dart';

/// Transport bas niveau vers l'API WebUI de qBittorrent.
///
/// Ne connait ni le conteneur d'injection, ni Hive, ni le magasin de secrets :
/// tout lui est fourni au constructeur, ce qui le rend integralement testable
/// avec un `http.Client` simule.
class QbClient {
  QbClient({
    required this.baseUri,
    required this.username,
    required this.password,
    http.Client? client,
    this.timeout = const Duration(seconds: 8),
  }) : _client = client ?? http.Client();

  final Uri baseUri;
  final String username;
  final String password;
  final Duration timeout;

  final http.Client _client;

  String? _sid;
  Future<void>? _loginInFlight;

  bool get isAuthenticated => _sid != null;

  void resetSession() => _sid = null;

  void close() => _client.close();

  String get _origin => baseUri.origin;

  Uri uri(String path, [Map<String, String>? query]) => baseUri.replace(
        path: '/api/v2/$path',
        queryParameters: (query == null || query.isEmpty) ? null : query,
      );

  /// qBittorrent rejette les requetes dont Referer et Origin ne designent pas
  /// l'hote vise : c'est sa protection contre le CSRF depuis un autre site.
  Map<String, String> _headers({bool withSession = true, Map<String, String>? extra}) {
    final headers = <String, String>{'Referer': _origin, 'Origin': _origin};
    final sid = _sid;
    if (withSession && sid != null) {
      headers['Cookie'] = 'SID=$sid';
    }
    if (extra != null) {
      headers.addAll(extra);
    }
    return headers;
  }

  /// Ouvre une session, ou rend celle deja en cours d'ouverture.
  ///
  /// La serialisation est essentielle : avec un rafraichissement toutes les
  /// trois secondes, plusieurs requetes peuvent se voir refusees en meme temps
  /// et declencher autant de connexions simultanees. qBittorrent bannit
  /// l'adresse au bout de cinq echecs, ce qui rendrait l'application et
  /// l'interface web inutilisables depuis l'appareil.
  Future<void> login() {
    return _loginInFlight ??= _performLogin().whenComplete(() => _loginInFlight = null);
  }

  Future<void> _performLogin() async {
    _sid = null;

    final response = await _guard(() => _client.post(
          uri('auth/login'),
          headers: _headers(
            withSession: false,
            extra: const {'Content-Type': 'application/x-www-form-urlencoded'},
          ),
          body: <String, String>{'username': username, 'password': password},
        ));

    if (response.statusCode == 403) {
      throw const QbBannedException();
    }
    if (response.statusCode != 200) {
      throw QbHttpException(response.statusCode, 'Echec de la connexion au serveur');
    }
    // Le serveur repond 200 meme lorsqu'il refuse : seul le corps distingue.
    if (response.body.trim() != 'Ok.') {
      throw const QbAuthException();
    }

    _sid = _extractSid(response.headers['set-cookie']);
    if (_sid == null) {
      throw const QbAuthException('Cookie de session absent de la reponse');
    }
  }

  /// `package:http` ne gere aucun cookie : le SID doit etre extrait puis
  /// reinjecte a la main.
  ///
  /// Attention en cas de reutilisation ailleurs : `dart:io` concatene plusieurs
  /// en-tetes `Set-Cookie` avec une virgule, et les dates `Expires` en
  /// contiennent elles-memes. Ce parsing ne tient que parce que qBittorrent
  /// n'emet qu'un seul cookie.
  static String? _extractSid(String? setCookieHeader) {
    if (setCookieHeader == null) {
      return null;
    }
    final match = RegExp(r'SID=([^;,\s]+)').firstMatch(setCookieHeader);
    return match?.group(1);
  }

  Future<http.Response> get(String path, [Map<String, String>? query]) =>
      _authorized((headers) => _client.get(uri(path, query), headers: headers));

  Future<http.Response> postForm(String path, Map<String, String> fields) =>
      _authorized((headers) => _client.post(
            uri(path),
            headers: {...headers, 'Content-Type': 'application/x-www-form-urlencoded'},
            body: fields,
          ));

  Future<http.Response> postMultipart(String path, Map<String, String> fields) =>
      _authorized((headers) async {
        final request = http.MultipartRequest('POST', uri(path))
          ..headers.addAll(headers)
          ..fields.addAll(fields);
        return http.Response.fromStream(await _client.send(request));
      });

  /// Envoie une requete authentifiee, en rejouant une seule fois si la session
  /// a expire.
  Future<http.Response> _authorized(
    Future<http.Response> Function(Map<String, String> headers) send,
  ) async {
    if (_sid == null) {
      await login();
    }

    var response = await _guard(() => send(_headers()));

    if (response.statusCode == 403) {
      // Le drapeau de rejeu est local a l'appel, et non un champ partage :
      // deux requetes concurrentes pourraient sinon se relancer mutuellement.
      resetSession();
      await login();
      response = await _guard(() => send(_headers()));
      if (response.statusCode == 403) {
        throw const QbAuthException('Session refusee apres reconnexion');
      }
    }

    // Sert a detecter les endpoints renommes entre versions majeures.
    if (response.statusCode == 404 || response.statusCode == 405) {
      throw QbUnsupportedEndpointException('Endpoint absent (${response.statusCode})');
    }
    if (response.statusCode >= 400) {
      throw QbHttpException(response.statusCode);
    }
    return response;
  }

  /// Traduit les pannes de transport en exceptions typees, pour que l'interface
  /// n'ait jamais a afficher un message technique brut.
  Future<http.Response> _guard(Future<http.Response> Function() action) async {
    try {
      return await action().timeout(timeout);
    } on TimeoutException {
      throw const QbTimeoutException();
    } on HandshakeException catch (error) {
      throw QbCertificateException('Certificat refuse : ${error.message}');
    } on SocketException catch (error) {
      throw QbNetworkException(error.message.isEmpty ? 'Serveur injoignable' : error.message);
    } on http.ClientException catch (error) {
      // IOClient enveloppe les erreurs TLS : sans ce test, un certificat change
      // remonterait comme une panne reseau ordinaire et le message serait faux.
      if (error.message.contains('HandshakeException') ||
          error.message.contains('CERTIFICATE') ||
          error.message.contains('certificate')) {
        throw QbCertificateException('Certificat refuse : ${error.message}');
      }
      throw QbNetworkException(error.message);
    }
  }
}
