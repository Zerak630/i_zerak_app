import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:i_zerak_app/models/commute_dao.dart';
import 'package:i_zerak_app/models/reminder_dao.dart';
import 'package:i_zerak_app/models/sport_dao.dart';
import 'package:i_zerak_app/services/reminders/reminder_service.dart';

import '../../__mocks__/commute_fakes.dart';
import '../../__mocks__/recap_fakes.dart';
import '../../__mocks__/sport_fakes.dart';

/// Un natif imaginaire : il garde ce qu'on lui transmet, et rend les
/// reponses donnees depuis les notifications.
class FakeReminderBridge implements IReminderBridge {
  bool supported = true;
  final List<Map<String, Object?>> configs = [];
  List<String> pending = [];
  int notificationRequests = 0;

  @override
  bool get isSupported => supported;

  @override
  Future<void> configure(Map<String, Object?> config) async => configs.add(config);

  @override
  Future<List<String>> takePendingSlotAnswers() async {
    final answers = pending;
    pending = [];
    return answers;
  }

  @override
  Future<bool> requestNotifications() async {
    notificationRequests++;
    return true;
  }
}

void main() {
  // Jeudi 26 novembre 2026, 12 h.
  final now = DateTime(2026, 11, 26, 12);
  const yoga = PlannedSlot(id: 'yoga-thu', sportId: Sport.yoga, weekday: DateTime.thursday, minutes: 30);
  const run = PlannedSlot(id: 'run-sat', sportId: Sport.running, weekday: DateTime.saturday, minutes: 45);

  late MemoryCommute commute;
  late MemorySport sport;
  late MemoryPreferences preferences;
  late FakeReminderBridge bridge;

  ReminderService service() => ReminderService(
        commute: commute,
        sport: sport,
        preferences: preferences,
        bridge: bridge,
        clock: () => now,
        locale: () => const Locale('fr', 'FR'),
      );

  setUp(() {
    commute = MemoryCommute(settings: const CommuteSettings(distanceKm: 20, consumption: 5));
    sport = MemorySport(plan: [yoga, run]);
    preferences = MemoryPreferences();
    bridge = FakeReminderBridge();
  });

  group('config', () {
    test('transmet reglages, textes traduits et creneaux', () async {
      final config = await service().config();
      final commuteSection = config['commute']! as Map;
      expect(commuteSection['enabled'], isTrue);
      expect(commuteSection['hour'], 18);
      expect(commuteSection['minute'], 30);
      expect(commuteSection['configured'], isTrue);
      expect(commuteSection['title'], 'Vélo ou voiture aujourd’hui ?');
      // 20 km a 5 L/100 au prix par defaut de 2 € : 2 €.
      expect(commuteSection['text'], contains('2,00'));
      expect(commuteSection['answered'], isEmpty);

      final sportSection = config['sport']! as Map;
      final slots = sportSection['slots']! as List;
      expect(slots, hasLength(2));
      final thursday = slots.cast<Map>().firstWhere((slot) => slot['id'] == 'yoga-thu');
      expect(thursday['weekday'], DateTime.thursday);
      expect(thursday['title'], contains('30 min'));
      expect(sportSection['done'], 'Faite');
    });

    test('liste les journees et creneaux deja saisis, sans remonter trop loin', () async {
      commute.days[dayKey(now)] = CommuteDay.remote(now);
      commute.days['2026-10-01'] = CommuteDay.remote(DateTime(2026, 10, 1));
      sport.sessions['s'] = SportSession.skipped(yoga, now);
      final config = await service().config();
      expect((config['commute']! as Map)['answered'], ['2026-11-26']);
      expect((config['sport']! as Map)['answered'], ['yoga-thu|2026-11-26']);
    });

    test('suit les reglages enregistres', () async {
      preferences.reminders = const ReminderSettings(commute: false, sportHour: 21, sportMinute: 5);
      final config = await service().config();
      expect((config['commute']! as Map)['enabled'], isFalse);
      expect((config['sport']! as Map)['hour'], 21);
      expect((config['sport']! as Map)['minute'], 5);
    });
  });

  group('importPendingAnswers', () {
    test('enregistre « Faite » a la duree prevue et « Pas faite » comme saute', () async {
      bridge.pending = ['done|yoga-thu|2026-11-26', 'skipped|run-sat|2026-11-21'];
      expect(await service().importPendingAnswers(), 2);
      final done = sport.sessions[SportSession.slotSessionId(yoga, DateTime(2026, 11, 26))]!;
      expect(done.done, isTrue);
      expect(done.minutes, 30);
      final skipped = sport.sessions[SportSession.slotSessionId(run, DateTime(2026, 11, 21))]!;
      expect(skipped.skipped, isTrue);
    });

    test("n'ecrase pas un creneau deja saisi et ignore l'inconnu", () async {
      final manual = SportSession.forSlot(yoga, now, minutes: 50);
      sport.sessions[manual.id] = manual;
      bridge.pending = ['skipped|yoga-thu|2026-11-26', 'done|gone|2026-11-26', 'n importe quoi'];
      expect(await service().importPendingAnswers(), 0);
      expect(sport.sessions[manual.id]!.minutes, 50);
    });
  });

  group('start', () {
    test("demande l'autorisation quand un rappel a de quoi partir", () async {
      await service().start();
      expect(bridge.notificationRequests, 1);
      expect(bridge.configs, hasLength(1));
    });

    test('ne demande rien sans trajet regle ni programme', () async {
      commute = MemoryCommute();
      sport = MemorySport();
      await service().start();
      expect(bridge.notificationRequests, 0);
      expect(bridge.configs, hasLength(1));
    });

    test('ne fait rien hors Android', () async {
      bridge.supported = false;
      await service().start();
      expect(bridge.configs, isEmpty);
    });
  });

  test('ReminderSettings se relit avec tolerance', () {
    final settings = ReminderSettings.fromJson({'commute': false, 'commute_hour': 42, 'sport': 'oui'});
    expect(settings.commute, isFalse);
    expect(settings.commuteHour, 23);
    expect(settings.sport, isTrue);
    expect(ReminderSettings.fromJson(settings.toJson()).toJson(), settings.toJson());
  });
}
