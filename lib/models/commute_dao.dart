/// Trajets domicile-travail, cagnotte et objectifs.
///
/// Dart pur, sans import Flutter : les calculs d'argent sont les plus faciles a
/// rater en silence, ils sont donc testes avec `package:test`, sans widgets.
///
/// Tous les montants sont en euros, arrondis au centime au moment ou ils sont
/// figes : additionner des centaines de doubles bruts finirait par afficher
/// 37,019999 dans la cagnotte.
library;

import 'package:i_zerak_app/models/gas_station_dao.dart';

/// Prix retenu quand aucune station n'a jamais repondu pour ce carburant.
///
/// Volontairement rond et un peu haut : il ne sert qu'a ne pas bloquer
/// l'enregistrement, et un prix sous-estime minorerait la cagnotte sans que
/// rien ne le signale.
const double kFallbackFuelPrice = 2.0;

double roundCents(double value) => (value * 100).roundToDouble() / 100;

// Lecteurs tolerants : un champ d'un type inattendu est traite comme absent.
// Un simple `as num?` leverait, et une seule valeur abimee empecherait
// l'onglet de s'ouvrir.
double? _asDouble(Object? raw) => raw is num ? raw.toDouble() : null;

String? _asString(Object? raw) => raw is String ? raw : null;

/// Jour calendaire, sans heure ni fuseau.
DateTime dateOnly(DateTime moment) => DateTime(moment.year, moment.month, moment.day);

/// Cle de persistance d'un jour, « aaaa-mm-jj ».
///
/// Triable telle quelle, et lisible dans un vidage de la boite.
String dayKey(DateTime day) => '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

DateTime? parseDayKey(String raw) {
  final parts = raw.split('-');
  if (parts.length != 3) {
    return null;
  }
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) {
    return null;
  }
  return DateTime(year, month, day);
}

enum CommuteMode {
  bike,
  car,

  /// Teletravail : pas de trajet, donc rien a gagner ni a depenser. Le jour
  /// est quand meme saisi, pour ne pas passer pour un oubli.
  remote;

  static CommuteMode fromName(String? raw) =>
      values.firstWhere((mode) => mode.name == raw, orElse: () => bike);
}

/// La cagnotte qu'alimente un trajet en voiture.
enum CarBucket {
  /// La voiture etait necessaire : sport le soir, courses.
  essential,

  /// Le velo etait possible : la flemme.
  missed;

  static CarBucket fromName(String? raw) =>
      values.firstWhere((bucket) => bucket.name == raw, orElse: () => essential);
}

/// D'ou vient le prix du litre retenu pour un trajet.
enum PriceSource {
  /// Le plus bas parmi les stations suivies, lu a l'instant.
  live,

  /// Stations injoignables, ou aucune ne vend ce carburant : le dernier prix
  /// releve.
  lastKnown,

  /// Aucun prix n'a jamais ete releve : `kFallbackFuelPrice`.
  fallback;

  static PriceSource fromName(String? raw) =>
      values.firstWhere((source) => source.name == raw, orElse: () => fallback);
}

/// Un prix du litre, et ce qui permet de dire d'ou il vient.
class ResolvedPrice {
  const ResolvedPrice({
    required this.pricePerLitre,
    required this.source,
    this.stationLabel,
    this.observedOn,
  });

  const ResolvedPrice.fallback()
      : pricePerLitre = kFallbackFuelPrice,
        source = PriceSource.fallback,
        stationLabel = null,
        observedOn = null;

  final double pricePerLitre;
  final PriceSource source;

  /// La station la moins chere, quand le prix vient d'une station.
  final String? stationLabel;

  /// Le jour ou ce prix a ete releve. Nul pour le prix par defaut.
  final DateTime? observedOn;
}

/// Une raison de prendre la voiture, et la cagnotte qu'elle alimente.
class CarReason {
  const CarReason({required this.id, this.label, required this.bucket});

  /// Stable dans le temps : c'est lui que retient un jour enregistre.
  final String id;

  /// Nul pour une raison livree avec l'application et jamais renommee, dont le
  /// libelle passe alors par la localisation ; rempli sinon.
  final String? label;

  final CarBucket bucket;

  /// L'une des trois raisons livrees, renommee ou non.
  bool get isBuiltIn => id == sport || id == shopping || id == lazy;

