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

  /// Ecrit puis force le vidage du tampon sur le disque.
  ///
  /// Une boite Hive sert d'abord ses valeurs depuis un cache en memoire : tant
  /// que le fichier n'est pas ecrit, l'application se comporte normalement et
  /// ne decouvre la perte qu'au redemarrage suivant. Le `flush` supprime cette
  /// fenetre, et surtout il fait remonter une erreur d'ecriture ici plutot que
  /// de la laisser passer inapercue.
  @override
  Future<void> save(ServerConfig config) async {
    await _box.put(_key, config);
    await _box.flush();
  }

  @override
  Future<void> clear() async {
    await _box.delete(_key);
    await _box.flush();
  }
}
