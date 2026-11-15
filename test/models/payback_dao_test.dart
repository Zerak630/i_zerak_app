import 'package:i_zerak_app/models/commute_dao.dart';
import 'package:i_zerak_app/models/payback_dao.dart';
import 'package:i_zerak_app/models/subscription_dao.dart';
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
  final subscriptions = [
    sub('Forfait', 20),
    sub('Spotify', 10.99),
    sub('Netflix', 13.49),
    // 120 € par an : 10 € par mois, pas 120 € le mois de l'echeance.
    sub('Stockage', 120, frequency: SubscriptionFrequency.yearly),
    sub('Ancien', 8, active: false),
  ];

  group('ce que le velo rembourse', () {
    test('du moins cher au plus cher, et le reste entame le suivant', () {
      final ledger = CommuteLedger([
        for (var day = 3; day <= 12; day++) _bike(DateTime(2026, 11, day), 3.42), // 34,20 €
        _bike(DateTime(2026, 10, 30), 50), // un autre mois : ne compte pas
      ], const []);
      final payback = paybackOf(DateTime(2026, 11, 15), subscriptions: subscriptions, commute: ledger);

      expect(payback.saved, 34.2);
      expect(payback.bikeDays, 10);
      expect(payback.lines.map((line) => line.subscription.name),
          ['Stockage', 'Spotify', 'Netflix', 'Forfait']);
      expect(payback.lines[0].monthly, 10);
      expect([for (final line in payback.lines) line.paid], [true, true, false, false]);
      // 34,20 - 10 - 10,99 = 13,21 : Netflix est entame, le forfait pas.
      expect(payback.lines[2].covered, 13.21);
      expect(payback.lines[2].remaining, 0.28);
      expect(payback.lines[3].covered, 0);
      expect(payback.paidCount, 2);
      expect(payback.next!.subscription.name, 'Netflix');
      expect(payback.surplus, 0);
    });

    test('un abonnement entame montre ce qui manque', () {
      final ledger = CommuteLedger([_bike(DateTime(2026, 11, 2), 15)], const []);
      final payback = paybackOf(DateTime(2026, 11, 2), subscriptions: subscriptions, commute: ledger);

      expect(payback.lines[0].paid, isTrue);
      expect(payback.lines[1].covered, 5);
      expect(payback.lines[1].remaining, 5.99);
      expect(payback.next!.subscription.name, 'Spotify');
      expect(payback.covered, 15);
    });

    test('tout rembourse : le surplus est annonce', () {
      final ledger = CommuteLedger([_bike(DateTime(2026, 11, 2), 60)], const []);
      final payback = paybackOf(DateTime(2026, 11, 2), subscriptions: subscriptions, commute: ledger);

      expect(payback.allPaid, isTrue);
      expect(payback.next, isNull);
      expect(payback.total, 54.48);
      expect(payback.surplus, 5.52);
    });

    test('les abonnements exclus ne sont pas rembourses', () {
      final ledger = CommuteLedger([_bike(DateTime(2026, 11, 2), 12)], const []);
      final payback = paybackOf(
        DateTime(2026, 11, 2),
        subscriptions: subscriptions,
        commute: ledger,
        excluded: {'Stockage'},
      );

      expect(payback.lines.map((line) => line.subscription.name), ['Spotify', 'Netflix', 'Forfait']);
      expect(payback.lines.first.paid, isTrue);
    });

    test('l historique remonte mois par mois, le plus recent en tete', () {
      final ledger = CommuteLedger([
        _bike(DateTime(2026, 9, 10), 4),
        _bike(DateTime(2026, 11, 10), 6),
      ], const []);
      final history = paybackHistory(DateTime(2026, 11, 20),
          count: 3, subscriptions: subscriptions, commute: ledger);

      expect(history.map((month) => month.month),
          [DateTime(2026, 11), DateTime(2026, 10), DateTime(2026, 9)]);
      expect(history.map((month) => month.saved), [6, 0, 4]);
    });
  });

  test('les exclusions se relisent avec les reglages', () {
    final settings = CommuteSettings.fromJson(
        const CommuteSettings(paybackExcluded: {'loyer', 'assurance'}).toJson());
    expect(settings.paybackExcluded, {'loyer', 'assurance'});
    expect(const CommuteSettings().toJson().containsKey('payback_excluded'), isFalse);
  });
}
