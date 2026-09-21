import 'package:i_zerak_app/models/commute_dao.dart';
import 'package:i_zerak_app/models/gas_station_dao.dart';
import 'package:test/test.dart';

const _settings = CommuteSettings(distanceKm: 12.4, consumption: 5.2);
const _price = ResolvedPrice(pricePerLitre: 1.689, source: PriceSource.live);

CommuteDay _bike(int day, {double amount = 1.09}) => CommuteDay(
      date: DateTime(2026, 9, day),
      mode: CommuteMode.bike,
      amount: amount,
      pricePerLitre: 1.689,
      priceSource: PriceSource.live,
    );

CommuteDay _car(int day, CarBucket bucket, {double amount = 1.09}) => CommuteDay(
      date: DateTime(2026, 9, day),
      mode: CommuteMode.car,
      amount: amount,
      pricePerLitre: 1.689,
      priceSource: PriceSource.live,
      reasonId: bucket == CarBucket.missed ? CarReason.lazy : CarReason.sport,
      bucket: bucket,
    );

Goal _goal(String id, double target, GoalKind kind, {DateTime? validatedAt}) => Goal(
      id: id,
      name: id,
      target: target,
      kind: kind,
      icon: GoalIcon.star,
      createdAt: DateTime(2026, 9, 1),
      validatedAt: validatedAt,
    );

