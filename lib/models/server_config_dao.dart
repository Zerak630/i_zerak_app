import 'package:hive/hive.dart';

/// Configuration du serveur auto-heberge : qBittorrent et l'agent de
/// supervision vivent sur la meme machine et partagent donc l'hote, le schema
/// et le certificat epingle. Seul le port differe.
///
/// Dart pur, sans import Flutter, pour rester testable avec `package:test`.
/// Le `TypeAdapter` correspondant est ecrit a la main dans
/// `lib/services/repositories/hive/type_adapters.dart` (identifiant de type 2).
@HiveType(typeId: 2)
class ServerConfig {
  @HiveField(0)
  String host;

  @HiveField(1)
  int port;

  @HiveField(2)
  bool useHttps;

  @HiveField(3)
  String username;

  /// Zero desactive le rafraichissement automatique.
  @HiveField(4)
  int pollIntervalSeconds;

  /// Racine de la bibliotheque Emby sur le serveur, ou seront deposes les
  /// telechargements.
  @HiveField(5)
  String? defaultSavePath;

  @HiveField(6)
  String? defaultCategory;

  /// Empreinte SHA-256 du certificat accepte, au format hexadecimal minuscule.
  /// Nulle tant qu'aucun certificat n'a ete approuve.
  @HiveField(7)
  String? pinnedCertSha256;

  @HiveField(8)
  int agentPort;

  ServerConfig({
    this.host = '',
    this.port = 8080,
    this.useHttps = true,
    this.username = '',
    this.pollIntervalSeconds = 3,
    this.defaultSavePath,
    this.defaultCategory,
    this.pinnedCertSha256,
    this.agentPort = 8081,
  });

  static const int _minPort = 1;
  static const int _maxPort = 65535;

  static bool isValidPort(int value) => value >= _minPort && value <= _maxPort;

  bool get isComplete => host.trim().isNotEmpty && isValidPort(port);

  bool get isAgentConfigured => host.trim().isNotEmpty && isValidPort(agentPort);

  /// Vrai lorsque l'hote est une adresse IPv4 litterale. Utile pour avertir
  /// l'utilisateur : un certificat auto-signe doit alors porter cette adresse
  /// dans son extension subjectAltName, faute de quoi la connexion echouera.
  bool get hostIsRawIpv4 => RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host.trim());

  String get _scheme => useHttps ? 'https' : 'http';

  Uri get baseUri => Uri(scheme: _scheme, host: host.trim(), port: port);

  Uri get agentBaseUri => Uri(scheme: _scheme, host: host.trim(), port: agentPort);

  /// qBittorrent refuse les requetes dont l'en-tete Referer ne correspond pas a
  /// l'hote vise : c'est sa protection contre le CSRF depuis un autre site.
  String get origin => baseUri.origin;

  /// Point unique de construction des URL qBittorrent. Concentrer la
  /// construction ici garantit qu'aucune adresse n'est ecrite ailleurs.
  Uri api(String path, [Map<String, String>? query]) => baseUri.replace(
        path: '/api/v2/$path',
        queryParameters: (query == null || query.isEmpty) ? null : query,
      );

  Uri agentApi(String path, [Map<String, String>? query]) => agentBaseUri.replace(
        path: '/api/v1/$path',
        queryParameters: (query == null || query.isEmpty) ? null : query,
      );

  ServerConfig copyWith({
    String? host,
    int? port,
    bool? useHttps,
    String? username,
    int? pollIntervalSeconds,
    String? defaultSavePath,
    String? defaultCategory,
    String? pinnedCertSha256,
    int? agentPort,
    bool clearPinnedCert = false,
  }) =>
      ServerConfig(
        host: host ?? this.host,
        port: port ?? this.port,
        useHttps: useHttps ?? this.useHttps,
        username: username ?? this.username,
        pollIntervalSeconds: pollIntervalSeconds ?? this.pollIntervalSeconds,
        defaultSavePath: defaultSavePath ?? this.defaultSavePath,
        defaultCategory: defaultCategory ?? this.defaultCategory,
        pinnedCertSha256: clearPinnedCert ? null : (pinnedCertSha256 ?? this.pinnedCertSha256),
        agentPort: agentPort ?? this.agentPort,
      );

  @override
  String toString() => 'ServerConfig($_scheme://$host:$port, agent:$agentPort, '
      'user:$username, poll:${pollIntervalSeconds}s, pinned:${pinnedCertSha256 != null})';
}
