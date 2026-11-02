import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:i_zerak_app/models/commute_dao.dart' show Goal, dayKey;
import 'package:i_zerak_app/models/screen_time_dao.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_screen_time.dart';

/// Depot Hive du temps libre, dans une `Box<String>` de JSON.
///
/// Meme format que `HiveCommuteRepository` : aucun `TypeAdapter`, et des cles
/// prefixees par nature :
///
///   - `settings` : les reglages ;
///   - `day:aaaa-mm-jj` : une journee terminee ;
///   - `goal:<id>` : un objectif.
///
/// Une entree illisible est ignoree plutot que de faire echouer la lecture
/// entiere.
class HiveScreenTimeRepository implements IScreenTime {
  HiveScreenTimeRepository(this._box);

  final Box<String> _box;

  static const String _settingsKey = 'settings';
  static const String _dayPrefix = 'day:';
  static const String _goalPrefix = 'goal:';

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

  /// Suivi d'un `flush`, pour la meme raison que dans le depot des trajets :
  /// une ecriture restee en cache disparaitrait avec l'application.
  Future<void> _put(String key, Object value) async {
    await _box.put(key, json.encode(value));
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
  Future<ScreenTimeSettings> readSettings() async =>
      ScreenTimeSettings.fromJson(_decode(_box.get(_settingsKey)));

  @override
  Future<void> saveSettings(ScreenTimeSettings settings) => _put(_settingsKey, settings.toJson());

  @override
  Future<List<ScreenTimeDay>> getDays() async => [
        for (final raw in _valuesWithPrefix(_dayPrefix))
          if (ScreenTimeDay.fromJson(raw) case final ScreenTimeDay day) day,
      ];

  @override
  Future<void> saveDay(ScreenTimeDay day) => _put('$_dayPrefix${dayKey(day.date)}', day.toJson());

  @override
  Future<List<Goal>> getGoals() async => [
        for (final raw in _valuesWithPrefix(_goalPrefix))
          if (Goal.fromJson(raw) case final Goal goal) goal,
      ];

  @override
  Future<void> saveGoal(Goal goal) => _put('$_goalPrefix${goal.id}', goal.toJson());

  @override
  Future<void> deleteGoal(String id) async {
    await _box.delete('$_goalPrefix$id');
    await _box.flush();
  }
}
