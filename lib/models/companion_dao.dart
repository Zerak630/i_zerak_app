/// Ce qui mesure l'habitude : le rythme d'epargne, la regularite, et la cible
/// du mois.
///
/// Dart pur, comme `commute_dao` dont tout ici derive. Rien n'est stocke sauf
/// la cible d'un defi : series, moyennes et dates projetees se recalculent a
/// partir des journees deja enregistrees, et ne peuvent donc pas diverger
/// d'elles.
library;

import 'package:i_zerak_app/models/commute_dao.dart';

/// Duree moyenne d'un mois, en jours : 365,25 / 12.
///
/// Les projections se comptent en mois, et un mois « de 30 jours » decalerait
/// une echeance lointaine de plusieurs semaines.
const double kAverageMonthDays = 30.4375;

/// Cle de persistance d'un mois, « aaaa-mm ». Triable telle quelle.
String monthKey(DateTime month) =>
    '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}';

DateTime? parseMonthKey(String raw) {
  final parts = raw.split('-');
  if (parts.length != 2) {
    return null;
  }
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  if (year == null || month == null || month < 1 || month > 12) {
    return null;
  }
  return DateTime(year, month);
}

/// Un jour ou l'on va au travail : du lundi au vendredi.
///
/// Les jours feries n'en sortent pas. L'application ne connait pas le
/// calendrier francais, et un defi rate parce que le 15 aout tombait un mardi
/// se corrige a la main en baissant la cible.
bool isWorkday(DateTime day) => day.weekday <= DateTime.friday;

/// Le nombre de jours du mois qui contient [month].
///
/// Le meme calcul que le `daysInMonth` du modele des abonnements, refait ici :
/// c'est un fait de calendrier, et aller le chercher la-bas lierait l'habitude
/// au domaine des prelevements.
int daysOfMonth(DateTime month) => DateTime(month.year, month.month + 1, 0).day;

/// Les jours ouvres du mois qui contient [month].
int workdaysIn(DateTime month) {
  var count = 0;
  final total = daysOfMonth(month);
  for (var day = 1; day <= total; day++) {
    if (isWorkday(DateTime(month.year, month.month, day))) {
      count++;
    }
  }
  return count;
}

/// Le lundi de la semaine qui contient [day].
DateTime mondayOf(DateTime day) =>
    dateOnly(day).subtract(Duration(days: day.weekday - DateTime.monday));

/// Les jours ouvres strictement entre [from] et [to], ces deux-la exclus.
int workdaysBetween(DateTime from, DateTime to) {
  var count = 0;
  var day = dateOnly(from).add(const Duration(days: 1));
  final last = dateOnly(to);
  while (day.isBefore(last)) {
    if (isWorkday(day)) {
      count++;
    }
    day = day.add(const Duration(days: 1));
  }
  return count;
}

/// Les [count] derniers jours ouvres, du plus ancien au plus recent, [today]
/// compris s'il en est un.
///
/// Seuls les jours de travail sont saisis : un samedi ou un dimanche ne
/// serait jamais qu'une case vide.
List<DateTime> lastWorkdays(DateTime today, int count) {
  final days = <DateTime>[];
  var day = dateOnly(today);
  while (days.length < count) {
    if (isWorkday(day)) {
      days.add(day);
    }
    day = DateTime(day.year, day.month, day.day - 1);
  }
  return days.reversed.toList();
}

/// Fenetre sur laquelle le rythme se mesure.
enum RateWindow {
  /// Les huit dernieres semaines : ce que vaut l'habitude actuelle, conges
  /// compris.
  recent,

  /// Tout l'historique : plus stable, mais insensible a un changement recent.
  all;

  static const Duration recentSpan = Duration(days: 56);
}

/// A quelle vitesse la cagnotte se remplit.
///
/// C'est le seul chiffre dont dependent toutes les dates projetees : il est
/// donc mesure sur une fenetre explicite, et affiche avec elle.
class SavingRate {
  const SavingRate({
    required this.window,
    required this.from,
    required this.to,
    required this.saved,
    required this.bikeDays,
  });

  /// Le rythme des journees donnees, vu de [now].
  ///
  /// Pour la fenetre courte, le debut est ramene au premier jour enregistre
  /// quand l'historique est plus jeune que huit semaines : sans cela, une
  /// premiere semaine de velo serait divisee par huit et donnerait un rythme
  /// faux de bout en bout.
  factory SavingRate.of(
    Iterable<CommuteDay> days, {
    required DateTime now,
    required RateWindow window,
  }) {
    final today = dateOnly(now);
    DateTime? first;
    for (final day in days) {
      if (first == null || day.date.isBefore(first)) {
        first = day.date;
      }
    }
    if (first == null) {
      return SavingRate(window: window, from: today, to: today, saved: 0, bikeDays: 0);
    }
    final start = switch (window) {
      RateWindow.all => first,
      RateWindow.recent => () {
          final edge = today.subtract(RateWindow.recentSpan);
          return edge.isBefore(first!) ? first : edge;
        }(),
    };
    var saved = 0.0;
    var bikeDays = 0;
    for (final day in days) {
      if (!day.isBike || day.date.isBefore(start) || day.date.isAfter(today)) {
        continue;
      }
      saved += day.amount;
      bikeDays++;
    }
    return SavingRate(
      window: window,
      from: start,
      to: today,
      saved: roundCents(saved),
      bikeDays: bikeDays,
    );
  }

