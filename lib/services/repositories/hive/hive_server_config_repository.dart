import 'package:hive/hive.dart';
import 'package:i_zerak_app/models/server_config_dao.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_server_config.dart';

/// Une seule configuration existe : elle est stockee sous une cle fixe, ce qui
/// rend l'ecriture atomique et la lecture triviale.
class HiveServerConfigRepository implements IServerConfig {
  static const String _key = 'default';

  final Box<ServerConfig> _box;

  HiveServerConfigRepository(this._box);

  @override
  Future<ServerConfig?> read() async => _box.get(_key);

  @override
  Future<void> save(ServerConfig config) => _box.put(_key, config);

  @override
  Future<void> clear() => _box.delete(_key);
}
