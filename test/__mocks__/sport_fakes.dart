import 'package:i_zerak_app/models/sport_dao.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_sport.dart';

/// Depot du sport en memoire : le comportement Hive est verifie a part.
class MemorySport implements ISport {
  MemorySport({List<Sport>? sports, List<PlannedSlot>? plan, List<SportSession>? sessions})
      : sports = {for (final sport in sports ?? const <Sport>[]) sport.id: sport},
        plan = {for (final slot in plan ?? const <PlannedSlot>[]) slot.id: slot},
        sessions = {for (final session in sessions ?? const <SportSession>[]) session.id: session};

  final Map<String, Sport> sports;
  final Map<String, PlannedSlot> plan;
  final Map<String, SportSession> sessions;

  @override
  Future<List<Sport>> getSports() async => mergeSports(sports.values);

  @override
  Future<void> saveSport(Sport sport) async => sports[sport.id] = sport;

  @override
  Future<void> deleteSport(Sport sport) async =>
      sport.isBuiltIn ? sports[sport.id] = hiddenSport(sport) : sports.remove(sport.id);

  @override
  Future<List<PlannedSlot>> getPlan() async => [...plan.values];

  @override
  Future<void> saveSlot(PlannedSlot slot) async => plan[slot.id] = slot;

  @override
  Future<void> deleteSlot(String id) async => plan.remove(id);

  @override
  Future<List<SportSession>> getSessions() async => [...sessions.values];

  @override
  Future<void> saveSession(SportSession session) async => sessions[session.id] = session;

  @override
  Future<void> deleteSession(String id) async => sessions.remove(id);
}