void main() {
  group('valeur d un trajet', () {
    test('distance aller-retour x consommation x prix, au centime', () {
      // 12,4 km x 5,2 L/100 km = 0,6448 L, a 1,689 €/L = 1,0891 €.
      expect(_settings.tripValue(1.689), 1.09);
    });

    test('sans distance renseignee, un trajet ne vaut rien', () {
      // Une distance par defaut remplirait la cagnotte de montants inventes.
      expect(const CommuteSettings().isConfigured, isFalse);
      expect(const CommuteSettings().tripValue(1.689), 0);
    });

    test('un jour a velo fige le prix et le montant du jour', () {
      final day = CommuteDay.bike(DateTime(2026, 9, 18, 8, 30), _settings, _price);

      expect(day.date, DateTime(2026, 9, 18));
      expect(day.amount, 1.09);
      expect(day.pricePerLitre, 1.689);
      expect(day.bucket, isNull);
    });

    test('un jour en voiture retient la cagnotte de sa raison au moment du trajet', () {
      const reason = CarReason(id: 'x', label: 'Rendez-vous', bucket: CarBucket.missed);
      final day = CommuteDay.car(DateTime(2026, 9, 18), _settings, _price, reason);

      expect(day.bucket, CarBucket.missed);
      expect(day.reasonLabel, 'Rendez-vous');
    });
  });

  group('cagnotte', () {
    test('seuls les jours a velo l alimentent', () {
      final ledger = CommuteLedger(
          [_bike(1), _bike(2), _car(3, CarBucket.essential), _car(4, CarBucket.missed)], const []);

      expect(ledger.totalSaved, 2.18);
      expect(ledger.balance, 2.18);
      expect(ledger.totals.essential, 1.09);
      expect(ledger.totals.missed, 1.09);
      expect(ledger.totals.bikeDays, 2);
    });

    test('les sommes ne derivent pas avec les arrondis', () {
      // Cent additions de 0,1 en double donnent 9,99999… : la cagnotte doit
      // afficher 10,00 €.
      final ledger = CommuteLedger([for (var i = 1; i <= 100; i++) _bike(1 + i % 28, amount: 0.1)], const []);
      expect(ledger.totalSaved, 10.0);
    });

    test('un achat valide sort du solde, pas du total economise', () {
      final ledger = CommuteLedger(
        [for (var d = 1; d <= 10; d++) _bike(d, amount: 5)],
        [_goal('sacoche', 35, GoalKind.purchase, validatedAt: DateTime(2026, 9, 15))],
      );

      expect(ledger.totalSaved, 50);
      expect(ledger.spent, 35);
      expect(ledger.balance, 15);
    });

    test('un palier valide ne coute rien', () {
      final ledger = CommuteLedger(
        [for (var d = 1; d <= 10; d++) _bike(d, amount: 5)],
        [_goal('palier', 40, GoalKind.milestone, validatedAt: DateTime(2026, 9, 15))],
      );

      expect(ledger.spent, 0);
      expect(ledger.balance, 50);
    });
  });

  group('objectifs', () {
    final days = [for (var d = 1; d <= 10; d++) _bike(d, amount: 4)]; // 40 €

    test('un achat avance avec le solde, un palier avec le total', () {
      final bought = _goal('casque', 30, GoalKind.purchase, validatedAt: DateTime(2026, 9, 12));
      final bag = _goal('sacoche', 35, GoalKind.purchase);
      final bike = _goal('velo', 450, GoalKind.milestone);
      final ledger = CommuteLedger(days, [bought, bag, bike]);

      // Le casque paye, il reste 10 € : la sacoche recule, le palier non.
      expect(ledger.progressOf(bag).current, 10);
      expect(ledger.progressOf(bag).reached, isFalse);
      expect(ledger.progressOf(bike).current, 40);
    });

    test('atteint au centime pres, et le reste ne passe jamais sous zero', () {
      final ledger = CommuteLedger(days, [_goal('pile', 40, GoalKind.purchase)]);
      final progress = ledger.progressOf(ledger.goals.single);

      expect(progress.reached, isTrue);
      expect(progress.remaining, 0);
      expect(progress.ratio, 1);
    });

    test('les objectifs valides quittent la liste active', () {
      final ledger = CommuteLedger(days, [
        _goal('a', 10, GoalKind.purchase, validatedAt: DateTime(2026, 9, 5)),
        _goal('b', 10, GoalKind.purchase),
      ]);

      expect(ledger.activeGoals.map((g) => g.id), ['b']);
      expect(ledger.validatedGoals.map((g) => g.id), ['a']);
    });
  });

  group('raisons', () {
    test('les usages se comptent par raison, les jours a velo n en ont pas', () {
      final uses = reasonUses(
          [_bike(1), _car(2, CarBucket.missed), _car(3, CarBucket.missed), _car(4, CarBucket.essential)]);

      expect(uses, {CarReason.lazy: 2, CarReason.sport: 1});
    });

    test('une raison livree renommee reste une raison livree', () {
      final renamed = CarReason.defaults.last.withLabel('Pas motivé');

      expect(renamed.isBuiltIn, isTrue);
      expect(renamed.label, 'Pas motivé');
      expect(renamed.withLabel(null).label, isNull);
    });

    test('le renommage survit a la relecture', () {
      final settings = CommuteSettings(reasons: [CarReason.defaults.first.withLabel('Escalade')]);
      final read = CommuteSettings.fromJson(settings.toJson());

      expect(read.reasons.single.id, CarReason.sport);
      expect(read.reasons.single.label, 'Escalade');
    });
  });

  group('persistance', () {
    test('un jour se relit a l identique', () {
      final day = CommuteDay.car(
        DateTime(2026, 9, 18),
        _settings,
        const ResolvedPrice(pricePerLitre: 1.7, source: PriceSource.lastKnown, stationLabel: 'Leclerc'),
        CarReason.defaults.first,
      );
      final read = CommuteDay.fromJson(day.toJson())!;

      expect(read.date, day.date);
      expect(read.amount, day.amount);
      expect(read.priceSource, PriceSource.lastKnown);
      expect(read.stationLabel, 'Leclerc');
      expect(read.bucket, CarBucket.essential);
      expect(read.reasonId, CarReason.sport);
    });

    test('des reglages illisibles retombent sur les valeurs par defaut', () {
      final settings = CommuteSettings.fromJson({'consumption': 'beaucoup', 'fuel': 'kerosene'});

      expect(settings.consumption, 5.2);
      expect(settings.fuel, FuelType.gazole);
      expect(settings.reasons.length, 3);
    });

    test('une liste de raisons videe par l utilisateur reste vide', () {
      final settings = CommuteSettings.fromJson(const CommuteSettings(reasons: []).toJson());
      expect(settings.reasons, isEmpty);
    });

    test('un objectif se relit a l identique', () {
      final goal = _goal('velo', 450, GoalKind.milestone, validatedAt: DateTime(2026, 9, 20, 18));
      final read = Goal.fromJson(goal.toJson())!;

      expect(read.kind, GoalKind.milestone);
      expect(read.target, 450);
      expect(read.validatedAt, DateTime(2026, 9, 20, 18));
    });
  });
}
