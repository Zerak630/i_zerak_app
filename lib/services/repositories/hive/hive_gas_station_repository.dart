import 'package:hive/hive.dart';
import 'package:i_zerak_app/models/gas_station_dao.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_gas_stations.dart';

/// Depot Hive des stations favorites.
///
/// Volontairement une `Box<String>` de libelles indexee par identifiant, et non
/// une boite d'objets : il n'y a que deux champs, et un modele stocke aurait
/// exige un `TypeAdapter` ecrit a la main de plus, avec un identifiant de type
/// brule a vie (cf. `type_adapters.dart`). Le format primitif se relit sans
/// adaptateur, donc sans migration possible a rater.
class HiveGasStationRepository implements IGasStations {
  HiveGasStationRepository(this._box);

  final Box<String> _box;

  /// Les sept stations qui vivaient jusqu'ici en dur dans `GasService`.
  ///
  /// Elles sont deposees une seule fois, a la premiere ouverture d'une boite
  /// vierge : sans cela, la mise a jour qui rend la liste modifiable la
  /// commencerait vide, et l'utilisateur devrait ressaisir ce qu'il suivait
  /// deja. Un drapeau distinct marque le passage, pour qu'une liste vidée a la
  /// main ne se repeuple pas au lancement suivant.
  static const Map<int, String> _legacyStations = {
    49400004: 'ZI EcoparcSaint Lambert des Levées, Saumur',
    49400006: "ZAC DU CHAMP BLANCHARD RUE DE L'AVENIR, Distré",
    49400007: 'BOULEVARD DE LA MARNE, Saumur',
    49412001: '51 Boulevard Mal de Lattre-de-Tassigny, Saumur',
    79100001: 'BD PORT GENTIL, Thouars',
    79100003: 'Route de Saumur, Thouars',
    79100006: '22 boulevard jacques menard, Thouars',
  };

  /// Cles de service. Aucune n'est numerique, elles ne peuvent donc pas entrer
  /// en collision avec un identifiant de station, et `getAll` les ignore.
  static const String _seededKey = 'seeded';
  static const String _fuelKey = 'fuel';

  /// A appeler une fois au demarrage, avant le premier affichage.
  Future<void> seedLegacyStationsIfEmpty() async {
    if (_box.containsKey(_seededKey)) {
      return;
    }
    // Compter les stations, et non les entrees de la boite : les cles de
    // service y cohabitent, et `_box.length` ferait dependre l'amorcage de
    // l'ordre dans lequel le carburant a ete enregistre.
    final empty = (await getAll()).isEmpty;
    await _box.put(_seededKey, '1');
    if (empty) {
      await _box.putAll({
        for (final entry in _legacyStations.entries) '${entry.key}': entry.value,
      });
    }
    await _box.flush();
  }

  @override
  /// Les cles non numeriques sont ignorees : c'est ce qui laisse cohabiter le
  /// drapeau `seeded` avec les stations, dans la meme boite.
  Future<List<SavedGasStation>> getAll() async => [
        for (final key in _box.keys)
          if (int.tryParse('$key') case final int id) (id: id, label: _box.get(key) ?? ''),
      ];

  @override
  Future<void> add(SavedGasStation station) async {
    await _box.put('${station.id}', station.label);
    // Meme raison qu'ailleurs dans le depot : une boite Hive sert ses valeurs
    // depuis un cache en memoire, et une ecriture qui n'atteint pas le disque
    // resterait invisible jusqu'au prochain demarrage.
    await _box.flush();
  }

  @override
  Future<void> delete(int id) async {
    await _box.delete('$id');
    await _box.flush();
  }

  @override
  Future<FuelType> readFuel() async => FuelType.fromName(_box.get(_fuelKey));

  @override
  Future<void> saveFuel(FuelType fuel) async {
    await _box.put(_fuelKey, fuel.name);
    await _box.flush();
  }
}