  static const String sport = 'sport';
  static const String shopping = 'shopping';
  static const String lazy = 'lazy';

  static const List<CarReason> defaults = [
    CarReason(id: sport, bucket: CarBucket.essential),
    CarReason(id: shopping, bucket: CarBucket.essential),
    CarReason(id: lazy, bucket: CarBucket.missed),
  ];

  CarReason withBucket(CarBucket bucket) => CarReason(id: id, label: label, bucket: bucket);

  /// `null` rend a une raison livree son libelle localise d'origine.
  CarReason withLabel(String? label) => CarReason(id: id, label: label, bucket: bucket);

  Map<String, dynamic> toJson() => {
        'id': id,
        if (label != null) 'label': label,
        'bucket': bucket.name,
      };

  static CarReason? fromJson(Object? raw) {
    if (raw is! Map || raw['id'] is! String) {
      return null;
    }
    return CarReason(
      id: raw['id'] as String,
      label: _asString(raw['label']),
      bucket: CarBucket.fromName(_asString(raw['bucket'])),
    );
  }
}

/// Nombre de journees enregistrees par raison.
///
/// Une raison utilisee ne se supprime pas : les journees qui la citent
/// n'auraient plus de libelle a jour, et l'historique afficherait un
/// identifiant.
Map<String, int> reasonUses(Iterable<CommuteDay> days) {
  final uses = <String, int>{};
  for (final day in days) {
    if (day.reasonId case final String id) {
      uses[id] = (uses[id] ?? 0) + 1;
    }
  }
  return uses;
}

/// Le trajet domicile-travail, tel que l'utilisateur l'a decrit.
class CommuteSettings {
  const CommuteSettings({
    this.distanceKm,
    this.consumption = 5.2,
    this.fuel = FuelType.gazole,
    this.reasons = CarReason.defaults,
    this.paybackExcluded = const {},
  });

  /// Aller et retour compris. Nulle tant qu'elle n'a pas ete renseignee :
  /// une distance par defaut remplirait la cagnotte de montants inventes.
  final double? distanceKm;

  /// En litres aux cent kilometres.
  final double consumption;

  final FuelType fuel;

  final List<CarReason> reasons;

  /// Les abonnements que le velo ne rembourse pas : le loyer, une assurance —
  /// ce qu'on ne paie pas « en plus », et qu'aucun trajet ne couvrirait.
  final Set<String> paybackExcluded;

  bool get isConfigured => (distanceKm ?? 0) > 0;

  /// Ce que coute un aller-retour en voiture, au prix donne.
  double tripValue(double pricePerLitre) =>
      roundCents((distanceKm ?? 0) * consumption / 100 * pricePerLitre);

  CarReason? reasonById(String id) {
    for (final reason in reasons) {
      if (reason.id == id) {
        return reason;
      }
    }
    return null;
  }

  CommuteSettings copyWith({
    double? distanceKm,
    double? consumption,
    FuelType? fuel,
    List<CarReason>? reasons,
    Set<String>? paybackExcluded,
  }) =>
      CommuteSettings(
        distanceKm: distanceKm ?? this.distanceKm,
        consumption: consumption ?? this.consumption,
        fuel: fuel ?? this.fuel,
        reasons: reasons ?? this.reasons,
        paybackExcluded: paybackExcluded ?? this.paybackExcluded,
      );

  Map<String, dynamic> toJson() => {
        if (distanceKm != null) 'distance_km': distanceKm,
        'consumption': consumption,
        'fuel': fuel.name,
        'reasons': [for (final reason in reasons) reason.toJson()],
        if (paybackExcluded.isNotEmpty) 'payback_excluded': [...paybackExcluded]..sort(),
      };

  /// Relecture tolerante : un champ manquant ou d'un type inattendu reprend sa
  /// valeur par defaut plutot que d'empecher l'onglet de s'ouvrir.
  factory CommuteSettings.fromJson(Object? raw) {
    if (raw is! Map) {
      return const CommuteSettings();
    }
    final reasons = [
      if (raw['reasons'] case final List<dynamic> list)
        for (final item in list)
          if (CarReason.fromJson(item) case final CarReason reason) reason,
    ];
    return CommuteSettings(
      distanceKm: _asDouble(raw['distance_km']),
      consumption: _asDouble(raw['consumption']) ?? 5.2,
      fuel: FuelType.fromName(_asString(raw['fuel'])),
      reasons: raw['reasons'] is List ? reasons : CarReason.defaults,
      paybackExcluded: {
        if (raw['payback_excluded'] case final List<dynamic> list)
          for (final id in list)
            if (id is String) id,
      },
    );
  }
}

