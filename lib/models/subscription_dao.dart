/// Abonnements : montants, echeances et categories.
///
/// Dart pur — les annotations Hive ne dependent pas de Flutter : les
/// conversions entre semaine, mois et annee sont faciles a rater en silence,
/// elles sont donc testees avec `package:test`, sans widgets.
///
/// Tous les montants sont en euros. Ils ne sont arrondis qu'au moment d'etre
/// affiches : arrondir chaque ligne avant de les additionner ferait deriver le
/// total de quelques centimes.
library;

import 'package:hive/hive.dart';

double roundCents(double value) => (value * 100).roundToDouble() / 100;

/// Jour calendaire, sans heure ni fuseau.
DateTime dateOnly(DateTime moment) => DateTime(moment.year, moment.month, moment.day);

/// Dernier jour du mois contenant [month].
int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

// Lecteurs tolerants : un champ d'un type inattendu est traite comme absent.
// Un simple `as num?` leverait, et une seule valeur abimee empecherait
// l'onglet de s'ouvrir.
double? _asDouble(Object? raw) => raw is num ? raw.toDouble() : null;

String? _asString(Object? raw) => raw is String ? raw : null;

/// Icone de repli, quand aucune n'a ete choisie.
const String kDefaultSubscriptionIcon = 'card';

@HiveType(typeId: 1)
enum SubscriptionFrequency {
  @HiveField(0)
  weekly,
  @HiveField(1)
  monthly,
  @HiveField(2)
  yearly;

  static SubscriptionFrequency fromName(String? raw) =>
      values.firstWhere((frequency) => frequency.name == raw, orElse: () => monthly);

  /// Nombre d'echeances par an.
  ///
  /// 52 semaines et non 52,18 : c'est la convention que la page retenait deja,
  /// et un montant hebdomadaire ramene au mois reste ainsi un chiffre rond a
  /// verifier de tete.
  double get perYear => switch (this) {
        weekly => 52,
        monthly => 12,
        yearly => 1,
      };
}

/// Les couleurs disponibles pour une categorie.
///
/// Un identifiant plutot qu'une valeur : le modele reste hors de Flutter, et
/// la teinte exacte depend du theme clair ou sombre (cf. `subscription_ui`).
enum CategoryColor {
  mint,
  steel,
  apricot,
  sky,
  gold,
  lilac,
  slate;

  static CategoryColor fromName(String? raw) =>
      values.firstWhere((color) => color.name == raw, orElse: () => slate);
}

/// Une categorie d'abonnement.
///
/// Meme partage que les raisons de l'onglet Velo : les categories livrees ont
/// un identifiant stable et un libelle traduit a l'affichage, celles ajoutees
/// a la main portent leur propre libelle.
class SubscriptionCategory {
  const SubscriptionCategory({required this.id, this.label, required this.color});

  /// Stable dans le temps : c'est lui que retient un abonnement.
  final String id;

  /// Nul pour une categorie livree, dont le nom est traduit.
  final String? label;

  final CategoryColor color;

  static const String home = 'home';
  static const String insurance = 'insurance';
  static const String sport = 'sport';
  static const String video = 'video';
  static const String telecom = 'telecom';
  static const String music = 'music';
  static const String software = 'software';

  /// Les categories livrees, dans l'ordre ou elles s'affichent.
  static const List<SubscriptionCategory> builtIn = [
    SubscriptionCategory(id: home, color: CategoryColor.mint),
    SubscriptionCategory(id: insurance, color: CategoryColor.steel),
    SubscriptionCategory(id: sport, color: CategoryColor.apricot),
    SubscriptionCategory(id: video, color: CategoryColor.sky),
    SubscriptionCategory(id: telecom, color: CategoryColor.gold),
    SubscriptionCategory(id: music, color: CategoryColor.lilac),
    SubscriptionCategory(id: software, color: CategoryColor.slate),
  ];

  bool get isBuiltIn => builtIn.any((category) => category.id == id);

  SubscriptionCategory withLabel(String? value) =>
      SubscriptionCategory(id: id, label: value, color: color);

  SubscriptionCategory withColor(CategoryColor value) =>
      SubscriptionCategory(id: id, label: label, color: value);

  factory SubscriptionCategory.fromJson(Map<String, Object?> raw) => SubscriptionCategory(
        id: _asString(raw['id']) ?? '',
        label: _asString(raw['label']),
        color: CategoryColor.fromName(_asString(raw['color'])),
      );

  Map<String, Object?> toJson() => {'id': id, 'label': label, 'color': color.name};
}

