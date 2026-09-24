import 'package:i_zerak_app/models/subscription_dao.dart';
import 'package:test/test.dart';

Subscription _sub(
  String name,
  double price,
  SubscriptionFrequency frequency, {
  String? category,
  DateTime? next,
  bool active = true,
}) =>
    Subscription(
      id: name,
      name: name,
      price: price,
      subscriptionType: frequency,
      categoryId: category,
      nextPayment: next,
      isActive: active,
    );

/// Le jeu d'essai de la maquette : huit abonnements actifs, deux suspendus.
List<Subscription> _sample() => [
      _sub('Panier de legumes', 18, SubscriptionFrequency.weekly,
          category: SubscriptionCategory.home, next: DateTime(2026, 9, 22)),
      _sub('Assurance auto', 720, SubscriptionFrequency.yearly,
          category: SubscriptionCategory.insurance, next: DateTime(2027, 3, 12)),
      _sub('Salle de sport', 34.90, SubscriptionFrequency.monthly,
          category: SubscriptionCategory.sport, next: DateTime(2026, 10, 5)),
      _sub('Netflix', 13.49, SubscriptionFrequency.monthly,
          category: SubscriptionCategory.video, next: DateTime(2026, 9, 28)),
      _sub('Forfait mobile', 12.99, SubscriptionFrequency.monthly,
          category: SubscriptionCategory.telecom, next: DateTime(2026, 10, 2)),
      _sub('Spotify', 11.99, SubscriptionFrequency.monthly,
          category: SubscriptionCategory.music, next: DateTime(2026, 9, 26)),
      _sub('Disney+', 5.99, SubscriptionFrequency.monthly,
          category: SubscriptionCategory.video, next: DateTime(2026, 9, 19)),
      _sub('iCloud', 2.99, SubscriptionFrequency.monthly,
          category: SubscriptionCategory.software, next: DateTime(2026, 9, 24)),
      _sub('Presse en ligne', 11.99, SubscriptionFrequency.monthly, active: false),
      _sub('Cloud gaming', 9.99, SubscriptionFrequency.monthly, active: false),
    ];

