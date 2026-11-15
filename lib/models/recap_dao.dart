/// Le bilan d'une semaine ou d'un mois : l'essence economisee, le temps repris
/// aux reseaux, et le temps de sport.
///
/// Chaque habitude garde son unite : des euros pour le velo, parce qu'ils sont
/// reels ; du temps pour les reseaux et le sport, parce qu'un prix de l'heure
/// serait invente. Le bilan les met cote a cote, sans les additionner.
///
/// Dart pur : rien n'est stocke, tout se recalcule a partir des depots.
library;

import 'package:i_zerak_app/models/commute_dao.dart';
import 'package:i_zerak_app/models/payback_dao.dart';
import 'package:i_zerak_app/models/screen_time_dao.dart';
import 'package:i_zerak_app/models/sport_dao.dart';
import 'package:i_zerak_app/models/subscription_dao.dart' show Subscription;

enum RecapPeriod { week, month }

/// Une periode de bilan, bornes incluses.
class RecapRange {
  const RecapRange._(this.period, this.start, this.end);

  /// La semaine, du lundi au dimanche, qui contient [day].
  factory RecapRange.weekOf(DateTime day) {
    final monday = weekStart(day);
    return RecapRange._(RecapPeriod.week, monday, dayOfWeek(monday, DateTime.sunday));
  }

  /// Le mois qui contient [day].
  factory RecapRange.monthOf(DateTime day) => RecapRange._(
        RecapPeriod.month,
        DateTime(day.year, day.month),
        DateTime(day.year, day.month + 1, 0),
      );

  factory RecapRange.of(RecapPeriod period, DateTime day) =>
      period == RecapPeriod.week ? RecapRange.weekOf(day) : RecapRange.monthOf(day);

  final RecapPeriod period;
  final DateTime start;
  final DateTime end;

  RecapRange get previous => RecapRange.of(period, DateTime(start.year, start.month, start.day - 1));

  RecapRange get next => RecapRange.of(period, DateTime(end.year, end.month, end.day + 1));

  bool contains(DateTime day) {
    final date = dateOnly(day);
    return !date.isBefore(start) && !date.isAfter(end);
  }

  int get days => DateTime.utc(end.year, end.month, end.day)
          .difference(DateTime.utc(start.year, start.month, start.day))
          .inDays +
      1;

  @override
  bool operator ==(Object other) =>
      other is RecapRange && other.period == period && other.start == start;

  @override
  int get hashCode => Object.hash(period, start);
}

/// Le temps libre d'une periode. Absent quand l'onglet n'est pas configure.
class FreeTimeRecap {
  const FreeTimeRecap({
    required this.regainedMinutes,
    required this.keptDays,
    required this.measuredDays,
    required this.overMinutes,
  });

  final double regainedMinutes;
  final int keptDays;

  /// Les journees mesurees et figees : celles que le telephone a gardees et
  /// que l'application a vues passer.
  final int measuredDays;
  final double overMinutes;
}

class Recap {
  const Recap({
    required this.range,
    required this.fuelSaved,
    required this.bikeDays,
    required this.commuteConfigured,
    required this.payback,
    required this.freeTime,
    required this.sportMinutes,
    required this.sportSessions,
    required this.bySport,
    required this.planned,
    required this.plannedDone,
  });

  final RecapRange range;

  final double fuelSaved;
  final int bikeDays;

  /// Faux tant que le trajet n'est pas regle : la ligne du velo n'a alors
  /// rien a dire.
  final bool commuteConfigured;

  /// Les abonnements rembourses : pour un mois seulement, puisqu'ils se
  /// comptent au mois.
  final MonthPayback? payback;

  final FreeTimeRecap? freeTime;

  final int sportMinutes;
  final int sportSessions;
  final List<SportTotal> bySport;

  /// Les creneaux du programme deja arrives sur la periode, et ceux qui ont
  /// ete faits.
  final int planned;
  final int plannedDone;

