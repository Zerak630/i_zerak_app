import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:i_zerak_app/models/commute_dao.dart';
import 'package:i_zerak_app/models/recap_dao.dart';
import 'package:i_zerak_app/models/sport_dao.dart';
import 'package:i_zerak_app/services/recap/recap_service.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../../__mocks__/commute_fakes.dart';
import '../../__mocks__/recap_fakes.dart';
import '../../__mocks__/sport_fakes.dart';
import '../../__mocks__/subscription_fakes.dart';

void main() {
  // Dimanche 29 novembre 2026, 18 h.
  final now = DateTime(2026, 11, 29, 18);
  late MemoryCommute commute;
  late MemorySport sport;
  late MemoryPreferences preferences;
  late FakeRecapBridge bridge;

  setUpAll(() async {
    await initializeDateFormatting('fr');
    await initializeDateFormatting('en');
  });

  RecapService service({Locale locale = const Locale('fr', 'FR')}) => RecapService(
        commute: commute,
        subscriptions: MemorySubscriptions([sub('Spotify', 10.99), sub('Netflix', 13.49)]),
        sport: sport,
        preferences: preferences,
        bridge: bridge,
        clock: () => now,
        locale: () => locale,
      );

  setUp(() {
    commute = MemoryCommute(
      settings: const CommuteSettings(distanceKm: 12.4),
      days: [
        CommuteDay(
          date: DateTime(2026, 11, 24),
          mode: CommuteMode.bike,
          amount: 12.4,
          pricePerLitre: 1.7,
          priceSource: PriceSource.live,
        ),
      ],
    );
    sport = MemorySport(sessions: [
      SportSession(id: 'a', date: DateTime(2026, 11, 25), sportId: Sport.yoga, minutes: 45),
      SportSession(id: 'b', date: DateTime(2026, 11, 28), sportId: Sport.running, minutes: 90),
    ]);
    preferences = MemoryPreferences();
    bridge = FakeRecapBridge();
  });

  test('le natif recoit les reglages et les bilans, avec le jour ou ils se terminent', () async {
    await service().push();

    final config = bridge.configs.single;
    expect((config['weekly'], config['monthly'], config['hour'], config['minute']), (true, true, 19, 30));
    final entries = (config['entries']! as List).cast<Map>();
    expect(entries.map((entry) => entry['kind']), ['week', 'week', 'month', 'month']);
    // Cette semaine se termine aujourd'hui, dimanche 29 ; le mois demain.
    expect(entries[0]['endEpochDay'], RecapService.epochDay(DateTime(2026, 11, 29)));
    expect(entries[2]['endEpochDay'], RecapService.epochDay(DateTime(2026, 11, 30)));
    expect(entries[0]['title'], 'Bilan de la semaine');
    expect(entries[2]['title'], 'Bilan de novembre');
  });

  test('le texte dit chaque habitude dans son unite', () async {
    await service().push();
    final entries = (bridge.configs.single['entries']! as List).cast<Map>();

    final week = entries[0]['text'] as String;
    expect(week, contains('12,40'));
    expect(week, contains('en 1 trajet'));
    expect(week, contains('2 h 15 de sport en 2 séances'));
    expect(week, isNot(contains('réseaux')), reason: 'Temps libre non configure');

    final month = entries[2]['text'] as String;
    expect(month, contains('1 abonnement remboursé sur 2'));

    final previous = entries[1]['text'] as String;
    expect(previous, contains('Pas de séance de sport'));
  });

  test('en anglais, le meme bilan', () async {
    await service(locale: const Locale('en', 'GB')).push();
    final entries = (bridge.configs.single['entries']! as List).cast<Map>();
    expect(entries[0]['title'], 'Your week');
    expect(entries[2]['title'], 'Your November');
    expect(entries[0]['text'], contains('2 h 15 of sport in 2 sessions'));
  });

  test('changer les reglages les enregistre, demande la permission et reprogramme', () async {
    await service().saveSettings(const RecapSettings(weekly: false, hour: 21, minute: 0));

    expect(preferences.recap.weekly, isFalse);
    expect(bridge.notificationRequests, 1);
    expect(bridge.configs.single['hour'], 21);

    await service().saveSettings(const RecapSettings(weekly: false, monthly: false));
    expect(bridge.notificationRequests, 1, reason: 'tout est coupe : rien a demander');
  });

  test('hors Android, rien n est transmis', () async {
    bridge.supported = false;
    await service().push();
    expect(bridge.configs, isEmpty);
  });

  test('le bilan de l ecran se lit dans les memes depots', () async {
    final recap = await service().recapOf(RecapRange.weekOf(now));
    expect(recap.fuelSaved, 12.4);
    expect(recap.sportMinutes, 135);
    expect(recap.freeTime, isNull);
  });
}