/// Un abonnement.
///
/// Les `TypeAdapter` correspondants sont ecrits a la main dans
/// `lib/services/repositories/hive/type_adapters.dart`. Toute modification des
/// champs ci-dessous doit y etre repercutee.
@HiveType(typeId: 0)
class Subscription {
  Subscription({
    this.id,
    this.name = '',
    this.price = 0.0,
    this.isActive = true,
    this.subscriptionType = SubscriptionFrequency.monthly,
    this.categoryId,
    DateTime? nextPayment,
    this.iconId,
  }) : nextPayment = nextPayment == null ? null : dateOnly(nextPayment);

  /// Nul tant que l'abonnement n'a pas ete enregistre une premiere fois ;
  /// `HiveSubscriptionRepository` lui attribue alors un identifiant. Mutable
  /// pour cette raison : un `id` final rendait toute persistance impossible.
  @HiveField(0)
  String? id;

  @HiveField(1)
  String name;

  @HiveField(2)
  double price;

  @HiveField(3)
  bool isActive;

  @HiveField(4)
  SubscriptionFrequency subscriptionType;

  // Le champ 5 portait `iconCode`, le point de code d'une icone choisie a la
  // main. Le numero est brule : ne jamais le reattribuer.

  /// Nul tant qu'aucune categorie n'a ete choisie, et pour tous les
  /// abonnements enregistres avant qu'elles existent.
  @HiveField(6)
  String? categoryId;

  /// Prochaine echeance connue, sans heure. Nulle si la date n'a jamais ete
  /// renseignee : l'abonnement compte alors dans les totaux, mais n'apparait
  /// ni au calendrier ni dans les prelevements a venir.
  @HiveField(7)
  DateTime? nextPayment;

  @HiveField(8)
  String? iconId;

  /// Montant ramene a l'annee, quelle que soit la frequence de facturation.
  double get yearlyAmount => price * subscriptionType.perYear;

  /// Le meme montant vu a la semaine, au mois ou a l'annee.
  double amountIn(SubscriptionFrequency unit) => yearlyAmount / unit.perYear;

  /// Decale l'echeance de [steps] periodes.
  ///
  /// Arithmetique par composants, et non par `Duration` : ajouter sept fois
  /// vingt-quatre heures decale d'une heure au changement d'heure, et le jour
  /// finirait par reculer. Le quantieme est ramene au dernier jour du mois
  /// quand il n'existe pas — le 31 en fevrier, le 29 fevrier hors annee
  /// bissextile.
  DateTime _shift(DateTime anchor, int steps) {
    switch (subscriptionType) {
      case SubscriptionFrequency.weekly:
        return DateTime(anchor.year, anchor.month, anchor.day + 7 * steps);
      case SubscriptionFrequency.monthly:
        // Index absolu du mois, pour que le passage d'une annee a l'autre se
        // fasse sans cas particulier, en arriere comme en avant.
        final index = anchor.year * 12 + anchor.month - 1 + steps;
        final year = index ~/ 12;
        final month = index % 12 + 1;
        return DateTime(year, month, anchor.day.clamp(1, daysInMonth(year, month)));
      case SubscriptionFrequency.yearly:
        final year = anchor.year + steps;
        return DateTime(year, anchor.month, anchor.day.clamp(1, daysInMonth(year, anchor.month)));
    }
  }

  /// Nombre de periodes a sauter pour approcher [target] sans le depasser.
  ///
  /// Evite de derouler une a une cinq annees de prelevements hebdomadaires
  /// quand on ouvre le mois en cours.
  int _stepsTowards(DateTime anchor, DateTime target) {
    switch (subscriptionType) {
      case SubscriptionFrequency.weekly:
        return (target.difference(anchor).inDays / 7).floor() - 1;
      case SubscriptionFrequency.monthly:
        return (target.year - anchor.year) * 12 + target.month - anchor.month - 1;
      case SubscriptionFrequency.yearly:
        return target.year - anchor.year - 1;
    }
  }

  /// Les echeances comprises entre [first] et [last], bornes incluses.
  ///
  /// La serie s'etend aussi avant la date renseignee : un abonnement saisi
  /// aujourd'hui avec sa prochaine echeance est repute avoir deja tourne les
  /// mois precedents, ce qui est le cas courant quand on remplit la liste.
  List<DateTime> occurrencesIn(DateTime first, DateTime last) {
    final anchor = nextPayment;
    if (anchor == null || last.isBefore(first)) {
      return const [];
    }
    final from = dateOnly(first);
    final to = dateOnly(last);
    final dates = <DateTime>[];
    var steps = _stepsTowards(anchor, from);
    // Borne de securite : une periode ne peut pas produire plus d'une echeance
    // par jour, et la boucle s'arrete de toute facon des que `to` est depasse.
    final limit = to.difference(from).inDays + 8;
    for (var seen = 0; seen <= limit; seen++) {
      final date = _shift(anchor, steps + seen);
      if (date.isAfter(to)) {
        break;
      }
      if (!date.isBefore(from)) {
        dates.add(date);
      }
    }
    return dates;
  }