  /// La part du temps repris aux reseaux qui est allee au sport, entre 0 et
  /// 1. Nulle sans temps repris.
  double? get sportShareOfRegained {
    final regained = freeTime?.regainedMinutes ?? 0;
    return regained <= 0 ? null : (sportMinutes / regained).clamp(0, 1).toDouble();
  }
}

/// Le bilan de [range].
///
/// [screenTime] est nul quand le Temps libre n'est pas configure, ou hors
/// Android. Ses journees figees sont seules comptees : la journee en cours ne
/// l'est qu'a minuit.
Recap buildRecap(
  RecapRange range, {
  required CommuteSettings commuteSettings,
  required CommuteLedger commute,
  required Iterable<Subscription> subscriptions,
  required ScreenTimeLedger? screenTime,
  required SportLedger sport,
}) {
  var fuel = 0.0;
  var bikeDays = 0;
  for (final day in commute.days) {
    if (day.isBike && range.contains(day.date)) {
      fuel += day.amount;
      bikeDays++;
    }
  }

  FreeTimeRecap? freeTime;
  if (screenTime != null && screenTime.settings.isConfigured) {
    final days = [for (final day in screenTime.days) if (range.contains(day.date)) day];
    freeTime = FreeTimeRecap(
      regainedMinutes: screenTime.regainedBetween(range.start, range.end),
      keptDays: days.where((day) => day.underQuota).length,
      measuredDays: days.length,
      overMinutes: screenTime.overBetween(range.start, range.end),
    );
  }

  var planned = 0;
  var plannedDone = 0;
  for (var monday = weekStart(range.start);
      !monday.isAfter(range.end);
      monday = DateTime(monday.year, monday.month, monday.day + 7)) {
    for (final slot in sport.slotsOf(monday)) {
      // Seuls les creneaux deja arrives : en cours de mois, ceux de la fin
      // ne sont pas encore « pas faits ».
      if (range.contains(slot.date) && !slot.date.isAfter(sport.today)) {
        planned++;
        if (slot.status == SlotStatus.done) {
          plannedDone++;
        }
      }
    }
  }
  final sessions = sport.doneBetween(range.start, range.end).toList();

  return Recap(
    range: range,
    fuelSaved: roundCents(fuel),
    bikeDays: bikeDays,
    commuteConfigured: commuteSettings.isConfigured,
    payback: range.period == RecapPeriod.month
        ? paybackOf(
            range.start,
            subscriptions: subscriptions,
            commute: commute,
            excluded: commuteSettings.paybackExcluded,
          )
        : null,
    freeTime: freeTime,
    sportMinutes: sessions.fold(0, (sum, session) => sum + session.minutes),
    sportSessions: sessions.length,
    bySport: sport.totalsBySport(from: range.start, to: range.end),
    planned: planned,
    plannedDone: plannedDone,
  );
}

/// Les notifications de bilan : chaque dimanche soir pour la semaine, le
/// dernier jour du mois pour le mois.
class RecapSettings {
  const RecapSettings({
    this.weekly = true,
    this.monthly = true,
    this.hour = 19,
    this.minute = 30,
  });

  final bool weekly;
  final bool monthly;
  final int hour;
  final int minute;

  RecapSettings copyWith({bool? weekly, bool? monthly, int? hour, int? minute}) => RecapSettings(
        weekly: weekly ?? this.weekly,
        monthly: monthly ?? this.monthly,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
      );

  Map<String, dynamic> toJson() => {
        'weekly': weekly,
        'monthly': monthly,
        'hour': hour,
        'minute': minute,
      };

  factory RecapSettings.fromJson(Object? raw) {
    if (raw is! Map) {
      return const RecapSettings();
    }
    const defaults = RecapSettings();
    int? asInt(Object? value) => value is num ? value.toInt() : null;
    return RecapSettings(
      weekly: raw['weekly'] is bool ? raw['weekly'] as bool : defaults.weekly,
      monthly: raw['monthly'] is bool ? raw['monthly'] as bool : defaults.monthly,
      hour: asInt(raw['hour'])?.clamp(0, 23) ?? defaults.hour,
      minute: asInt(raw['minute'])?.clamp(0, 59) ?? defaults.minute,
    );
  }
}
