import 'dart:convert';

/// Modeles renvoyes par l'agent de supervision du Raspberry Pi.
///
/// Dart pur, sans import Flutter, pour rester testable avec `package:test`.

class SystemStats {
  const SystemStats({
    this.hostname = '',
    this.model,
    this.kernel,
    this.uptimeSeconds = 0,
    this.load1 = 0,
    this.load5 = 0,
    this.load15 = 0,
    this.cpuTempC,
    this.memTotalBytes,
    this.memAvailableBytes,
    this.throttled = const ThrottleFlags(),
  });

  final String hostname;
  final String? model;
  final String? kernel;
  final int uptimeSeconds;
  final double load1;
  final double load5;
  final double load15;
  final double? cpuTempC;
  final int? memTotalBytes;
  final int? memAvailableBytes;
  final ThrottleFlags throttled;

  int? get memUsedBytes => (memTotalBytes == null || memAvailableBytes == null)
      ? null
      : memTotalBytes! - memAvailableBytes!;

  factory SystemStats.fromJson(Map<String, dynamic> json) => SystemStats(
        hostname: json['hostname'] as String? ?? '',
        model: json['model'] as String?,
        kernel: json['kernel'] as String?,
        uptimeSeconds: (json['uptime_seconds'] as num?)?.toInt() ?? 0,
        load1: (json['load_1'] as num?)?.toDouble() ?? 0,
        load5: (json['load_5'] as num?)?.toDouble() ?? 0,
        load15: (json['load_15'] as num?)?.toDouble() ?? 0,
        cpuTempC: (json['cpu_temp_c'] as num?)?.toDouble(),
        memTotalBytes: (json['mem_total_bytes'] as num?)?.toInt(),
        memAvailableBytes: (json['mem_available_bytes'] as num?)?.toInt(),
        throttled: ThrottleFlags.fromJson(json['throttled']),
      );

  factory SystemStats.fromBody(String body) {
    final decoded = jsonDecode(body);
    return decoded is Map<String, dynamic> ? SystemStats.fromJson(decoded) : const SystemStats();
  }
}

/// Drapeaux de bridage du Raspberry Pi.
///
/// La sous-tension est le diagnostic le plus utile de la page : une
/// alimentation trop faible provoque corruptions et services qui tombent, sans
/// jamais rien laisser dans les journaux applicatifs.
class ThrottleFlags {
  const ThrottleFlags({
    this.available = false,
    this.underVoltageNow = false,
    this.underVoltageOccurred = false,
    this.throttlingNow = false,
    this.throttlingOccurred = false,
  });

  final bool available;
  final bool underVoltageNow;
  final bool underVoltageOccurred;
  final bool throttlingNow;
  final bool throttlingOccurred;

  bool get hasWarning =>
      available &&
      (underVoltageNow || underVoltageOccurred || throttlingNow || throttlingOccurred);

  factory ThrottleFlags.fromJson(Object? raw) {
    if (raw is! Map<String, dynamic> || raw['available'] != true) {
      return const ThrottleFlags();
    }
    return ThrottleFlags(
      available: true,
      underVoltageNow: raw['under_voltage_now'] == true,
      underVoltageOccurred: raw['under_voltage_occurred'] == true,
      throttlingNow: raw['currently_throttled'] == true,
      throttlingOccurred: raw['throttling_occurred'] == true,
    );
  }
}

/// Etat d'un volume surveille.
class StorageVolume {
  const StorageVolume({
    required this.path,
    required this.label,
    required this.mounted,
    this.reason,
    this.device,
    this.fstype,
    this.readonly = false,
    this.totalBytes,
    this.usedBytes,
    this.freeBytes,
    this.quotaBytes,
    this.quotaFreeBytes,
    this.quotaRatio,
  });

  final String path;
  final String label;
  final bool mounted;

  /// `missing`, `not_mounted` ou `same_device_as_root` lorsque le volume est
  /// absent. `not_mounted` est le cas du disque debranche.
  final String? reason;
  final String? device;
  final String? fstype;
  final bool readonly;
  final int? totalBytes;
  final int? usedBytes;
  final int? freeBytes;
  final int? quotaBytes;
  final int? quotaFreeBytes;
  final double? quotaRatio;

  /// Vrai lorsqu'il est deraisonnable de lancer un nouveau telechargement :
  /// disque absent, en lecture seule, ou plafond atteint.
  bool get blocksDownloads =>
      !mounted || readonly || (quotaRatio != null && quotaRatio! >= 1.0);