  final RateWindow window;

  /// Premier et dernier jour de la fenetre, celui-ci compris.
  final DateTime from;
  final DateTime to;

  /// Ce que le velo a rapporte sur la fenetre.
  final double saved;
  final int bikeDays;

  int get spanDays => to.difference(from).inDays + 1;

  double get perMonth => spanDays <= 0 ? 0 : roundCents(saved / spanDays * kAverageMonthDays);

  double get bikeDaysPerWeek => spanDays <= 0 ? 0 : bikeDays / spanDays * 7;

  /// Deux semaines au moins, et de l'argent dedans.
  ///
  /// Projeter une date sur trois jours de releves donnerait un chiffre que
  /// rien ne soutient : mieux vaut ne rien annoncer.
  bool get isMeasurable => spanDays >= 14 && perMonth > 0;

  /// Quand [amount] sera atteint, en partant de [from]. Nulle si le rythme ne
  /// se mesure pas, ou si le montant est deja la.
  DateTime? dateFor(double amount, {required DateTime from}) {
    if (!isMeasurable || amount <= 0) {
      return null;
    }
    final days = (amount / perMonth * kAverageMonthDays).ceil();
    return dateOnly(from).add(Duration(days: days));
  }
}

/// La plus longue suite de journees a velo, et celle en cours.
///
/// Un jour sans rien d'enregistre n'interrompt pas la suite : il n'a pas ete
/// saisi, ce n'est pas la meme chose que d'avoir pris la voiture. Un week-end,
/// un jour de conge ou un oubli ne cassent donc pas une serie.
///
/// Un jour de teletravail non plus : il n'y avait pas de trajet a faire. Il
/// ne compte pas dans la suite, mais comble le trou qu'il laisserait.
///
/// Mais un trou, si. Sans ce garde-fou, trente trajets etales sur six mois sans
/// une seule journee en voiture donnaient « 30 jours d'affilee », ce que
/// personne ne lit comme autre chose que trente jours de suite.
class StreakInfo {
  const StreakInfo({required this.current, required this.record, this.recordEnd});

  /// Combien de jours ouvres vides peuvent separer deux trajets sans rompre la
  /// suite.
  ///
  /// Un seul : de quoi absorber un oubli de saisie, pas de quoi relier deux
  /// trajets hebdomadaires. Le week-end, lui, ne compte jamais.
  static const int maxMissedWorkdays = 1;

  /// [now] clot une serie que le silence a rattrapee : sans lui, un dernier
  /// trajet vieux de trois semaines serait encore annonce « en cours ».
  factory StreakInfo.of(Iterable<CommuteDay> days, {DateTime? now}) {
    final sorted = [...days]..sort((a, b) => a.date.compareTo(b.date));
    var run = 0;
    var record = 0;
    DateTime? recordEnd;
    DateTime? previous;
    for (final day in sorted) {
      if (day.isRemote) {
        if (previous != null) {
          previous = day.date;
        }
      } else if (day.isBike) {
        final missed = previous == null ? 0 : workdaysBetween(previous, day.date);
        run = missed > maxMissedWorkdays ? 1 : run + 1;
        previous = day.date;
        if (run > record) {
          record = run;
          recordEnd = day.date;
        }
      } else {
        run = 0;
        previous = null;
      }
    }
    if (now != null &&
        previous != null &&
        workdaysBetween(previous, dateOnly(now)) > maxMissedWorkdays) {
      run = 0;
    }
    return StreakInfo(current: run, record: record, recordEnd: recordEnd);
  }

  /// La suite qui court encore : zero des que la derniere journee saisie est
  /// une journee en voiture.
  final int current;

  final int record;

  /// Dernier jour de la plus longue suite, pour pouvoir dire en quel mois.
  final DateTime? recordEnd;

  bool get holdsRecord => current > 0 && current >= record;

  /// Combien de journees il faut encore pour depasser le record.
  int get toBeatRecord => holdsRecord ? 0 : record - current + 1;
}

/// Ce qu'un jour de la semaine donne, sur tout l'historique.
class WeekdayStat {
  const WeekdayStat({
    required this.weekday,
    required this.bike,
    required this.essential,
    required this.missed,
  });

