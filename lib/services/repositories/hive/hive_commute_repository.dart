import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:i_zerak_app/models/commute_dao.dart';
import 'package:i_zerak_app/models/gas_station_dao.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_commute.dart';

/// Depot Hive des trajets, dans une `Box<String>` de JSON.
///
/// Meme parti pris que pour les stations favorites : aucun `TypeAdapter`,
/// donc aucun identifiant de type brule a vie, et un format qui accepte un
/// champ de plus sans migration. Les cles sont prefixees par nature :
///
///   - `settings` : les reglages du trajet ;
///   - `day:aaaa-mm-jj` : une journee ;
///   - `goal:<id>` : un objectif ;
///   - `price:<carburant>:aaaa-mm-jj` : le prix le plus bas vu ce jour-la.
///
/// Une entree illisible est ignoree plutot que de faire echouer la lecture
/// entiere : une journee corrompue ne doit pas vider la cagnotte a l'ecran.
class HiveCommuteRepository implements ICommute {
  HiveCommuteRepository(this._box);

  final Box<String> _box;

  static const String _settingsKey = 'settings';
  static const String _dayPrefix = 'day:';
  static const String _goalPrefix = 'goal:';
  static const String _pricePrefix = 'price:';

  String _priceKey(FuelType fuel, DateTime day) => '$_pricePrefix${fuel.name}:${dayKey(day)}';

  Object? _decode(String? raw) {
    if (raw == null) {
      return null;
    }
    try {
      return json.decode(raw);
    } on FormatException {
      return null;
    }
  }

  /// Chaque ecriture est suivie d'un `flush` : une boite Hive sert ses
  /// valeurs depuis un cache en memoire, et une ecriture qui n'atteint pas le
  /// disque disparaitrait si Android tuait l'application juste apres.
  Future<void> _put(String key, Object value) async {
    await _box.put(key, json.encode(value));
    await _box.flush();
  }

  Future<void> _delete(String key) async {
    await _box.delete(key);
    await _box.flush();
  }

  Iterable<Object?> _valuesWithPrefix(String prefix) sync* {
    for (final key in _box.keys) {
      if ('$key'.startsWith(prefix)) {
        yield _decode(_box.get(key));
      }
    }
  }

  @override
  Future<CommuteSettings> readSettings() async =>
      CommuteSettings.fromJson(_decode(_box.get(_settingsKey)));

  @override
  Future<void> saveSettings(CommuteSettings settings) => _put(_settingsKey, settings.toJson());

  @override
  Future<List<CommuteDay>> getDays() async => [
        for (final raw in _valuesWithPrefix(_dayPrefix))
          if (CommuteDay.fromJson(raw) case final CommuteDay day) day,
      ];

  @override
  Future<void> saveDay(CommuteDay day) => _put('$_dayPrefix${dayKey(day.date)}', day.toJson());

  @override
  Future<void> deleteDay(DateTime date) => _delete('$_dayPrefix${dayKey(date)}');

  @override
  Future<List<Goal>> getGoals() async => [
        for (final raw in _valuesWithPrefix(_goalPrefix))
          if (Goal.fromJson(raw) case final Goal goal) goal,
      ];

  @override
  Future<void> saveGoal(Goal goal) => _put('$_goalPrefix${goal.id}', goal.toJson());

  @override
  Future<void> deleteGoal(String id) => _delete('$_goalPrefix$id');

  @override
  Future<void> recordPrice(FuelType fuel, DateTime day, double price, String? station) =>
      _put(_priceKey(fuel, day), {'price': price, if (station != null) 'station': station});

  @override
  Future<PriceObservation?> latestPrice(FuelType fuel, {DateTime? onOrBefore}) async {
    final prefix = '$_pricePrefix${fuel.name}:';
    final bound = onOrBefore == null ? null : dateOnly(onOrBefore);
    PriceObservation? latest;
    for (final key in _box.keys) {
      final name = '$key';
      if (!name.startsWith(prefix)) {
        continue;
      }
      final day = parseDayKey(name.substring(prefix.length));
      final raw = _decode(_box.get(key));
      if (day == null || raw is! Map || raw['price'] is! num) {
        continue;
      }
      if (bound != null && day.isAfter(bound)) {
        continue;
      }
      if (latest == null || day.isAfter(latest.day)) {
        latest = (
          day: day,
          price: (raw['price'] as num).toDouble(),
          station: raw['station'] as String?,
        );
      }
    }
    return latest;
  }
}
