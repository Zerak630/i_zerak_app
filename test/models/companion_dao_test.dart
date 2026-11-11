import 'package:i_zerak_app/models/commute_dao.dart';
import 'package:i_zerak_app/models/companion_dao.dart';
import 'package:test/test.dart';

/// Le 1er juin 2026 est un lundi, le 14 septembre aussi, et le 18 septembre un
/// vendredi : septembre 2026 compte 22 jours ouvres.
CommuteDay bike(DateTime date, {double amount = 1.09}) => CommuteDay(
      date: date,
      mode: CommuteMode.bike,
      amount: amount,
      pricePerLitre: 1.689,
      priceSource: PriceSource.live,
    );

CommuteDay car(DateTime date, {CarBucket bucket = CarBucket.essential}) => CommuteDay(
      date: date,
      mode: CommuteMode.car,
      amount: 1.09,
      pricePerLitre: 1.689,
      priceSource: PriceSource.live,
      reasonId: bucket == CarBucket.missed ? 'lazy' : 'sport',
      bucket: bucket,
    );

CommuteDay remote(DateTime date) => CommuteDay.remote(date);

/// Les [count] premiers jours ouvres du mois, a velo.
List<CommuteDay> bikeMonth(int year, int month, int count) {
  final days = <CommuteDay>[];
  for (var day = 1; day <= daysOfMonth(DateTime(year, month)) && days.length < count; day++) {
    final date = DateTime(year, month, day);
    if (isWorkday(date)) {
      days.add(bike(date));
    }
  }
  return days;
}

