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

    test('le temps repris se mesure sur la moyenne de depart, quota tenu ou non', () {
      final settings = configured(baseline: 120);
      // Semaine 0 : quota de 108 minutes.
      final kept = closedDay(settings, DateTime(2026, 11, 2), 60);
      expect(kept.underQuota, isTrue);
      expect(kept.regainedMinutes, 60);
      expect(kept.overMinutes, 0);

      final over = closedDay(settings, DateTime(2026, 11, 2), 110);
      expect(over.underQuota, isFalse);
      // Dix minutes reprises sur la moyenne, deux de trop sur le quota.
      expect(over.regainedMinutes, 10);
      expect(over.overMinutes, 2);

      // Au-dessus de la moyenne : rien de repris, et rien de negatif.
      expect(closedDay(settings, DateTime(2026, 11, 2), 150).regainedMinutes, 0);
    });

    test('les journees figees du temps de la cagnotte se relisent', () {
      final settings = configured(baseline: 120);
      final legacy = {
        ...closedDay(settings, DateTime(2026, 11, 2), 60).toJson(),
        'amount': 2.0,
        'missed': 0.4,
      };
      final day = ScreenTimeDay.fromJson(legacy)!;
      expect(day.regainedMinutes, 60);
      expect(closedDay(settings, DateTime(2026, 11, 2), 60).toJson().containsKey('amount'), isFalse);
    });

    test('relu tel qu\'ecrit, et tolerant', () {
      final settings = configured().copyWith(reportHour: 22);
      final copy = ScreenTimeSettings.fromJson(settings.toJson());
      expect(copy.isConfigured, isTrue);
      expect(copy.reportHour, 22);
      expect(copy.startDate, DateTime(2026, 11, 2));
      expect(copy.apps.single.label, 'Instagram');

      final broken = ScreenTimeSettings.fromJson({'floor': 'vingt', 'apps': 'x'});
      expect(broken.floorMinutes, 20);
      expect(broken.isConfigured, isFalse);
    });

    test('un jour fige garde son quota et sa moyenne', () {
      final settings = configured(baseline: 120);
      final day = closedDay(settings, DateTime(2026, 11, 2), 90);
      final copy = ScreenTimeDay.fromJson(day.toJson())!;
      expect(copy.quotaMinutes, 108);
      expect(copy.baselineMinutes, 120);
      expect(copy.regainedMinutes, 30);
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
        today: today,
      );
      expect(ledger.streak, 1);
    });

    test('temps repris, jours tenus et temps de trop', () {
      final ledger = ScreenTimeLedger(
        settings: settings,
        days: [
          closedDay(settings, DateTime(2026, 11, 9), 60),
          closedDay(settings, DateTime(2026, 11, 8), 180),
          closedDay(settings, DateTime(2026, 11, 7), 100),
        ],
        today: today,
      );
      // 60 + 0 + 20 minutes reprises sur une moyenne de 120.
      expect(ledger.regainedMinutes, 80);
      expect(ledger.regainedBetween(DateTime(2026, 11, 8), DateTime(2026, 11, 9)), 60);
      expect(ledger.keptDays, 2);
      expect(ledger.overDays, 1);
      // Le 8, semaine 0 : quota de 108, 72 minutes de trop.
      expect(ledger.overMinutes, 72);
      expect(ledger.overBetween(DateTime(2026, 11, 9), DateTime(2026, 11, 9)), 0);
    });

    test('aujourd hui, au-dessus du quota : du temps de trop, et du temps repris quand meme', () {
      final live = DailyUsage(
        date: today,
        apps: const {insta: AppUsage(seconds: 100 * 60)},
        hourly: List.filled(24, 0),
      );
      final ledger = ScreenTimeLedger(
          settings: settings, days: const [], today: today, live: live);
      // Semaine 1 : quota de 97 minutes.
      expect(ledger.todayUnderQuota, isFalse);
      expect(ledger.todayOver, 3);
      expect(ledger.todayRegained, 20);
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
        today: today,
      );
      expect(ledger.weekAverage, 90);
      expect(ledger.trend, closeTo(-0.25, 1e-9));
    });

    test('le quota de la semaine prochaine', () {
      final ledger = ScreenTimeLedger(
          settings: settings, days: const [], today: today);
      expect(ledger.todayQuota, 97);
      expect(ledger.nextWeekQuota, 87);
    });

    test('l\'heure la plus chargee tient compte d\'aujourd\'hui', () {
      final live = DailyUsage.fromSessions(today, [
        session(insta, DateTime(2026, 11, 10, 22, 10), const Duration(minutes: 30)),
      ], {insta});
      final ledger = ScreenTimeLedger(
          settings: settings, days: const [], today: today, live: live);
      expect(ledger.peakHour, 22);
      expect(ledger.todayRegained, 90);
      expect(ledger.todayUnderQuota, isTrue);
    });
  });

  test('daysBetween ignore le changement d\'heure', () {
    expect(daysBetween(DateTime(2026, 10, 24), DateTime(2026, 10, 26)), 2);
    expect(daysBetween(DateTime(2026, 3, 28), DateTime(2026, 3, 30)), 2);
  });
}