  /// La premiere echeance a partir de [from], incluse. Nulle si l'abonnement
  /// n'a pas de date.
  DateTime? nextPaymentOnOrAfter(DateTime from) {
    final anchor = nextPayment;
    if (anchor == null) {
      return null;
    }
    final target = dateOnly(from);
    var steps = _stepsTowards(anchor, target);
    for (var seen = 0; seen < 400; seen++) {
      final date = _shift(anchor, steps + seen);
      if (!date.isBefore(target)) {
        return date;
      }
    }
    return null;
  }

  factory Subscription.fromJson(String? id, Map<String, Object?> raw) => Subscription(
        id: id,
        name: _asString(raw['name']) ?? '',
        price: _asDouble(raw['price']) ?? 0.0,
        isActive: raw['isActive'] is bool ? raw['isActive'] as bool : true,
        subscriptionType: SubscriptionFrequency.fromName(_asString(raw['subscriptionType'])),
        categoryId: _asString(raw['categoryId']),
        nextPayment: DateTime.tryParse(_asString(raw['nextPayment']) ?? ''),
        iconId: _asString(raw['iconId']),
      );

  Map<String, Object?> toJson() => {
        'name': name,
        'price': price,
        'isActive': isActive,
        'subscriptionType': subscriptionType.name,
        'categoryId': categoryId,
        'nextPayment': nextPayment?.toIso8601String(),
        'iconId': iconId,
      };
}

/// Une echeance : l'abonnement, le jour, et le montant reellement preleve.
typedef Payment = ({Subscription subscription, DateTime date, double amount});

/// Ce que pese une categorie sur le total.
class CategoryTotal {
  const CategoryTotal({
    required this.categoryId,
    required this.amount,
    required this.count,
    required this.share,
  });

  /// Nul pour les abonnements sans categorie.
  final String? categoryId;
  final double amount;
  final int count;

  /// Part du total, entre 0 et 1.
  final double share;
}

/// La liste des abonnements, et tout ce qui s'en deduit.
///
/// Rien n'est stocke : les totaux se recalculent a chaque lecture, ce qui evite
/// qu'un compteur enregistre ne diverge de la liste apres une suppression.
class SubscriptionLedger {
  SubscriptionLedger(List<Subscription> all)
      : active = _byCostDescending(all.where((subscription) => subscription.isActive)),
        suspended = _byCostDescending(all.where((subscription) => !subscription.isActive));

  final List<Subscription> active;
  final List<Subscription> suspended;

  static List<Subscription> _byCostDescending(Iterable<Subscription> items) {
    final sorted = items.toList()
      ..sort((a, b) => b.yearlyAmount.compareTo(a.yearlyAmount));
    return List.unmodifiable(sorted);
  }

  /// Total des abonnements actifs, dans l'unite demandee.
  double totalIn(SubscriptionFrequency unit) => _sum(active, unit);

  /// Ce que couterait la reprise des abonnements suspendus.
  double suspendedTotalIn(SubscriptionFrequency unit) => _sum(suspended, unit);

  static double _sum(Iterable<Subscription> items, SubscriptionFrequency unit) =>
      items.fold(0.0, (total, subscription) => total + subscription.amountIn(unit));

  /// Le poids de chaque categorie, de la plus lourde a la plus legere.
  ///
  /// Les abonnements sans categorie sont regroupes sous `categoryId` nul.
  List<CategoryTotal> byCategory(SubscriptionFrequency unit) {
    final amounts = <String?, double>{};
    final counts = <String?, int>{};
    for (final subscription in active) {
      final key = subscription.categoryId;
      amounts[key] = (amounts[key] ?? 0) + subscription.amountIn(unit);
      counts[key] = (counts[key] ?? 0) + 1;
    }
    final total = totalIn(unit);
    final totals = [
      for (final entry in amounts.entries)
        CategoryTotal(
          categoryId: entry.key,
          amount: entry.value,
          count: counts[entry.key] ?? 0,
          share: total <= 0 ? 0 : entry.value / total,
        ),
    ]..sort((a, b) => b.amount.compareTo(a.amount));
    return List.unmodifiable(totals);
  }

  /// Les echeances des abonnements actifs entre [first] et [last], bornes
  /// incluses, du plus ancien au plus recent.
  List<Payment> paymentsIn(DateTime first, DateTime last) {
    final payments = <Payment>[
      for (final subscription in active)
        for (final date in subscription.occurrencesIn(first, last))
          (subscription: subscription, date: date, amount: subscription.price),
    ]..sort((a, b) {
        final byDate = a.date.compareTo(b.date);
        return byDate != 0 ? byDate : a.subscription.name.compareTo(b.subscription.name);
      });
    return List.unmodifiable(payments);
  }

  static double totalOf(Iterable<Payment> payments) =>
      payments.fold(0.0, (total, payment) => total + payment.amount);
}