/// Une journee enregistree : a velo, ou en voiture pour une raison donnee.
///
/// Tout ce qui sert au calcul est fige a l'enregistrement — prix, montant,
/// cagnotte. Changer de voiture, de distance ou reclasser une raison ne doit
/// pas reecrire des economies deja acquises.
class CommuteDay {
  const CommuteDay({
    required this.date,
    required this.mode,
    required this.amount,
    required this.pricePerLitre,
    required this.priceSource,
    this.stationLabel,
    this.reasonId,
    this.reasonLabel,
    this.bucket,
    this.imported = false,
  });

  factory CommuteDay.bike(
    DateTime date,
    CommuteSettings settings,
    ResolvedPrice price, {
    bool imported = false,
  }) =>
      CommuteDay(
        date: dateOnly(date),
        mode: CommuteMode.bike,
        amount: settings.tripValue(price.pricePerLitre),
        pricePerLitre: price.pricePerLitre,
        priceSource: price.source,
        stationLabel: price.stationLabel,
        imported: imported,
      );

  /// En voiture. La cagnotte alimentee repond a une seule question : le velo
  /// etait-il possible ? Oui, c'est une economie loupee ; non, une depense
  /// obligatoire.
  factory CommuteDay.car(
    DateTime date,
    CommuteSettings settings,
    ResolvedPrice price,
    CarBucket bucket,
  ) =>
      CommuteDay(
        date: dateOnly(date),
        mode: CommuteMode.car,
        amount: settings.tripValue(price.pricePerLitre),
        pricePerLitre: price.pricePerLitre,
        priceSource: price.source,
        stationLabel: price.stationLabel,
        bucket: bucket,
      );

  /// En teletravail : aucun trajet, aucun montant.
  factory CommuteDay.remote(DateTime date) => CommuteDay(
        date: dateOnly(date),
        mode: CommuteMode.remote,
        amount: 0,
        pricePerLitre: 0,
        priceSource: PriceSource.fallback,
      );

  final DateTime date;
  final CommuteMode mode;

  /// Valeur du trajet, en euros. Pour un jour a velo, c'est ce qui entre dans
  /// la cagnotte.
  final double amount;

  final double pricePerLitre;
  final PriceSource priceSource;
  final String? stationLabel;

  /// Voiture uniquement, et seulement pour les journees saisies du temps ou
  /// l'on choisissait une raison detaillee. Garde pour ne rien perdre.
  final String? reasonId;

  /// Copie du libelle d'une raison ajoutee a la main, pour les memes journees.
  final String? reasonLabel;

  /// Voiture uniquement : la cagnotte alimentee, figee au jour du trajet.
  final CarBucket? bucket;

  /// Repris d'un export Google Maps : le prix est celui du jour de l'import,
  /// pas celui du jour du trajet, que l'API ne publie plus.
  final bool imported;

  bool get isBike => mode == CommuteMode.bike;

  bool get isCar => mode == CommuteMode.car;

  bool get isRemote => mode == CommuteMode.remote;

  Map<String, dynamic> toJson() => {
        'date': dayKey(date),
        'mode': mode.name,
        'amount': amount,
        'price': pricePerLitre,
        'source': priceSource.name,
        if (stationLabel != null) 'station': stationLabel,
        if (reasonId != null) 'reason': reasonId,
        if (reasonLabel != null) 'reason_label': reasonLabel,
        if (bucket != null) 'bucket': bucket!.name,
        if (imported) 'imported': true,
      };

  static CommuteDay? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final date = parseDayKey('${raw['date']}');
    final amount = raw['amount'];
    if (date == null || amount is! num) {
      return null;
    }
    final mode = CommuteMode.fromName(_asString(raw['mode']));
    return CommuteDay(
      date: date,
      mode: mode,
      amount: amount.toDouble(),
      pricePerLitre: _asDouble(raw['price']) ?? 0,
      priceSource: PriceSource.fromName(_asString(raw['source'])),
      stationLabel: _asString(raw['station']),
      reasonId: _asString(raw['reason']),
      reasonLabel: _asString(raw['reason_label']),
      bucket: mode == CommuteMode.car ? CarBucket.fromName(_asString(raw['bucket'])) : null,
      imported: raw['imported'] == true,
    );
  }
}