void main() {
  group('conversion entre unites', () {
    test('un montant hebdomadaire se lit au mois et a l annee', () {
      final basket = _sub('Panier', 18, SubscriptionFrequency.weekly);

      expect(basket.amountIn(SubscriptionFrequency.weekly), closeTo(18, 0.001));
      expect(basket.amountIn(SubscriptionFrequency.monthly), closeTo(78, 0.001));
      expect(basket.amountIn(SubscriptionFrequency.yearly), closeTo(936, 0.001));
    });

    test('un montant annuel se lit au mois', () {
      final insurance = _sub('Assurance', 720, SubscriptionFrequency.yearly);

      expect(insurance.amountIn(SubscriptionFrequency.monthly), closeTo(60, 0.001));
    });

    test('une facturation hebdomadaire pese plus qu une mensuelle plus chere', () {
      final basket = _sub('Panier', 18, SubscriptionFrequency.weekly);
      final gym = _sub('Sport', 34.90, SubscriptionFrequency.monthly);

      expect(basket.yearlyAmount, greaterThan(gym.yearlyAmount));
    });
  });

  group('totaux', () {
    test('seuls les abonnements actifs comptent', () {
      final ledger = SubscriptionLedger(_sample());

      expect(ledger.active, hasLength(8));
      expect(ledger.suspended, hasLength(2));
      expect(roundCents(ledger.totalIn(SubscriptionFrequency.monthly)), 220.35);
      expect(roundCents(ledger.totalIn(SubscriptionFrequency.yearly)), 2644.20);
      expect(roundCents(ledger.suspendedTotalIn(SubscriptionFrequency.monthly)), 21.98);
    });

    test('la liste est triee du plus lourd au plus leger, toutes frequences melangees', () {
      final ledger = SubscriptionLedger(_sample());

      expect(
        ledger.active.take(3).map((subscription) => subscription.name),
        ['Panier de legumes', 'Assurance auto', 'Salle de sport'],
      );
    });

    test('une categorie regroupe ses abonnements', () {
      final totals = SubscriptionLedger(_sample()).byCategory(SubscriptionFrequency.monthly);
      final video =
          totals.firstWhere((total) => total.categoryId == SubscriptionCategory.video);

      expect(video.count, 2);
      expect(roundCents(video.amount), 19.48);
      expect(video.share, closeTo(19.48 / 220.35, 0.0001));
      expect(totals.first.categoryId, SubscriptionCategory.home);
      expect(
        totals.fold<double>(0, (sum, total) => sum + total.share),
        closeTo(1, 0.0001),
      );
    });

    test('les abonnements sans categorie sont regroupes a part', () {
      final ledger = SubscriptionLedger([
        _sub('Sans', 10, SubscriptionFrequency.monthly),
        _sub('Avec', 10, SubscriptionFrequency.monthly, category: SubscriptionCategory.home),
      ]);

      final totals = ledger.byCategory(SubscriptionFrequency.monthly);
      expect(totals.map((total) => total.categoryId), containsAll([null, SubscriptionCategory.home]));
    });
  });

  group('echeances', () {
    test('un abonnement hebdomadaire tombe tous les mardis du mois', () {
      final basket = _sub('Panier', 18, SubscriptionFrequency.weekly,
          next: DateTime(2026, 9, 22));

      final dates = basket.occurrencesIn(DateTime(2026, 9, 1), DateTime(2026, 9, 30));

      expect(dates.map((date) => date.day), [1, 8, 15, 22, 29]);
    });

    test('le 31 devient le dernier jour des mois plus courts', () {
      final rent = _sub('Loyer', 500, SubscriptionFrequency.monthly,
          next: DateTime(2026, 1, 31));

      final february = rent.occurrencesIn(DateTime(2026, 2, 1), DateTime(2026, 2, 28));

      expect(february.single, DateTime(2026, 2, 28));
    });

    test('le 29 fevrier devient le 28 hors annee bissextile', () {
      final yearly = _sub('Annuel', 100, SubscriptionFrequency.yearly,
          next: DateTime(2028, 2, 29));

      final dates = yearly.occurrencesIn(DateTime(2027, 2, 1), DateTime(2027, 2, 28));

      expect(dates.single, DateTime(2027, 2, 28));
    });

    test('la serie remonte avant la date saisie', () {
      final netflix = _sub('Netflix', 13.49, SubscriptionFrequency.monthly,
          next: DateTime(2026, 9, 28));

      final july = netflix.occurrencesIn(DateTime(2026, 7, 1), DateTime(2026, 7, 31));

      expect(july.single, DateTime(2026, 7, 28));
    });

    test('sans date, un abonnement n a aucune echeance', () {
      final orphan = _sub('Sans date', 10, SubscriptionFrequency.monthly);

      expect(orphan.occurrencesIn(DateTime(2026, 9, 1), DateTime(2026, 9, 30)), isEmpty);
      expect(orphan.nextPaymentOnOrAfter(DateTime(2026, 9, 18)), isNull);
    });

    test('la prochaine echeance inclut le jour meme', () {
      final today = DateTime(2026, 9, 18);
      final sub = _sub('Aujourd hui', 5, SubscriptionFrequency.monthly, next: today);

      expect(sub.nextPaymentOnOrAfter(today), today);
    });

    test('une date depassee avance jusqu au mois suivant', () {
      final sub = _sub('Passe', 5, SubscriptionFrequency.monthly,
          next: DateTime(2026, 6, 28));

      expect(sub.nextPaymentOnOrAfter(DateTime(2026, 9, 29)), DateTime(2026, 10, 28));
    });
  });

  group('prelevements d un mois', () {
    test('ils sont ordonnes par date, au montant reellement facture', () {
      final ledger = SubscriptionLedger(_sample());

      final payments = ledger.paymentsIn(DateTime(2026, 9, 1), DateTime(2026, 9, 30));

      expect(payments.map((payment) => payment.date.day),
          [1, 2, 5, 8, 15, 19, 22, 24, 26, 28, 29]);
      // Le panier est facture 18 € par semaine, et non ses 78 € mensuels.
      expect(payments.first.amount, 18);
      expect(roundCents(SubscriptionLedger.totalOf(payments)), 172.35);
    });

    test('un abonnement suspendu ne tombe plus', () {
      final ledger = SubscriptionLedger([
        _sub('Suspendu', 10, SubscriptionFrequency.monthly,
            next: DateTime(2026, 9, 10), active: false),
      ]);

      expect(ledger.paymentsIn(DateTime(2026, 9, 1), DateTime(2026, 9, 30)), isEmpty);
    });

    test('l assurance annuelle explique l ecart avec la moyenne', () {
      final ledger = SubscriptionLedger(_sample());

      final september = ledger.paymentsIn(DateTime(2026, 9, 1), DateTime(2026, 9, 30));
      final march = ledger.paymentsIn(DateTime(2027, 3, 1), DateTime(2027, 3, 31));

      expect(SubscriptionLedger.totalOf(september),
          lessThan(ledger.totalIn(SubscriptionFrequency.monthly)));
      expect(SubscriptionLedger.totalOf(march),
          greaterThan(ledger.totalIn(SubscriptionFrequency.monthly)));
    });
  });

  group('lecture tolerante', () {
    test('un aller-retour JSON conserve tout', () {
      final source = _sub('Netflix', 13.49, SubscriptionFrequency.monthly,
          category: SubscriptionCategory.video, next: DateTime(2026, 9, 28));
      source.iconId = 'film';

      final copy = Subscription.fromJson('x', source.toJson());

      expect(copy.name, 'Netflix');
      expect(copy.price, 13.49);
      expect(copy.subscriptionType, SubscriptionFrequency.monthly);
      expect(copy.categoryId, SubscriptionCategory.video);
      expect(copy.nextPayment, DateTime(2026, 9, 28));
      expect(copy.iconId, 'film');
    });

    test('un champ abime ne fait pas echouer la lecture', () {
      final copy = Subscription.fromJson('x', const {
        'name': 'Abime',
        'price': 'douze',
        'subscriptionType': 'inconnu',
        'nextPayment': 'pas une date',
        'isActive': 'oui',
      });

      expect(copy.price, 0);
      expect(copy.subscriptionType, SubscriptionFrequency.monthly);
      expect(copy.nextPayment, isNull);
      expect(copy.isActive, isTrue);
    });

    test('l heure est ecartee de la date d echeance', () {
      final sub = Subscription(nextPayment: DateTime(2026, 9, 28, 23, 45));

      expect(sub.nextPayment, DateTime(2026, 9, 28));
    });
  });
}
