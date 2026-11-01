import 'package:i_zerak_app/models/commute_dao.dart' show Goal, GoalIcon, GoalKind;
import 'package:i_zerak_app/models/screen_time_dao.dart';
import 'package:test/test.dart';

const insta = 'com.instagram.android';
const yt = 'com.google.android.youtube';

UsageSession session(String package, DateTime start, Duration length) =>
    UsageSession(package, start, start.add(length));

ScreenTimeSettings configured({double baseline = 120, DateTime? start}) => ScreenTimeSettings(
      apps: const [TrackedApp(package: insta, label: 'Instagram')],
      baselineMinutes: baseline,
      startDate: start ?? DateTime(2026, 11, 2),
    );

ScreenTimeDay closedDay(ScreenTimeSettings settings, DateTime date, int minutes) =>
    settings.close(DailyUsage(
      date: date,
      apps: {insta: AppUsage(seconds: minutes * 60, opens: 3)},
      hourly: List.filled(24, 0),
    ));

void main() {
  group('mergeSessions', () {
    test('fusionne les passages rapproches d\'une meme application', () {
      final merged = mergeSessions([
        session(insta, DateTime(2026, 11, 1, 10), const Duration(minutes: 5)),
        session(insta, DateTime(2026, 11, 1, 10, 5, 10), const Duration(minutes: 2)),
        session(insta, DateTime(2026, 11, 1, 11), const Duration(minutes: 1)),
      ]);
      expect(merged, hasLength(2));
      expect(merged.first.duration, const Duration(minutes: 7, seconds: 10));
    });

    test('ne fusionne pas deux applications differentes', () {
      final merged = mergeSessions([
        session(insta, DateTime(2026, 11, 1, 10), const Duration(minutes: 5)),
        session(yt, DateTime(2026, 11, 1, 10, 5, 1), const Duration(minutes: 5)),
      ]);
      expect(merged, hasLength(2));
    });

    test('ignore les sessions de duree nulle', () {
      final start = DateTime(2026, 11, 1, 10);
      expect(mergeSessions([UsageSession(insta, start, start)]), isEmpty);
    });
  });

  group('DailyUsage.fromSessions', () {
    final day = DateTime(2026, 11, 1);

    test('compte temps, ouvertures et heures, pour les seules applications suivies', () {
      final usage = DailyUsage.fromSessions(day, [
        session(insta, DateTime(2026, 11, 1, 21, 50), const Duration(minutes: 20)),
        session(insta, DateTime(2026, 11, 1, 8), const Duration(minutes: 5)),
        session('com.whatsapp', DateTime(2026, 11, 1, 9), const Duration(hours: 1)),
      ], {insta});

      expect(usage.seconds, 25 * 60);
      expect(usage.opens, 2);
      expect(usage.hourly[21], 10 * 60);
      expect(usage.hourly[22], 10 * 60);
      expect(usage.hourly[8], 5 * 60);
      expect(usage.apps.keys, [insta]);
    });

    test('une session a cheval sur minuit n\'est comptee que pour sa part', () {
      final usage = DailyUsage.fromSessions(day, [
        session(insta, DateTime(2026, 10, 31, 23, 50), const Duration(minutes: 20)),
        session(insta, DateTime(2026, 11, 1, 23, 55), const Duration(minutes: 20)),
      ], {insta});

      expect(usage.seconds, 15 * 60);
      expect(usage.hourly[0], 10 * 60);
      expect(usage.hourly[23], 5 * 60);
      // Seule celle commencee ce jour-la compte comme ouverture.
      expect(usage.opens, 1);
    });

    test('le temps exclut les courtes pauses que les ouvertures ignorent', () {
      final usage = DailyUsage.fromSessions(day, [
        session(insta, DateTime(2026, 11, 1, 10), const Duration(minutes: 5)),
        session(insta, DateTime(2026, 11, 1, 10, 5, 20), const Duration(minutes: 5)),
      ], {insta});
      expect(usage.seconds, 10 * 60);
      expect(usage.opens, 1);
    });

    test('relu tel qu\'ecrit', () {
      final usage = DailyUsage.fromSessions(day, [
        session(insta, DateTime(2026, 11, 1, 12), const Duration(minutes: 3)),
      ], {insta});
      final copy = DailyUsage.fromJson(day, usage.toJson());
      expect(copy.seconds, usage.seconds);
      expect(copy.opens, usage.opens);
      expect(copy.hourly, usage.hourly);
    });
  });

  group('ScreenTimeSettings', () {
    test('le quota baisse de 10 % des la premiere semaine, puis chaque semaine', () {
      final settings = configured(baseline: 120);
      expect(settings.quotaFor(DateTime(2026, 11, 2)), 108);
      expect(settings.quotaFor(DateTime(2026, 11, 8)), 108);
      expect(settings.quotaFor(DateTime(2026, 11, 9)), 97);
      expect(settings.quotaFor(DateTime(2026, 11, 16)), 87);
    });

    test('le quota ne descend pas sous le plancher', () {
      final settings = configured(baseline: 30);
      expect(settings.quotaFor(DateTime(2027, 6, 1)), 20);
    });

    test('une moyenne deja sous le plancher sert de quota', () {
      final settings = configured(baseline: 12);
      expect(settings.quotaFor(DateTime(2027, 6, 1)), 12);
    });

    test('le gain se mesure sur la moyenne de depart, au centime', () {
      final settings = configured(baseline: 120);
      // Une heure gagnee a 2 €/h.
      expect(settings.gainFor(60), 2.0);
      expect(settings.gainFor(100), 0.67);
      // Au-dessus de la moyenne : rien, mais rien de retire non plus.
      expect(settings.gainFor(150), 0);
    });

    test('relu tel qu\'ecrit, et tolerant', () {
      final settings = configured().copyWith(ratePerHour: 3, reportHour: 22);
      final copy = ScreenTimeSettings.fromJson(settings.toJson());
      expect(copy.isConfigured, isTrue);
      expect(copy.ratePerHour, 3);
      expect(copy.reportHour, 22);
      expect(copy.startDate, DateTime(2026, 11, 2));
      expect(copy.apps.single.label, 'Instagram');

      final broken = ScreenTimeSettings.fromJson({'rate': 'deux', 'apps': 'x'});
      expect(broken.ratePerHour, 2.0);
      expect(broken.isConfigured, isFalse);
    });

    test('un jour fige garde son quota et son gain', () {
      final settings = configured(baseline: 120);
      final day = closedDay(settings, DateTime(2026, 11, 2), 90);
      final copy = ScreenTimeDay.fromJson(day.toJson())!;
      expect(copy.quotaMinutes, 108);
      expect(copy.amount, 1.0);
      expect(copy.underQuota, isTrue);
    });
  });

  group('ScreenTimeLedger', () {
    final settings = configured(baseline: 120);
    final today = DateTime(2026, 11, 10);

    test('la serie remonte depuis hier et s\'arrete au premier depassement', () {
      final ledger = ScreenTimeLedger(
        settings: settings,
        days: [
          closedDay(settings, DateTime(2026, 11, 9), 60),
          closedDay(settings, DateTime(2026, 11, 8), 80),
          closedDay(settings, DateTime(2026, 11, 7), 200),
          closedDay(settings, DateTime(2026, 11, 6), 10),
        ],
        goals: const [],
        today: today,
      );
      expect(ledger.streak, 2);
    });

    test('un jour sans mesure rompt la serie', () {
      final ledger = ScreenTimeLedger(
        settings: settings,
        days: [
          closedDay(settings, DateTime(2026, 11, 9), 60),
          closedDay(settings, DateTime(2026, 11, 7), 60),
        ],
        goals: const [],
        today: today,
      );
      expect(ledger.streak, 1);
    });

    test('cagnotte, objectifs et heures gagnees', () {
      final ledger = ScreenTimeLedger(
        settings: settings,
        days: [
          closedDay(settings, DateTime(2026, 11, 9), 60),
          closedDay(settings, DateTime(2026, 11, 8), 180),
        ],
        goals: [
          Goal(
            id: 'g',
            name: 'Livre',
            target: 1.5,
            kind: GoalKind.purchase,
            icon: GoalIcon.gift,
            createdAt: DateTime(2026, 11, 2),
            validatedAt: DateTime(2026, 11, 9),
          ),
        ],
        today: today,
      );
      expect(ledger.totalSaved, 2.0);
      expect(ledger.balance, 0.5);
      expect(ledger.hoursSaved, 1.0);
    });

    test('moyenne de la semaine et tendance', () {
      final ledger = ScreenTimeLedger(
        settings: settings,
        days: [
          closedDay(settings, DateTime(2026, 11, 9), 60),
          closedDay(settings, DateTime(2026, 11, 8), 120),
          // Trop ancien pour la semaine.
          closedDay(settings, DateTime(2026, 10, 1), 600),
        ],
        goals: const [],
        today: today,
      );
      expect(ledger.weekAverage, 90);
      expect(ledger.trend, closeTo(-0.25, 1e-9));
    });

    test('le quota de la semaine prochaine', () {
      final ledger = ScreenTimeLedger(
          settings: settings, days: const [], goals: const [], today: today);
      expect(ledger.todayQuota, 97);
      expect(ledger.nextWeekQuota, 87);
    });

    test('l\'heure la plus chargee tient compte d\'aujourd\'hui', () {
      final live = DailyUsage.fromSessions(today, [
        session(insta, DateTime(2026, 11, 10, 22, 10), const Duration(minutes: 30)),
      ], {insta});
      final ledger = ScreenTimeLedger(
          settings: settings, days: const [], goals: const [], today: today, live: live);
      expect(ledger.peakHour, 22);
      expect(ledger.todayGain, 3.0);
      expect(ledger.todayUnderQuota, isTrue);
    });
  });

  test('daysBetween ignore le changement d\'heure', () {
    expect(daysBetween(DateTime(2026, 10, 24), DateTime(2026, 10, 26)), 2);
    expect(daysBetween(DateTime(2026, 3, 28), DateTime(2026, 3, 30)), 2);
  });
}