enum GoalKind {
  /// Un achat finance par la cagnotte. Il n'en est plus cree : la cagnotte a
  /// laisse la place aux abonnements rembourses (cf. `payback_dao.dart`). Ceux
  /// qui existaient se lisent desormais comme des paliers, et ceux deja
  /// valides restent dans l'historique.
  purchase,

  /// Un palier : un gros achat que l'argent economise finit par rentabiliser.
  /// Il se mesure sur le total economise depuis [Goal.since], et se valide
  /// sans rien depenser. « Rentabiliser le velo » en est un.
  milestone;

  static GoalKind fromName(String? raw) =>
      values.firstWhere((kind) => kind.name == raw, orElse: () => purchase);
}

/// Icones proposees a la creation d'un objectif.
///
/// Le nom est la cle de persistance, comme pour `FuelType`.
enum GoalIcon {
  bike,
  helmet,
  bag,
  gift,
  star,
  phone,
  laptop,
  fitness;

  static GoalIcon fromName(String? raw) =>
      values.firstWhere((icon) => icon.name == raw, orElse: () => star);
}

class Goal {
  const Goal({
    required this.id,
    required this.name,
    required this.target,
    required this.kind,
    required this.icon,
    required this.createdAt,
    this.since,
    this.validatedAt,
  });

  final String id;
  final String name;
  final double target;
  final GoalKind kind;
  final GoalIcon icon;
  final DateTime createdAt;

  /// Premier jour dont l'economie compte. Nul : depuis le premier trajet.
  ///
  /// Un telephone achete en novembre ne se rentabilise pas avec l'essence
  /// economisee en mars ; le velo, lui, si — il etait deja la.
  final DateTime? since;

  /// Renseigne une fois l'objectif valide. Valider ne depense rien : c'est
  /// constater qu'il est rentabilise.
  final DateTime? validatedAt;

  bool get isValidated => validatedAt != null;

  Goal validated(DateTime at) => Goal(
        id: id,
        name: name,
        target: target,
        kind: kind,
        icon: icon,
        createdAt: createdAt,
        since: since,
        validatedAt: at,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'target': target,
        'kind': kind.name,
        'icon': icon.name,
        'created': createdAt.toIso8601String(),
        if (since != null) 'since': dayKey(since!),
        if (validatedAt != null) 'validated': validatedAt!.toIso8601String(),
      };

  static Goal? fromJson(Object? raw) {
    if (raw is! Map || raw['id'] is! String || raw['target'] is! num) {
      return null;
    }
    return Goal(
      id: raw['id'] as String,
      name: _asString(raw['name']) ?? '',
      target: (raw['target'] as num).toDouble(),
      kind: GoalKind.fromName(_asString(raw['kind'])),
      icon: GoalIcon.fromName(_asString(raw['icon'])),
      createdAt: DateTime.tryParse('${raw['created']}') ?? DateTime(2000),
      since: parseDayKey('${raw['since']}'),
      validatedAt: DateTime.tryParse('${raw['validated']}'),
    );
  }
}

/// Ou en est un objectif.
class GoalProgress {
  const GoalProgress(this.goal, this.current);

  final Goal goal;

  /// Ce qui a ete economise depuis [Goal.since].
  final double current;

  bool get reached => current + 0.005 >= goal.target;

  double get ratio => goal.target <= 0 ? 1 : (current / goal.target).clamp(0, 1).toDouble();

  double get remaining => reached ? 0 : roundCents(goal.target - current);
}

/// Totaux d'une periode, par nature de journee.
class CommuteTotals {
  const CommuteTotals({
    required this.bike,
    required this.bikeDays,
    required this.essential,
    required this.essentialDays,
    required this.missed,
    required this.missedDays,
    this.remoteDays = 0,
  });

