import 'package:i_zerak_app/models/commute_dao.dart';
import 'package:i_zerak_app/models/recap_dao.dart';
import 'package:i_zerak_app/models/screen_time_dao.dart';
import 'package:i_zerak_app/models/sport_dao.dart';
import 'package:test/test.dart';

import '../__mocks__/subscription_fakes.dart';

CommuteDay _bike(DateTime date, double amount) => CommuteDay(
      date: date,
      mode: CommuteMode.bike,
      amount: amount,
      pricePerLitre: 1.7,
      priceSource: PriceSource.live,
    );

void main() {
  // Mercredi 18 novembre 2026.
  final today = DateTime(2026, 11, 18);

  group('periodes', () {
    test('une semaine va du lundi au dimanche, un mois du 1er au dernier jour', () {
      final week = RecapRange.weekOf(today);
      expect((week.start, week.end), (DateTime(2026, 11, 16), DateTime(2026, 11, 22)));
      expect(week.days, 7);
      expect(week.previous.start, DateTime(2026, 11, 9));
      expect(week.next.start, DateTime(2026, 11, 23));

      final february = RecapRange.monthOf(DateTime(2028, 2, 10));
      expect((february.start, february.end), (DateTime(2028, 2, 1), DateTime(2028, 2, 29)));
      expect(RecapRange.monthOf(DateTime(2026, 1, 5)).previous.start, DateTime(2025, 12, 1));
    });

    test('une semaine a cheval sur deux mois reste une semaine', () {
      final week = RecapRange.weekOf(DateTime(2026, 12, 1));
      expect((week.start, week.end), (DateTime(2026, 11, 30), DateTime(2026, 12, 6)));
      expect(week.contains(DateTime(2026, 12, 6, 23, 59)), isTrue);
      expect(week.contains(DateTime(2026, 12, 7)), isFalse);
    });
  });

  group('bilan', () {
    const settings = CommuteSettings(distanceKm: 12, paybackExcluded: {'Loyer'});
    final commute = CommuteLedger([
      _bike(DateTime(2026, 11, 16), 2.5),
      _bike(DateTime(2026, 11, 17), 2.5),
      _bike(DateTime(2026, 11, 3), 10),
      _bike(DateTime(2026, 10, 30), 7),
    ], const []);
    final free = ScreenTimeSettings(
      apps: const [TrackedApp(package: 'insta', label: 'Instagram')],
      baselineMinutes: 120,
      startDate: DateTime(2026, 11, 1),
    );
    ScreenTimeDay day(DateTime date, int minutes) => free.close(DailyUsage(
          date: date,
          apps: {'insta': AppUsage(seconds: minutes * 60)},
          hourly: List.filled(24, 0),
        ));
    final screen = ScreenTimeLedger(
      settings: free,
      days: [day(DateTime(2026, 11, 16), 60), day(DateTime(2026, 11, 17), 200), day(DateTime(2026, 11, 9), 30)],
      today: today,
    );
    const yoga = PlannedSlot(id: 'y', sportId: Sport.yoga, weekday: DateTime.monday, minutes: 30);
    final sport = SportLedger(
      sports: Sport.defaults,
      plan: const [yoga],
      sessions: [
        SportSession.forSlot(yoga, DateTime(2026, 11, 16), minutes: 40),
        SportSession(id: 'r', date: DateTime(2026, 11, 17), sportId: Sport.running, minutes: 25),
        SportSession(id: 'o', date: DateTime(2026, 10, 31), sportId: Sport.running, minutes: 60),
      ],
      today: today,
    );

    Recap recap(RecapRange range, {ScreenTimeLedger? screenTime}) => buildRecap(
          range,
          commuteSettings: settings,
          commute: commute,
          subscriptions: [sub('Spotify', 10.99), sub('Loyer', 700)],
          screenTime: screenTime,
          sport: sport,
        );

    test('la semaine : essence, temps repris, sport, chacun dans son unite', () {
      final week = recap(RecapRange.weekOf(today), screenTime: screen);

      expect(week.fuelSaved, 5);
      expect(week.bikeDays, 2);
      expect(week.payback, isNull, reason: 'les abonnements se comptent au mois');
      // 60 minutes reprises le 16, aucune le 17 (200 minutes).
      expect(week.freeTime!.regainedMinutes, 60);
      expect(week.freeTime!.keptDays, 1);
      expect(week.freeTime!.measuredDays, 2);
      expect(week.sportMinutes, 65);
      expect(week.sportSessions, 2);
      expect((week.planned, week.plannedDone), (1, 1));
      expect(week.bySport.map((total) => total.sportId), [Sport.yoga, Sport.running]);
      // 65 minutes de sport pour 60 reprises : la part plafonne a tout.
      expect(week.sportShareOfRegained, 1);
    });

    test('le mois ajoute les abonnements rembourses, hors exclusions', () {
      final month = recap(RecapRange.monthOf(today), screenTime: screen);

      expect(month.fuelSaved, 15);
      expect(month.payback!.lines.single.subscription.name, 'Spotify');
      expect(month.payback!.paidCount, 1);
      // Trois lundis de novembre deja arrives : le 2, le 9 et le 16 ; seul
      // le 16 a ete fait. Le 23 et le 30 ne comptent pas encore.
      expect(month.planned, 3);
      expect(month.plannedDone, 1);
      expect(month.freeTime!.regainedMinutes, 60 + 90);
    });

    test('sans temps libre configure, pas de ligne au lieu de zeros', () {
      final week = recap(RecapRange.weekOf(today));
      expect(week.freeTime, isNull);
      expect(week.sportShareOfRegained, isNull);
    });
  });

  test('les reglages se relisent, et tolerent une valeur abimee', () {
    final settings = RecapSettings.fromJson(
        const RecapSettings(weekly: false, hour: 20, minute: 5).toJson());
    expect((settings.weekly, settings.monthly, settings.hour, settings.minute), (false, true, 20, 5));

    final broken = RecapSettings.fromJson({'hour': 42, 'weekly': 'oui'});
    expect((broken.weekly, broken.hour), (true, 23));
  });
}
