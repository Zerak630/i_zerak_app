/// Ce que le velo rembourse : l'essence economisee d'un mois, face aux
/// abonnements que l'on paie deja.
///
/// La cagnotte attendait qu'on lui donne un but, et personne ne le faisait.
/// Les abonnements, eux, sont deja la, et reviennent chaque mois : ils font des
/// objectifs tout trouves, qui se remettent a zero avec les prelevements.
///
/// Dart pur, comme `budget_dao.dart` : rien n'est stocke ici, tout se
/// recalcule a partir des abonnements et des journees deja enregistrees.
library;

import 'package:i_zerak_app/models/commute_dao.dart';
import 'package:i_zerak_app/models/subscription_dao.dart'
    show Subscription, SubscriptionFrequency;

/// Un abonnement, et ce que le velo en a rembourse ce mois-la.
class PaybackLine {
  const PaybackLine({required this.subscription, required this.monthly, required this.covered});

  final Subscription subscription;

  /// Ce que l'abonnement coute par mois, quelle que soit sa frequence : un
  /// annuel de 120 € compte pour 10 € chaque mois, et non pour 120 € le seul
  /// mois de son echeance — il avalerait sinon tout ce que le velo rapporte.
  final double monthly;

  /// La part remboursee, entre 0 et [monthly].
  final double covered;

  bool get paid => covered + 0.005 >= monthly;

  double get remaining => paid ? 0 : roundCents(monthly - covered);

  double get ratio => monthly <= 0 ? 1 : (covered / monthly).clamp(0, 1).toDouble();
}

/// Un mois : l'essence economisee, et les abonnements qu'elle couvre.
class MonthPayback {
  const MonthPayback({
    required this.month,
    required this.saved,
    required this.bikeDays,
    required this.lines,
  });

  /// Le premier jour du mois decrit.
  final DateTime month;

  /// L'essence que le velo a evitee ce mois-la.
  final double saved;
  final int bikeDays;

  /// Du moins cher au plus cher : c'est l'ordre dans lequel le velo les
  /// rembourse. Commencer par les petits fait tomber une premiere case des
  /// les premiers trajets, plutot que d'entamer un forfait a 40 € que le mois
  /// ne finira peut-etre pas.
  final List<PaybackLine> lines;

  /// Ce que coutent, par mois, les abonnements suivis.
  double get total => roundCents(lines.fold(0.0, (sum, line) => sum + line.monthly));

  /// Ce qui en a ete rembourse.
  double get covered => roundCents(lines.fold(0.0, (sum, line) => sum + line.covered));

  int get paidCount => lines.where((line) => line.paid).length;

  bool get allPaid => lines.isNotEmpty && paidCount == lines.length;

  /// Ce que le velo a economise au-dela de tous les abonnements.
  double get surplus => saved > total ? roundCents(saved - total) : 0;

  double get ratio => total <= 0 ? 0 : (covered / total).clamp(0, 1).toDouble();

  /// Le prochain abonnement a tomber : celui qui est entame, ou le suivant.
  PaybackLine? get next {
    for (final line in lines) {
      if (!line.paid) {
        return line;
      }
    }
    return null;
  }
}

/// Les abonnements que le velo rembourse : les actifs, hors exclusions, et
/// qui coutent quelque chose.
List<Subscription> paybackSubscriptions(
  Iterable<Subscription> subscriptions, {
  Set<String> excluded = const {},
}) {
  final kept = [
    for (final subscription in subscriptions)
      if (subscription.isActive &&
          subscription.price > 0 &&
          !excluded.contains(subscription.id))
        subscription,
  ];
  kept.sort((a, b) {
    final byAmount = a
        .amountIn(SubscriptionFrequency.monthly)
        .compareTo(b.amountIn(SubscriptionFrequency.monthly));
    return byAmount != 0 ? byAmount : a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return kept;
}

/// Ce que le velo a rembourse le mois qui contient [month].
///
/// Les abonnements sont ceux d'aujourd'hui, y compris pour un mois passe :
/// l'application ne garde pas l'historique de leurs prix, et un abonnement
/// resilie depuis disparait aussi des mois d'avant.
MonthPayback paybackOf(
  DateTime month, {
  required Iterable<Subscription> subscriptions,
  required CommuteLedger commute,
  Set<String> excluded = const {},
}) {
  final first = DateTime(month.year, month.month);
  final totals = commute.monthTotals(first.year, first.month);
  var left = totals.bike;
  final lines = <PaybackLine>[];
  for (final subscription in paybackSubscriptions(subscriptions, excluded: excluded)) {
    final monthly = roundCents(subscription.amountIn(SubscriptionFrequency.monthly));
    final covered = left >= monthly ? monthly : (left > 0 ? roundCents(left) : 0.0);
    left = roundCents(left - covered);
    lines.add(PaybackLine(subscription: subscription, monthly: monthly, covered: covered));
  }
  return MonthPayback(month: first, saved: totals.bike, bikeDays: totals.bikeDays, lines: lines);
}

/// Les [count] derniers mois, du plus recent au plus ancien, [until] compris.
List<MonthPayback> paybackHistory(
  DateTime until, {
  int count = 6,
  required Iterable<Subscription> subscriptions,
  required CommuteLedger commute,
  Set<String> excluded = const {},
}) =>
    [
      for (var back = 0; back < count; back++)
        paybackOf(
          DateTime(until.year, until.month - back),
          subscriptions: subscriptions,
          commute: commute,
          excluded: excluded,
        ),
    ];