  /// `DateTime.monday` a `DateTime.sunday`.
  final int weekday;

  final int bike;
  final int essential;
  final int missed;

  int get carDays => essential + missed;

  int get recorded => bike + carDays;

  double get ratio => recorded == 0 ? 0 : bike / recorded;

  bool get flawless => recorded > 0 && carDays == 0;
}

/// Un mois et ce qu'il a donne.
class MonthTally {
  const MonthTally({required this.month, required this.bike, required this.recorded});

  final DateTime month;
  final int bike;
  final int recorded;
}

/// Une semaine de la grille : son lundi, et ses cinq jours ouvres.
typedef RegularityWeek = ({DateTime monday, List<CommuteDay?> days});

/// Tout ce que l'ecran Regularite affiche.
class Regularity {
  Regularity(Iterable<CommuteDay> days, {DateTime? now})
      : _byDay = {for (final day in days) dayKey(day.date): day},
        streak = StreakInfo.of(days, now: now) {
    for (final day in _byDay.values) {
      if (_first == null || day.date.isBefore(_first!)) {
        _first = day.date;
      }
    }
  }

  final Map<String, CommuteDay> _byDay;

  final StreakInfo streak;

  DateTime? _first;

  /// Premiere journee enregistree, toutes natures confondues.
  DateTime? get firstDay => _first;

  int get recordedDays => _byDay.length;

  int get bikeDays => _byDay.values.where((day) => day.isBike).length;

  CommuteDay? dayOn(DateTime date) => _byDay[dayKey(date)];

  /// Du lundi au vendredi, dans cet ordre. Les jours jamais enregistres — un
  /// samedi, le plus souvent — n'y figurent pas.
  List<WeekdayStat> get weekdays {
    final stats = <int, ({int bike, int essential, int missed})>{};
    for (final day in _byDay.values) {
      // Le teletravail ne dit rien du choix entre velo et voiture.
      if (day.isRemote) {
        continue;
      }
      final current = stats[day.date.weekday] ?? (bike: 0, essential: 0, missed: 0);
      stats[day.date.weekday] = (
        bike: current.bike + (day.isBike ? 1 : 0),
        essential: current.essential + (!day.isBike && day.bucket != CarBucket.missed ? 1 : 0),
        missed: current.missed + (!day.isBike && day.bucket == CarBucket.missed ? 1 : 0),
      );
    }
    return [
      for (var weekday = DateTime.monday; weekday <= DateTime.sunday; weekday++)
        if (stats[weekday] case final tally?)
          WeekdayStat(
            weekday: weekday,
            bike: tally.bike,
            essential: tally.essential,
            missed: tally.missed,
          ),
    ];
  }

  /// Le jour de la semaine ou la voiture gagne le plus souvent.
  ///
  /// Trois journees au moins, et moins de trois quarts a velo : en dessous,
  /// l'ecart tient au hasard et le nommer serait un reproche gratuit.
  WeekdayStat? get weakestWeekday {
    WeekdayStat? weakest;
    for (final stat in weekdays) {
      if (stat.recorded < 3 || stat.ratio >= 0.75) {
        continue;
      }
      if (weakest == null || stat.ratio < weakest.ratio) {
        weakest = stat;
      }
    }
    return weakest;
  }

  /// Le jour de la semaine sans une seule journee en voiture, le mieux fourni
  /// quand plusieurs se valent.
  WeekdayStat? get flawlessWeekday {
    WeekdayStat? best;
    for (final stat in weekdays) {
      if (!stat.flawless || stat.recorded < 3) {
        continue;
      }
      if (best == null || stat.recorded > best.recorded) {
        best = stat;
      }
    }
    return best;
  }

  /// Du plus ancien au plus recent.
  List<MonthTally> get months {
    final tallies = <String, ({DateTime month, int bike, int recorded})>{};
    for (final day in _byDay.values) {
      if (day.isRemote) {
        continue;
      }
      final month = DateTime(day.date.year, day.date.month);
      final key = monthKey(month);
      final current = tallies[key] ?? (month: month, bike: 0, recorded: 0);
      tallies[key] = (
        month: month,
        bike: current.bike + (day.isBike ? 1 : 0),
        recorded: current.recorded + 1,
      );
    }
    final sorted = tallies.values.toList()..sort((a, b) => a.month.compareTo(b.month));
    return [
      for (final tally in sorted)
        MonthTally(month: tally.month, bike: tally.bike, recorded: tally.recorded),
    ];
  }

  /// Le mois qui compte le plus de journees a velo. A egalite, le plus recent.
  MonthTally? get bestMonth {
    MonthTally? best;
    for (final tally in months) {
      if (best == null || tally.bike >= best.bike) {
        best = tally;
      }
    }
    return best?.bike == 0 ? null : best;
  }