  factory StorageVolume.fromJson(Map<String, dynamic> json) => StorageVolume(
        path: json['path'] as String? ?? '',
        label: json['label'] as String? ?? '',
        mounted: json['mounted'] == true,
        reason: json['reason'] as String?,
        device: json['device'] as String?,
        fstype: json['fstype'] as String?,
        readonly: json['readonly'] == true,
        totalBytes: (json['total_bytes'] as num?)?.toInt(),
        usedBytes: (json['used_bytes'] as num?)?.toInt(),
        freeBytes: (json['free_bytes'] as num?)?.toInt(),
        quotaBytes: (json['quota_bytes'] as num?)?.toInt(),
        quotaFreeBytes: (json['quota_free_bytes'] as num?)?.toInt(),
        quotaRatio: (json['quota_ratio'] as num?)?.toDouble(),
      );

  static List<StorageVolume> listFromBody(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic> || decoded['volumes'] is! List) {
      return const [];
    }
    return (decoded['volumes'] as List)
        .whereType<Map<String, dynamic>>()
        .map(StorageVolume.fromJson)
        .toList(growable: false);
  }
}

enum ServiceState {
  active,
  inactive,
  failed,
  activating,
  deactivating,
  unknown;

  static ServiceState fromApi(String? raw) => switch (raw) {
        'active' => active,
        'inactive' => inactive,
        'failed' => failed,
        'activating' => activating,
        'deactivating' => deactivating,
        _ => unknown,
      };

  bool get isRunning => this == active;
  bool get isTransitioning => this == activating || this == deactivating;
}

/// Interface web d'un service, telle que declaree dans la configuration de
/// l'agent.
///
/// L'agent ne connait pas l'hote : il ignore par quelle adresse le telephone
/// le joint — reseau local ou Tailscale. L'adresse complete n'est donc formee
/// qu'ici, avec l'hote des reglages.
class ServiceWeb {
  const ServiceWeb({required this.port, this.scheme = 'http', this.path = '/'});

  final int port;
  final String scheme;
  final String path;

  static ServiceWeb? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      return null;
    }
    final raw = json['port'];
    final port = raw is int ? raw : null;
    if (port == null || port < 1 || port > 65535) {
      return null;
    }
    final scheme = json['scheme'];
    final path = json['path'];
    return ServiceWeb(
      port: port,
      // Tout autre schema ouvrirait autre chose qu'un navigateur.
      scheme: scheme == 'https' ? 'https' : 'http',
      path: path is String && path.startsWith('/') ? path : '/',
    );
  }

  Uri uriFor(String host) => Uri.parse('$scheme://${_authority(host.trim())}:$port$path');

  /// Une adresse IPv6 litterale doit etre entre crochets devant le port.
  static String _authority(String host) =>
      host.contains(':') && !host.startsWith('[') ? '[$host]' : host;
}

class ServiceStatus {
  const ServiceStatus({
    required this.name,
    required this.unit,
    required this.state,
    this.subState = '',
    this.enabled = false,
    this.since,
    this.memoryBytes,
    this.web,
    this.actions = allActions,
  });

  static const Set<String> allActions = {'start', 'stop', 'restart'};

  final String name;
  final String unit;
  final ServiceState state;
  final String subState;
  final bool enabled;
  final String? since;
  final int? memoryBytes;
  final ServiceWeb? web;

  /// Actions que l'agent accepte pour ce service, parmi [allActions]. Un agent
  /// anterieur a ce champ ne l'envoie pas : tout est alors permis, comme avant.
  final Set<String> actions;

  static Set<String> _actionsFromJson(Object? json) {
    if (json is! List) {
      return allActions;
    }
    return json.whereType<String>().where(allActions.contains).toSet();
  }

  ServiceStatus copyWith({ServiceState? state}) => ServiceStatus(
        name: name,
        unit: unit,
        state: state ?? this.state,
        subState: subState,
        enabled: enabled,
        since: since,
        memoryBytes: memoryBytes,
        web: web,
        actions: actions,
      );

  factory ServiceStatus.fromJson(Map<String, dynamic> json) => ServiceStatus(
        name: json['name'] as String? ?? '',
        unit: json['unit'] as String? ?? '',
        state: ServiceState.fromApi(json['active_state'] as String?),
        subState: json['sub_state'] as String? ?? '',
        enabled: json['enabled'] == true,
        since: json['since'] as String?,
        memoryBytes: (json['memory_bytes'] as num?)?.toInt(),
        web: ServiceWeb.fromJson(json['web']),
        actions: _actionsFromJson(json['actions']),
      );

  static List<ServiceStatus> listFromBody(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic> || decoded['services'] is! List) {
      return const [];
    }
    return (decoded['services'] as List)
        .whereType<Map<String, dynamic>>()
        .map(ServiceStatus.fromJson)
        .toList(growable: false);
  }
}