  factory CommuteTotals.of(Iterable<CommuteDay> days) {
    var bike = 0.0, essential = 0.0, missed = 0.0;
    var bikeDays = 0, essentialDays = 0, missedDays = 0, remoteDays = 0;
    for (final day in days) {
      if (day.isRemote) {
        remoteDays++;
      } else if (day.isBike) {
        bike += day.amount;
        bikeDays++;
      } else if (day.bucket == CarBucket.missed) {
        missed += day.amount;
        missedDays++;
      } else {
        essential += day.amount;
        essentialDays++;
      }
    }
    return CommuteTotals(
      bike: roundCents(bike),
      bikeDays: bikeDays,
      essential: roundCents(essential),
      essentialDays: essentialDays,
      missed: roundCents(missed),
      missedDays: missedDays,
      remoteDays: remoteDays,
    );
  }

  final double bike;
  final int bikeDays;
  final double essential;
  final int essentialDays;
  final double missed;
  final int missedDays;

  /// Journees en teletravail : comptees, mais sans montant.
  final int remoteDays;
}

/// Une somme economisee un jour donne.
typedef Saving = ({DateTime date, double amount});

/// Des paliers, et l'argent economise qui les rentabilise.
///
/// Plus de cagnotte ou l'on puise : valider un objectif ne retire rien. Le
/// meme argent economise peut donc rentabiliser le velo et rembourser les
/// abonnements du mois — ce sont deux facons de le regarder, pas deux
/// depenses.
class GoalBook {
  GoalBook(Iterable<Goal> goals, {required Iterable<Saving> savings})
      : goals = [...goals]..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
        _savings = [...savings],
        totalSaved = roundCents(savings.fold(0.0, (sum, saving) => sum + saving.amount));

  /// Du plus ancien au plus recent : l'ordre dans lequel ils ont ete crees.
  final List<Goal> goals;

  final List<Saving> _savings;

  /// Tout ce qui a ete economise depuis le debut. Ne baisse jamais.
  final double totalSaved;

  /// Ce qui a ete economise depuis [from] inclus, ou depuis le debut.
  double savedSince(DateTime? from) {
    if (from == null) {
      return totalSaved;
    }
    final start = dateOnly(from);
    return roundCents(_savings
        .where((saving) => !saving.date.isBefore(start))
        .fold(0.0, (sum, saving) => sum + saving.amount));
  }

  List<Goal> get activeGoals => [for (final goal in goals) if (!goal.isValidated) goal];

  List<Goal> get validatedGoals =>
      [for (final goal in goals) if (goal.isValidated) goal]
        ..sort((a, b) => b.validatedAt!.compareTo(a.validatedAt!));

  GoalProgress progressOf(Goal goal) => GoalProgress(goal, savedSince(goal.since));
}

/// Tout ce que l'onglet affiche, calcule a partir des jours et des objectifs.
///
/// Rien de ce qui est ici n'est stocke : la cagnotte se recalcule a chaque
/// fois, elle ne peut donc pas diverger des jours qui la composent.
class CommuteLedger {
  factory CommuteLedger(Iterable<CommuteDay> days, Iterable<Goal> goals) {
    final totals = CommuteTotals.of(days);
    return CommuteLedger._(
      [...days]..sort((a, b) => b.date.compareTo(a.date)),
      totals,
      GoalBook(goals, savings: [
        for (final day in days)
          if (day.isBike) (date: day.date, amount: day.amount),
      ]),
    );
  }

  CommuteLedger._(this.days, this.totals, this.book);

  /// Du plus recent au plus ancien.
  final List<CommuteDay> days;

  final CommuteTotals totals;

  final GoalBook book;

  /// Du plus ancien au plus recent : l'ordre dans lequel ils ont ete crees.
  List<Goal> get goals => book.goals;

  /// Tout ce que le velo a rapporte depuis le premier trajet. Ne baisse jamais.
  double get totalSaved => totals.bike;

  DateTime? get firstBikeDay {
    DateTime? first;
    for (final day in days) {
      if (day.isBike) {
        first = day.date;
      }
    }
    return first;
  }

  CommuteDay? dayOn(DateTime date) {
    final wanted = dateOnly(date);
    for (final day in days) {
      if (day.date == wanted) {
        return day;
      }
    }
    return null;
  }

  List<Goal> get activeGoals => book.activeGoals;

  List<Goal> get validatedGoals => book.validatedGoals;

  GoalProgress progressOf(Goal goal) => book.progressOf(goal);

  CommuteTotals monthTotals(int year, int month) => CommuteTotals.of(
      days.where((day) => day.date.year == year && day.date.month == month));
}