  /// Combien de semaines la grille peut montrer, premiere journee comprise.
  int weeksSince(DateTime now) {
    final first = _first;
    if (first == null) {
      return 0;
    }
    final span = mondayOf(now).difference(mondayOf(first)).inDays;
    return span ~/ 7 + 1;
  }

  /// Les [count] dernieres semaines, de la plus ancienne a la plus recente,
  /// celle de [now] comprise. Cinq cases par semaine, du lundi au vendredi.
  List<RegularityWeek> lastWeeks(int count, {required DateTime now}) {
    final lastMonday = mondayOf(now);
    return [
      for (var back = count - 1; back >= 0; back--)
        () {
          final monday = lastMonday.subtract(Duration(days: back * 7));
          return (
            monday: monday,
            days: [
              for (var offset = 0; offset < 5; offset++)
                dayOn(monday.add(Duration(days: offset))),
            ],
          );
        }(),
    ];
  }
}

/// La cible d'un mois, telle qu'elle a ete enregistree.
class ChallengeTarget {
  const ChallengeTarget({required this.month, required this.target});

  /// Le premier jour du mois vise.
  final DateTime month;

  /// En journees a velo.
  final int target;

  Map<String, dynamic> toJson() => {'month': monthKey(month), 'target': target};

  static ChallengeTarget? fromJson(Object? raw) {
    if (raw is! Map || raw['target'] is! num) {
      return null;
    }
    final month = parseMonthKey('${raw['month']}');
    if (month == null) {
      return null;
    }
    final target = (raw['target'] as num).toInt();
    return target <= 0 ? null : ChallengeTarget(month: month, target: target);
  }
}

/// Ou en est le defi d'un mois.
class MonthChallenge {
  const MonthChallenge({
    required this.month,
    required this.target,
    required this.done,
    required this.workdays,
    required this.openWorkdays,
  });

  /// Le defi du mois qui contient [month], vu de [now].
  factory MonthChallenge.of(
    DateTime month, {
    required int target,
    required Iterable<CommuteDay> days,
    required DateTime now,
  }) {
    final first = DateTime(month.year, month.month);
    final total = daysOfMonth(first);
    final last = DateTime(first.year, first.month, total);
    final today = dateOnly(now);

    var done = 0;
    final recorded = <String>{};
    for (final day in days) {
      if (day.date.isBefore(first) || day.date.isAfter(last)) {
        continue;
      }
      recorded.add(dayKey(day.date));
      if (day.isBike) {
        done++;
      }
    }

    // Les jours ouvres qui restent a jouer : a partir d'aujourd'hui, et
    // seulement ceux ou rien n'est encore enregistre. Une journee deja saisie
    // en voiture est perdue pour le defi, et le dire evite d'annoncer une
    // cible encore atteignable alors qu'elle ne l'est plus.
    var open = 0;
    for (var day = 1; day <= total; day++) {
      final date = DateTime(first.year, first.month, day);
      if (date.isBefore(today) || !isWorkday(date) || recorded.contains(dayKey(date))) {
        continue;
      }
      open++;
    }

    return MonthChallenge(
      month: first,
      target: target,
      done: done,
      workdays: workdaysIn(first),
      openWorkdays: open,
    );
  }

  final DateTime month;
  final int target;

  /// Journees a velo deja enregistrees dans le mois.
  final int done;

  final int workdays;

  /// Jours ouvres restants, aujourd'hui compris, ou rien n'est enregistre.
  final int openWorkdays;

  bool get reached => done >= target;

  int get missing => reached ? 0 : target - done;

  double get ratio => target <= 0 ? 1 : (done / target).clamp(0, 1).toDouble();

  /// Faux quand il ne reste plus assez de jours ouvres pour y arriver.
  bool get stillPossible => reached || missing <= openWorkdays;
}

/// Une cible plausible pour [month] : la moyenne des journees a velo des
/// [lookback] mois precedents.
///
/// Nulle quand aucun de ces mois n'a de journee enregistree — proposer un
/// chiffre tire de rien ferait passer le hasard pour une mesure. Jamais plus
/// que les jours ouvres du mois, ni moins d'un.
int? suggestedTarget(
  DateTime month, {
  required Iterable<CommuteDay> days,
  int lookback = 3,
}) {
  final first = DateTime(month.year, month.month);
  var bike = 0;
  var recorded = 0;
  for (var back = 1; back <= lookback; back++) {
    final start = DateTime(first.year, first.month - back);
    final end = DateTime(start.year, start.month, daysOfMonth(start));
    for (final day in days) {
      if (day.date.isBefore(start) || day.date.isAfter(end)) {
        continue;
      }
      recorded++;
      if (day.isBike) {
        bike++;
      }
    }
  }
  if (recorded == 0) {
    return null;
  }
  final mean = (bike / lookback).round();
  return mean.clamp(1, workdaysIn(first));
}
