import 'package:i_zerak_app/models/server_config_dao.dart';

abstract class IServerConfig {
  /// Nul tant qu'aucune configuration n'a ete enregistree.
  Future<ServerConfig?> read();

  Future<void> save(ServerConfig config);

  Future<void> clear();
}