void main() {
  final today = DateTime(2026, 9, 18);

  group('calendrier', () {
    test('un mois se note et se relit', () {
      expect(monthKey(DateTime(2026, 9)), '2026-09');
      expect(parseMonthKey('2026-09'), DateTime(2026, 9));
      expect(parseMonthKey('2026-13'), isNull);
      expect(parseMonthKey('septembre'), isNull);
    });

    test('le week-end n est pas un jour ouvre', () {
      expect(isWorkday(DateTime(2026, 9, 18)), isTrue);
      expect(isWorkday(DateTime(2026, 9, 19)), isFalse);
      expect(isWorkday(DateTime(2026, 9, 20)), isFalse);
    });

    test('septembre 2026 compte 22 jours ouvres', () {
      expect(daysOfMonth(DateTime(2026, 9)), 30);
      expect(workdaysIn(DateTime(2026, 9)), 22);
      expect(workdaysIn(DateTime(2026, 2)), 20);
    });

    test('les quatorze derniers jours ouvres sautent les week-ends', () {
      // Vendredi 18 septembre : du lundi 31 aout au vendredi 18, sans samedi
      // ni dimanche.
      final days = lastWorkdays(DateTime(2026, 9, 18, 8, 30), 14);

      expect(days.length, 14);
      expect(days.first, DateTime(2026, 8, 31));
      expect(days.last, DateTime(2026, 9, 18));
      expect(days.where((day) => !isWorkday(day)), isEmpty);
    });

    test('un dimanche, la liste finit le vendredi', () {
      final days = lastWorkdays(DateTime(2026, 9, 20), 14);

      expect(days.last, DateTime(2026, 9, 18));
      expect(days.first, DateTime(2026, 8, 31));
    });

    test('le lundi d une semaine se trouve depuis n importe quel jour', () {
      expect(mondayOf(DateTime(2026, 9, 18)), DateTime(2026, 9, 14));
      expect(mondayOf(DateTime(2026, 9, 14)), DateTime(2026, 9, 14));
      expect(mondayOf(DateTime(2026, 9, 20)), DateTime(2026, 9, 14));
    });
  });

  group('rythme', () {
    test('un euro par jour pendant trente jours fait un mois moyen', () {
      final days = [
        for (var back = 29; back >= 0; back--)
          bike(today.subtract(Duration(days: back)), amount: 1),
      ];

      final rate = SavingRate.of(days, now: today, window: RateWindow.all);

      expect(rate.spanDays, 30);
      expect(rate.saved, 30);
      expect(rate.perMonth, closeTo(30.44, 0.01));
      expect(rate.bikeDaysPerWeek, closeTo(7, 0.01));
      expect(rate.isMeasurable, isTrue);
    });

    test('la fenetre courte ne remonte pas avant le premier jour', () {
      // Quatre semaines d'historique seulement : diviser par huit donnerait un
      // rythme deux fois trop bas.
      final days = [
        for (var back = 27; back >= 0; back--)
          bike(today.subtract(Duration(days: back)), amount: 1),
      ];

      final recent = SavingRate.of(days, now: today, window: RateWindow.recent);

      expect(recent.from, today.subtract(const Duration(days: 27)));
      expect(recent.spanDays, 28);
      expect(recent.perMonth, closeTo(30.44, 0.01));
    });

    test('la fenetre courte coupe ce qui depasse huit semaines', () {
      final days = [
        for (var back = 120; back >= 0; back--)
          bike(today.subtract(Duration(days: back)), amount: 1),
      ];

      final recent = SavingRate.of(days, now: today, window: RateWindow.recent);
      final all = SavingRate.of(days, now: today, window: RateWindow.all);

      expect(recent.spanDays, 57);
      expect(recent.saved, 57);
      expect(all.spanDays, 121);
    });

    test('les journees en voiture ne remplissent pas la cagnotte', () {
      final days = [
        for (var back = 29; back >= 0; back--)
          back.isEven
              ? bike(today.subtract(Duration(days: back)), amount: 1)
              : car(today.subtract(Duration(days: back))),
      ];

      final rate = SavingRate.of(days, now: today, window: RateWindow.all);

      expect(rate.bikeDays, 15);
      expect(rate.saved, 15);
    });

    test('deux semaines au moins, sinon aucune date n est annoncee', () {
      final days = [
        for (var back = 12; back >= 0; back--)
          bike(today.subtract(Duration(days: back)), amount: 1),
      ];

      final rate = SavingRate.of(days, now: today, window: RateWindow.all);

      expect(rate.spanDays, 13);
      expect(rate.isMeasurable, isFalse);
      expect(rate.dateFor(50, from: today), isNull);
    });

    test('sans aucune journee, le rythme est nul et muet', () {
      final rate = SavingRate.of(const [], now: today, window: RateWindow.recent);

      expect(rate.perMonth, 0);
      expect(rate.isMeasurable, isFalse);
      expect(rate.dateFor(50, from: today), isNull);
    });

    test('la date projetee suit le montant qui reste', () {
      final days = [
        for (var back = 29; back >= 0; back--)
          bike(today.subtract(Duration(days: back)), amount: 1),
      ];
      final rate = SavingRate.of(days, now: today, window: RateWindow.all);

      final oneMonth = rate.dateFor(30.44, from: today);
      final twoMonths = rate.dateFor(60.88, from: today);

      expect(oneMonth!.difference(today).inDays, closeTo(30, 1));
      expect(twoMonths!.difference(today).inDays, closeTo(61, 1));
      // Rien a atteindre : aucune date.
      expect(rate.dateFor(0, from: today), isNull);
    });
  });

  group('series', () {
    test('une journee en voiture casse la serie, un jour vide non', () {
      final days = [
        bike(DateTime(2026, 9, 7)),
        bike(DateTime(2026, 9, 8)),
        // Le 9 n'est pas enregistre : la serie continue.
        bike(DateTime(2026, 9, 10)),
        bike(DateTime(2026, 9, 11)),
      ];

      expect(StreakInfo.of(days).current, 4);

      final broken = [...days, car(DateTime(2026, 9, 14))];

      expect(StreakInfo.of(broken).current, 0);
      expect(StreakInfo.of(broken).record, 4);
    });

    test('le teletravail ne casse pas la serie, et ne la prolonge pas', () {
      final days = [
        bike(DateTime(2026, 9, 7)),
        bike(DateTime(2026, 9, 8)),
        remote(DateTime(2026, 9, 9)),
        remote(DateTime(2026, 9, 10)),
        bike(DateTime(2026, 9, 11)),
      ];

      expect(StreakInfo.of(days).current, 3);
      expect(
        StreakInfo.of([...days, remote(DateTime(2026, 9, 14)), remote(DateTime(2026, 9, 15))],
                now: DateTime(2026, 9, 16))
            .current,
        3,
        reason: 'deux jours de teletravail ne sont pas deux oublis',
      );
    });

    test('le record retient son dernier jour', () {
      final days = [
        for (var day = 1; day <= 4; day++) bike(DateTime(2026, 6, day)),
        car(DateTime(2026, 6, 5)),
        bike(DateTime(2026, 6, 8)),
      ];

      final streak = StreakInfo.of(days);

      expect(streak.record, 4);
      expect(streak.recordEnd, DateTime(2026, 6, 4));
      expect(streak.current, 1);
      expect(streak.holdsRecord, isFalse);
      // Il faut depasser le record, pas l'egaler.
      expect(streak.toBeatRecord, 4);
    });

    test('la serie en cours peut porter le record', () {
      final days = [for (var day = 1; day <= 5; day++) bike(DateTime(2026, 6, day))];

      final streak = StreakInfo.of(days);

      expect(streak.current, 5);
      expect(streak.record, 5);
      expect(streak.holdsRecord, isTrue);
      expect(streak.toBeatRecord, 0);
    });

    test('un trajet par semaine ne fait pas une serie', () {
      // Trente trajets, un par semaine, sans une seule journee en voiture :
      // sans garde-fou, cela donnait « 30 jours d'affilee ».
      final days = [
        for (var week = 0; week < 30; week++)
          bike(DateTime(2026, 1, 5).add(Duration(days: week * 7 + 2))),
      ];

      final streak = StreakInfo.of(days);

      expect(streak.record, 1);
      expect(streak.current, 1);
    });

    test('le week-end et un oubli ne cassent rien', () {
      final days = [
        // Vendredi, puis le lundi suivant : le week-end ne compte pas.
        bike(DateTime(2026, 9, 11)),
        bike(DateTime(2026, 9, 14)),
        // Le 15 est oublie, le 16 reprend : un seul jour ouvre vide.
        bike(DateTime(2026, 9, 16)),
        bike(DateTime(2026, 9, 17)),
      ];

      expect(StreakInfo.of(days).current, 4);
    });

    test('deux jours ouvres vides cloturent la serie', () {
      final days = [
        bike(DateTime(2026, 9, 14)),
        // Le 15 et le 16 sont vides : le 17 repart de un.
        bike(DateTime(2026, 9, 17)),
      ];

      expect(StreakInfo.of(days).current, 1);
      expect(StreakInfo.of(days).record, 1);
    });

    test('une serie ancienne n est plus en cours', () {
      final days = [for (final day in [1, 2, 3]) bike(DateTime(2026, 9, day))];

      // Vue du 18, la derniere journee a quinze jours.
      expect(StreakInfo.of(days, now: today).current, 0);
      expect(StreakInfo.of(days, now: today).record, 3);
      // Vue du 4, lendemain du dernier trajet, elle court encore.
      expect(StreakInfo.of(days, now: DateTime(2026, 9, 4)).current, 3);
    });

    test('les jours ouvres entre deux dates excluent les bornes', () {
      // Du vendredi au lundi : rien entre les deux.
      expect(workdaysBetween(DateTime(2026, 9, 11), DateTime(2026, 9, 14)), 0);
      // Du lundi au jeudi : mardi et mercredi.
      expect(workdaysBetween(DateTime(2026, 9, 14), DateTime(2026, 9, 17)), 2);
      expect(workdaysBetween(DateTime(2026, 9, 14), DateTime(2026, 9, 15)), 0);
    });

    test('sans journee, ni serie ni record', () {
      final streak = StreakInfo.of(const []);

      expect(streak.current, 0);
      expect(streak.record, 0);
      expect(streak.recordEnd, isNull);
      expect(streak.holdsRecord, isFalse);
    });
  });

  group('regularite', () {
    test('chaque jour de la semaine compte ses natures', () {
      final regularity = Regularity([
        // Trois mardis : deux a velo, un en voiture par flemme.
        bike(DateTime(2026, 9, 1)),
        bike(DateTime(2026, 9, 8)),
        car(DateTime(2026, 9, 15), bucket: CarBucket.missed),
        // Un jeudi a velo.
        bike(DateTime(2026, 9, 3)),
      ]);

      final tuesday = regularity.weekdays.firstWhere((s) => s.weekday == DateTime.tuesday);

      expect(tuesday.bike, 2);
      expect(tuesday.missed, 1);
      expect(tuesday.essential, 0);
      expect(tuesday.recorded, 3);
      expect(tuesday.carDays, 1);
      expect(tuesday.flawless, isFalse);
      expect(regularity.weekdays.map((s) => s.weekday),
          [DateTime.tuesday, DateTime.thursday]);
    });

    test('le teletravail n entre ni dans les jours de la semaine ni dans les mois', () {
      final regularity = Regularity([
        bike(DateTime(2026, 9, 1)),
        remote(DateTime(2026, 9, 8)),
        remote(DateTime(2026, 9, 3)),
      ]);

      expect(regularity.weekdays.map((s) => s.weekday), [DateTime.tuesday]);
      expect(regularity.weekdays.single.recorded, 1);
      expect(regularity.months.single.recorded, 1);
    });

    test('le point faible demande trois journees et moins de trois quarts', () {
      // Deux mardis dont un en voiture : la moitie, mais sur deux journees.
      final thin = Regularity([
        bike(DateTime(2026, 9, 1)),
        car(DateTime(2026, 9, 8)),
      ]);

      expect(thin.weakestWeekday, isNull);

      final enough = Regularity([
        bike(DateTime(2026, 9, 1)),
        car(DateTime(2026, 9, 8)),
        car(DateTime(2026, 9, 15)),
      ]);

      expect(enough.weakestWeekday?.weekday, DateTime.tuesday);

      // Trois mardis dont un seul en voiture : deux tiers... non, 67 % reste
      // sous le seuil. Quatre sur cinq le depasse.
      final good = Regularity([
        for (final day in [1, 8, 15, 22]) bike(DateTime(2026, 9, day)),
        car(DateTime(2026, 9, 29)),
      ]);

      expect(good.weakestWeekday, isNull);
    });

    test('un jour sans la moindre voiture se distingue', () {
      final regularity = Regularity([
        for (final day in [3, 10, 17]) bike(DateTime(2026, 9, day)),
        car(DateTime(2026, 9, 1)),
      ]);

      expect(regularity.flawlessWeekday?.weekday, DateTime.thursday);
      expect(regularity.flawlessWeekday?.bike, 3);
    });

    test('le meilleur mois est celui qui compte le plus de velo', () {
      final regularity = Regularity([
        ...bikeMonth(2026, 6, 14),
        ...bikeMonth(2026, 7, 7),
        ...bikeMonth(2026, 8, 3),
      ]);

      expect(regularity.bestMonth?.month, DateTime(2026, 6));
      expect(regularity.bestMonth?.bike, 14);
      expect(regularity.months.map((m) => m.month),
          [DateTime(2026, 6), DateTime(2026, 7), DateTime(2026, 8)]);
    });

    test('un historique sans velo n a pas de meilleur mois', () {
      expect(Regularity([car(DateTime(2026, 9, 1))]).bestMonth, isNull);
      expect(Regularity(const []).bestMonth, isNull);
    });

    test('la grille compte ses semaines depuis la premiere journee', () {
      final regularity = Regularity([bike(DateTime(2026, 6, 1))]);

      // Du lundi 1er juin au lundi 14 septembre : seize semaines.
      expect(regularity.weeksSince(today), 16);
      expect(Regularity(const []).weeksSince(today), 0);
    });

    test('la derniere colonne de la grille est la semaine en cours', () {
      final regularity = Regularity([
        bike(DateTime(2026, 9, 14)),
        car(DateTime(2026, 9, 15)),
      ]);

      final weeks = regularity.lastWeeks(2, now: today);

      expect(weeks, hasLength(2));
      expect(weeks.last.monday, DateTime(2026, 9, 14));
      expect(weeks.first.monday, DateTime(2026, 9, 7));
      // Cinq cases, du lundi au vendredi.
      expect(weeks.last.days, hasLength(5));
      expect(weeks.last.days[0]?.isBike, isTrue);
      expect(weeks.last.days[1]?.isBike, isFalse);
      expect(weeks.last.days[4], isNull);
    });
  });

  group('defi du mois', () {
    final september = DateTime(2026, 9);

    // Dix journees a velo, trois en voiture, rien apres le 17.
    final days = [
      car(DateTime(2026, 9, 1), bucket: CarBucket.missed),
      car(DateTime(2026, 9, 2)),
      bike(DateTime(2026, 9, 3)),
      bike(DateTime(2026, 9, 4)),
      car(DateTime(2026, 9, 7)),
      for (final day in [8, 9, 10, 11, 14, 15, 16, 17]) bike(DateTime(2026, 9, day)),
    ];

    test('les journees du mois se comptent, et seulement elles', () {
      final challenge = MonthChallenge.of(
        september,
        target: 14,
        days: [...days, bike(DateTime(2026, 8, 31)), bike(DateTime(2026, 10, 1))],
        now: today,
      );

      expect(challenge.done, 10);
      expect(challenge.target, 14);
      expect(challenge.missing, 4);
      expect(challenge.workdays, 22);
      expect(challenge.ratio, closeTo(10 / 14, 0.001));
      expect(challenge.reached, isFalse);
    });

    test('les jours restants excluent le passe, les week-ends et le deja saisi', () {
      final challenge = MonthChallenge.of(september, target: 14, days: days, now: today);

      // Le 18, puis du 21 au 25, puis du 28 au 30 : neuf jours ouvres.
      expect(challenge.openWorkdays, 9);
      expect(challenge.stillPossible, isTrue);

      final recordedToday =
          MonthChallenge.of(september, target: 14, days: [...days, car(today)], now: today);

      // La journee du jour est jouee : il ne reste que huit jours.
      expect(recordedToday.openWorkdays, 8);
    });

    test('une cible hors d atteinte le dit', () {
      final challenge = MonthChallenge.of(september, target: 20, days: days, now: today);

      expect(challenge.missing, 10);
      expect(challenge.openWorkdays, 9);
      expect(challenge.stillPossible, isFalse);
    });

    test('une cible atteinte reste atteinte, meme sans jour restant', () {
      final challenge = MonthChallenge.of(
        september,
        target: 8,
        days: days,
        now: DateTime(2026, 9, 30),
      );

      expect(challenge.reached, isTrue);
      expect(challenge.missing, 0);
      expect(challenge.ratio, 1);
      expect(challenge.stillPossible, isTrue);
    });

    test('un mois passe n a plus de jour a jouer', () {
      final challenge = MonthChallenge.of(
        DateTime(2026, 8),
        target: 10,
        days: bikeMonth(2026, 8, 3),
        now: today,
      );

      expect(challenge.done, 3);
      expect(challenge.openWorkdays, 0);
      expect(challenge.stillPossible, isFalse);
    });

    test('la cible proposee est la moyenne des trois mois precedents', () {
      final history = [
        ...bikeMonth(2026, 6, 14),
        ...bikeMonth(2026, 7, 7),
        ...bikeMonth(2026, 8, 3),
      ];

      expect(suggestedTarget(september, days: history), 8);
    });

    test('sans historique, aucune cible n est proposee', () {
      expect(suggestedTarget(september, days: const []), isNull);
      // Des journees trop anciennes ne comptent pas : juin est hors des trois
      // mois precedant decembre.
      expect(suggestedTarget(DateTime(2026, 12), days: bikeMonth(2026, 6, 14)), isNull);
    });

    test('la proposition ne sort jamais des jours ouvres du mois', () {
      // Trois mois pleins de velo : la moyenne depasserait les jours ouvres de
      // fevrier.
      final history = [
        ...bikeMonth(2025, 11, 21),
        ...bikeMonth(2025, 12, 22),
        ...bikeMonth(2026, 1, 22),
      ];

      final suggestion = suggestedTarget(DateTime(2026, 2), days: history);

      expect(suggestion, lessThanOrEqualTo(workdaysIn(DateTime(2026, 2))));
      expect(suggestion, greaterThanOrEqualTo(1));
    });

    test('une cible se note et se relit', () {
      final target = ChallengeTarget(month: DateTime(2026, 9), target: 14);

      final read = ChallengeTarget.fromJson(target.toJson());

      expect(read?.month, DateTime(2026, 9));
      expect(read?.target, 14);
      expect(ChallengeTarget.fromJson({'month': '2026-09'}), isNull);
      expect(ChallengeTarget.fromJson({'month': '2026-09', 'target': 0}), isNull);
      expect(ChallengeTarget.fromJson('14'), isNull);
    });
  });
}
