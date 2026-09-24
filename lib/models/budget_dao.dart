/// Ce que coute un mois : les abonnements preleves et les trajets faits en
/// voiture, reunis pour la premiere fois.
///
/// Dart pur : rien n'est stocke ici, tout se recalcule a partir des
/// abonnements et des journees deja enregistrees. Un mois ne peut donc pas
/// diverger de ce qui le compose, et corriger une journee corrige le budget.
library;

// `roundCents` et `dateOnly` existent dans les deux modeles, a l'identique :
// les masquer ici evite le conflit sans rien changer au calcul.
import 'package:i_zerak_app/models/commute_dao.dart' hide dateOnly, roundCents;
import 'package:i_zerak_app/models/subscription_dao.dart';

/// Le budget d'un mois.
class MonthBudget {
  const MonthBudget({
    required this.month,
    required this.subscriptions,
    required this.subscriptionCount,
    required this.carTrips,
    required this.carDays,
    required this.bikeSaved,
    required this.bikeDays,
  });

  /// Le premier jour du mois decrit.
  final DateTime month;

  /// Ce que les abonnements ont reellement preleve ce mois-ci, et non leur
  /// moyenne mensuelle : un annuel pese sur son seul mois d'echeance.
  final double subscriptions;
  final int subscriptionCount;

  /// Les trajets domicile-travail faits en voiture, toutes raisons confondues.
  final double carTrips;
  final int carDays;

  /// Ce que le velo a evite le meme mois. Ne s'ajoute pas au total : c'est une
  /// depense qui n'a pas eu lieu.
  final double bikeSaved;
  final int bikeDays;

  double get total => subscriptions + carTrips;

  /// Part des abonnements dans le total, entre 0 et 1.
  double get subscriptionShare => total <= 0 ? 0 : subscriptions / total;

  bool get isEmpty => subscriptionCount == 0 && carDays == 0 && bikeDays == 0;
}

/// Le budget du mois qui contient [month].
MonthBudget budgetOf(
  DateTime month, {
  required SubscriptionLedger subscriptions,
  required CommuteLedger commute,
}) {
  final first = DateTime(month.year, month.month);
  final last = DateTime(month.year, month.month, daysInMonth(month.year, month.month));
  final payments = subscriptions.paymentsIn(first, last);
  final trips = commute.monthTotals(month.year, month.month);

  return MonthBudget(
    month: first,
    subscriptions: SubscriptionLedger.totalOf(payments),
    subscriptionCount: payments.length,
    carTrips: trips.essential + trips.missed,
    carDays: trips.essentialDays + trips.missedDays,
    bikeSaved: trips.bike,
    bikeDays: trips.bikeDays,
  );
}

/// Les [count] derniers mois, du plus ancien au plus recent, [until] compris.
///
/// L'ordre est celui d'un graphique qu'on lit de gauche a droite.
List<MonthBudget> budgetHistory(
  DateTime until, {
  int count = 6,
  required SubscriptionLedger subscriptions,
  required CommuteLedger commute,
}) =>
    [
      for (var back = count - 1; back >= 0; back--)
        budgetOf(
          DateTime(until.year, until.month - back),
          subscriptions: subscriptions,
          commute: commute,
        ),
    ];
