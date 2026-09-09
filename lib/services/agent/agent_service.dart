import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:i_zerak_app/models/agent_dao.dart';
import 'package:i_zerak_app/models/server_config_dao.dart';
import 'package:i_zerak_app/services/qbittorrent/qb_exceptions.dart';
import 'package:i_zerak_app/services/qbittorrent/qb_http_client_factory.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_credentials.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_server_config.dart';

/// Instantane de l'etat du Raspberry Pi.
typedef SystemSnapshot = ({
  SystemStats stats,
  List<StorageVolume> volumes,
  List<ServiceStatus> services,
});

enum ServiceCommand { start, stop, restart }

/// Client de l'agent de supervision installe sur le Raspberry Pi.
///
/// Reutilise deliberement la hierarchie d'exceptions de qBittorrent : les deux
/// services vivent sur la meme machine, derriere le meme certificat, et
/// l'interface peut ainsi n'avoir qu'un seul `switch` exhaustif pour traduire
/// les erreurs.
class AgentService {
  AgentService({
    required IServerConfig config,
    required ICredentials credentials,
    http.Client Function(ServerConfig config)? clientFactory,
    this.timeout = const Duration(seconds: 8),
  })  : _config = config,
        _credentials = credentials,
        _clientFactory = clientFactory;

  final IServerConfig _config;
  final ICredentials _credentials;
  final http.Client Function(ServerConfig config)? _clientFactory;
  final Duration timeout;

  http.Client? _client;
  ServerConfig? _cachedConfig;
  String? _token;

  void invalidate() {
    _client?.close();
    _client = null;
    _cachedConfig = null;
    _token = null;
  }

  Future<({http.Client client, ServerConfig config, String token})> _resolve() async {
    var config = _cachedConfig;
    var token = _token;
    var client = _client;

    if (config == null || token == null || client == null) {
      config = await _config.read();
      if (config == null || !config.isAgentConfigured) {
        throw const QbNotConfiguredException();
      }
      token = await _credentials.read(SecretKey.agentToken);
      if (token == null || token.isEmpty) {
        throw const QbNotConfiguredException('Jeton de l\'agent absent');
      }
      client = _clientFactory?.call(config) ??
          (config.useHttps
              ? buildPinnedClient(pinnedSha256: config.pinnedCertSha256)
              : buildPlainClient());

      _cachedConfig = config;
      _token = token;
      _client = client;
    }

    return (client: client, config: config, token: token);
  }

  Map<String, String> _headers(String token) => {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      };

  Future<http.Response> _get(String path) async {
    final resolved = await _resolve();
    return _guard(() => resolved.client.get(
          resolved.config.agentApi(path),
          headers: _headers(resolved.token),
        ));
  }

  Future<SystemStats> system() async => SystemStats.fromBody((await _get('system')).body);

  Future<List<StorageVolume>> storage() async =>
      StorageVolume.listFromBody((await _get('storage')).body);

  Future<List<ServiceStatus>> services() async =>
      ServiceStatus.listFromBody((await _get('services')).body);

  Future<String> health() async => (await _get('health')).body;

  /// Verifie une configuration d'agent qui n'est pas encore enregistree.
  ///
  /// Le pendant de `QbService.testConnection` : l'ecran de reglages doit
  /// pouvoir eprouver le port et le jeton saisis avant que l'utilisateur ne
  /// valide, et distinguer un agent injoignable d'un jeton refuse. Retourne la
  /// version annoncee par l'agent.
  Future<String> testConnection(ServerConfig config, String token) async {
    if (token.trim().isEmpty) {
      throw const QbNotConfiguredException('Jeton de l\'agent absent');
    }

    String? presented;
    final client = _clientFactory?.call(config) ??
        (config.useHttps
            ? buildPinnedClient(
                pinnedSha256: config.pinnedCertSha256,
                onUntrustedCertificate: (fingerprint) => presented = fingerprint,
              )
            : buildPlainClient());

    try {
      final response = await _guard(() => client.get(
            config.agentApi('health'),
            headers: _headers(token.trim()),
          ));
      final decoded = jsonDecode(response.body);
      return (decoded is Map && decoded['version'] is String)
          ? decoded['version'] as String
          : '?';
    } on QbCertificateException catch (error) {
      throw QbCertificateException(error.message, presentedFingerprint: presented);
    } on QbNetworkException catch (error) {
      // Selon la plateforme, un certificat refuse remonte en simple panne
      // reseau. L'empreinte captee au passage tranche sans ambiguite.
      if (presented != null) {
        throw QbCertificateException(error.message, presentedFingerprint: presented);
      }
      rethrow;
    } finally {
      client.close();
    }
  }

  Future<SystemSnapshot> snapshot() async {
    final stats = await system();
    final volumes = await storage();
    final serviceList = await services();
    return (stats: stats, volumes: volumes, services: serviceList);
  }

  Future<ServiceStatus> command(String name, ServiceCommand command) async {
    final resolved = await _resolve();
    final response = await _guard(() => resolved.client.post(
          resolved.config.agentApi('services/$name/${command.name}'),
          headers: _headers(resolved.token),
        ));
    // La reponse est l'etat du service apres application.
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const QbHttpException(200, 'Reponse inattendue de l\'agent');
    }
    return ServiceStatus.fromJson(decoded);
  }

  Future<http.Response> _guard(Future<http.Response> Function() action) async {
    final http.Response response;
    try {
      response = await action().timeout(timeout);
    } on TimeoutException {
      throw const QbTimeoutException();
    } on HandshakeException catch (error) {
      throw QbCertificateException('Certificat refuse : ${error.message}');
    } on SocketException catch (error) {
      throw QbNetworkException(error.message.isEmpty ? 'Agent injoignable' : error.message);
    } on http.ClientException catch (error) {
      if (error.message.contains('HandshakeException') ||
          error.message.contains('certificate') ||
          error.message.contains('CERTIFICATE')) {
        throw QbCertificateException('Certificat refuse : ${error.message}');
      }
      throw QbNetworkException(error.message);
    }

    // 401 signifie un jeton absent ou faux : le rejouer ne servirait a rien.
    if (response.statusCode == 401) {
      throw const QbAuthException('Jeton de l\'agent refuse');
    }
    if (response.statusCode == 404) {
      throw const QbUnsupportedEndpointException('Service inconnu de l\'agent');
    }
    if (response.statusCode == 429) {
      throw const QbHttpException(429, 'Trop d\'actions, patientez');
    }
    if (response.statusCode >= 400) {
      throw QbHttpException(response.statusCode);
    }
    return response;
  }
}
