import 'dart:convert';

/// Etat global des transferts, renvoye par `GET /api/v2/transfer/info`.
class TransferInfoDao {
  const TransferInfoDao({
    this.dlInfoSpeed = 0,
    this.dlInfoData = 0,
    this.upInfoSpeed = 0,
    this.upInfoData = 0,
    this.connectionStatus = ConnectionStatus.unknown,
  });

  final int dlInfoSpeed;
  final int dlInfoData;
  final int upInfoSpeed;
  final int upInfoData;
  final ConnectionStatus connectionStatus;

  factory TransferInfoDao.fromJson(Map<String, dynamic> json) => TransferInfoDao(
        dlInfoSpeed: (json['dl_info_speed'] as num?)?.toInt() ?? 0,
        dlInfoData: (json['dl_info_data'] as num?)?.toInt() ?? 0,
        upInfoSpeed: (json['up_info_speed'] as num?)?.toInt() ?? 0,
        upInfoData: (json['up_info_data'] as num?)?.toInt() ?? 0,
        connectionStatus: ConnectionStatus.fromApi(json['connection_status'] as String?),
      );

  factory TransferInfoDao.fromBody(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      return const TransferInfoDao();
    }
    return TransferInfoDao.fromJson(decoded);
  }
}

enum ConnectionStatus {
  connected,

  /// Connecte, mais aucune connexion entrante : le port n'est pas joignable
  /// depuis l'exterieur, ce qui degrade fortement les vitesses.
  firewalled,
  disconnected,
  unknown;

  static ConnectionStatus fromApi(String? raw) => switch (raw) {
        'connected' => connected,
        'firewalled' => firewalled,
        'disconnected' => disconnected,
        _ => unknown,
      };
}
