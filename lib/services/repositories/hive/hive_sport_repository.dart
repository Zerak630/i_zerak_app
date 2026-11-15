import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:i_zerak_app/models/sport_dao.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_sport.dart';

/// Depot Hive du sport, dans une `Box<String>` de JSON.
///
/// Meme format que `HiveCommuteRepository` : aucun `TypeAdapter`, et des cles
/// prefixees par nature, une entree par fait — c'est ce qui permet a la
/// synchro de fusionner entree par entree :
///
///   - `sport:<id>` : un sport ajoute, ou un sport livre renomme ;
///   - `slot:<id>` : un creneau du programme ;
///   - `session:<id>` : une seance saisie.
///
/// Une entree illisible est ignoree plutot que de faire echouer la lecture
/// entiere.
class HiveSportRepository implements ISport {
  HiveSportRepository(this._box);

  final Box<String> _box;

  static const String _sportPrefix = 'sport:';
  static const String _slotPrefix = 'slot:';
  static const String _sessionPrefix = 'session:';

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

  /// Chaque ecriture est suivie d'un `flush`, comme dans les autres depots.
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
  Future<List<Sport>> getSports() async => mergeSports([
        for (final raw in _valuesWithPrefix(_sportPrefix))
          if (Sport.fromJson(raw) case final Sport sport) sport,
      ]);

  @override
  Future<void> saveSport(Sport sport) => _put('$_sportPrefix${sport.id}', sport.toJson());

  @override
  Future<void> deleteSport(Sport sport) =>
      sport.isBuiltIn ? saveSport(hiddenSport(sport)) : _delete('$_sportPrefix${sport.id}');

  @override
  Future<List<PlannedSlot>> getPlan() async => [
        for (final raw in _valuesWithPrefix(_slotPrefix))
          if (PlannedSlot.fromJson(raw) case final PlannedSlot slot) slot,
      ];

  @override
  Future<void> saveSlot(PlannedSlot slot) => _put('$_slotPrefix${slot.id}', slot.toJson());

  @override
  Future<void> deleteSlot(String id) => _delete('$_slotPrefix$id');

  @override
  Future<List<SportSession>> getSessions() async => [
        for (final raw in _valuesWithPrefix(_sessionPrefix))
          if (SportSession.fromJson(raw) case final SportSession session) session,
      ];

  @override
  Future<void> saveSession(SportSession session) =>
      _put('$_sessionPrefix${session.id}', session.toJson());

  @override
  Future<void> deleteSession(String id) => _delete('$_sessionPrefix$id');
}
