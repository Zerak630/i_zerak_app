import 'package:i_zerak_app/models/budget_dao.dart';
import 'package:i_zerak_app/models/commute_dao.dart' hide dateOnly, roundCents;
import 'package:i_zerak_app/models/subscription_dao.dart';
import 'package:test/test.dart';

const _settings = CommuteSettings(distanceKm: 12.4, consumption: 5.2);
const _price = ResolvedPrice(pricePerLitre: 1.689, source: PriceSource.live);

CommuteDay _bike(int day) => CommuteDay.bike(DateTime(2026, 9, day), _settings, _price);

CommuteDay _car(int day, {CarBucket bucket = CarBucket.essential}) => CommuteDay.car(
      DateTime(2026, 9, day),
      _settings,
      _price,
      CarReason(id: bucket == CarBucket.essential ? 'sport' : 'lazy', bucket: bucket),
    );

Subscription _sub(
  String name,
  double price,
  SubscriptionFrequency frequency,
  DateTime next,
) =>
    Subscription(
      id: name,
      name: name,
      price: price,
      subscriptionType: frequency,
      nextPayment: next,
    );

void main() {
  final september = DateTime(2026, 9, 18);

  SubscriptionLedger subscriptions() => SubscriptionLedger([
        _sub('Panier', 18, SubscriptionFrequency.weekly, DateTime(2026, 9, 22)),
        _sub('Netflix', 13.49, SubscriptionFrequency.monthly, DateTime(2026, 9, 28)),
        _sub('Assurance', 720, SubscriptionFrequency.yearly, DateTime(2027, 3, 12)),
      ]);

  CommuteLedger commute() => CommuteLedger(
        [_bike(1), _bike(2), _car(3), _car(4, bucket: CarBucket.missed), _bike(30)],
        const [],
      );

  test('le mois additionne les abonnements preleves et les trajets en voiture', () {
    final budget = budgetOf(september, subscriptions: subscriptions(), commute: commute());

    // Cinq mardis a 18 €, plus Netflix le 28.
    expect(roundCents(budget.subscriptions), 103.49);
    expect(budget.subscriptionCount, 6);
    expect(budget.carDays, 2);
    expect(roundCents(budget.total), roundCents(103.49 + budget.carTrips));
  });

  test('le velo ne s ajoute pas au total : c est une depense evitee', () {
    final budget = budgetOf(september, subscriptions: subscriptions(), commute: commute());

    expect(budget.bikeDays, 3);
    expect(budget.bikeSaved, greaterThan(0));
    expect(roundCents(budget.total), roundCents(budget.subscriptions + budget.carTrips));
  });

  test('un abonnement annuel ne pese que sur son mois d echeance', () {
    final march = budgetOf(DateTime(2027, 3, 4),
        subscriptions: subscriptions(), commute: commute());
    final april = budgetOf(DateTime(2027, 4, 4),
        subscriptions: subscriptions(), commute: commute());

    expect(march.subscriptions, greaterThan(700));
    expect(april.subscriptions, lessThan(200));
  });

  test('les parts se repartissent entre abonnements et voiture', () {
    final budget = budgetOf(september, subscriptions: subscriptions(), commute: commute());

    expect(budget.subscriptionShare, closeTo(budget.subscriptions / budget.total, 0.0001));
    expect(budget.subscriptionShare, inInclusiveRange(0, 1));
  });

  test('un mois sans rien est vide, et sa part ne divise pas par zero', () {
    final budget = budgetOf(
      DateTime(2020, 1, 15),
      subscriptions: SubscriptionLedger(const []),
      commute: CommuteLedger(const [], const []),
    );

    expect(budget.isEmpty, isTrue);
    expect(budget.total, 0);
    expect(budget.subscriptionShare, 0);
  });

  test('l historique se lit de gauche a droite, le mois courant en dernier', () {
    final history = budgetHistory(september,
        count: 6, subscriptions: subscriptions(), commute: commute());

    expect(history, hasLength(6));
    expect(history.first.month, DateTime(2026, 4));
    expect(history.last.month, DateTime(2026, 9));
  });

  test('l historique franchit le changement d annee', () {
    final history = budgetHistory(DateTime(2027, 2, 10),
        count: 4, subscriptions: subscriptions(), commute: commute());

    expect(history.map((month) => month.month),
        [DateTime(2026, 11), DateTime(2026, 12), DateTime(2027, 1), DateTime(2027, 2)]);
  });
}
