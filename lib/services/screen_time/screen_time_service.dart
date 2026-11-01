import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:i_zerak_app/models/commute_dao.dart' show dateOnly;
import 'package:i_zerak_app/models/screen_time_dao.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_screen_time.dart';
import 'package:i_zerak_app/services/screen_time/usage_source.dart';

/// Une moyenne de depart, et le nombre de jours qui la fondent.
typedef BaselineMeasure = ({double minutes, int days});

/// Fait le lien entre ce qu'Android mesure et ce que l'onglet retient.
///
/// A chaque ouverture, les journees terminees qui manquent encore sont
/// mesurees puis figees, tant qu'Android en garde la trace ; la journee en
/// cours est remesuree sans etre ecrite.
class ScreenTimeService {
  ScreenTimeService({
    required this.store,
    required this.source,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  final IScreenTime store;
  final IUsageSource source;
  final DateTime Function() clock;

  /// Jours en arriere qu'on tente de rattraper. Android en garde une dizaine ;
  /// au-dela, les reponses sont vides et `hasData` les ecarte.
  static const int catchUpDays = 9;

  /// Jours mesures pour la moyenne de depart.
  static const int baselineDays = 7;

  DateTime _day(DateTime day, int offset) => DateTime(day.year, day.month, day.day + offset);

  Future<DailyUsage?> _measure(DateTime day, Set<String> packages, {DateTime? until}) async {
    final window = await source.sessions(day, until ?? _day(day, 1), packages);
    return window.hasData ? DailyUsage.fromSessions(day, window.sessions, packages) : null;
  }

  /// Fige les journees terminees qui manquent, mesure aujourd'hui, et remet
  /// le bilan du soir a jour.
  Future<ScreenTimeLedger> sync() async {
    final now = clock();
    final today = dateOnly(now);
    final settings = await store.readSettings();
    final days = await store.getDays();
    final goals = await store.getGoals();

    DailyUsage? live;
    if (settings.isConfigured && await source.hasAccess()) {
      final known = {for (final day in days) day.date};
      final packages = settings.packages;
      final earliest = _day(today, -catchUpDays);
      var day = settings.startDate!.isAfter(earliest) ? settings.startDate! : earliest;
      for (; day.isBefore(today); day = _day(day, 1)) {
        if (known.contains(day)) {
          continue;
        }
        final usage = await _measure(day, packages);
        if (usage != null) {
          final closed = settings.close(usage);
          await store.saveDay(closed);
          days.add(closed);
        }
      }
      live = await _measure(today, packages, until: now) ?? DailyUsage.empty(today);
    }

    final ledger = ScreenTimeLedger(
      settings: settings,
      days: days,
      goals: goals,
      today: today,
      live: live,
    );
    await pushReport(ledger);
    return ledger;
  }

  /// La moyenne quotidienne des [baselineDays] jours precedant aujourd'hui.
  /// Nulle si Android n'a rien garde.
  Future<BaselineMeasure?> measureBaseline(Set<String> packages) async {
    final today = dateOnly(clock());
    var total = 0.0;
    var count = 0;
    for (var offset = baselineDays; offset >= 1; offset--) {
      final usage = await _measure(_day(today, -offset), packages);
      if (usage != null) {
        total += usage.minutes;
        count++;
      }
    }
    return count == 0 ? null : (minutes: total / count, days: count);
  }

  /// Transmet au bilan du soir de quoi se calculer seul, application fermee.
  ///
  /// Le natif refait le calcul du quota et du gain (cf. DailyReport.kt) : il
  /// recoit donc les memes parametres, et la serie arretee a hier.
  Future<void> pushReport(ScreenTimeLedger ledger) async {
    try {
      await source.configureReport(reportConfig(ledger));
    } on Exception catch (error) {
      // Le bilan est un plus : son echec ne doit pas empecher l'onglet de
      // s'afficher.
      debugPrint('Bilan du soir non programme : $error');
    }
  }

  /// Nul quand il n'y a rien a programmer.
  @visibleForTesting
  static Map<String, Object?>? reportConfig(ScreenTimeLedger ledger) {
    final settings = ledger.settings;
    if (!settings.isConfigured || !settings.reportEnabled) {
      return null;
    }
    final yesterday = DateTime(ledger.today.year, ledger.today.month, ledger.today.day - 1);
    return {
      'hour': settings.reportHour,
      'minute': settings.reportMinute,
      'packages': settings.packages.toList(),
      'baseline': settings.baselineMinutes,
      'startEpochDay': epochDay(settings.startDate!),
      'decrease': settings.weeklyDecrease,
      'floor': settings.floorMinutes,
      'rate': settings.ratePerHour,
      'streak': ledger.streak,
      'streakThroughEpochDay': epochDay(yesterday),
    };
  }

  /// Jours ecoules depuis le 1er janvier 1970, sur la date calendaire : la
  /// meme formule que cote Kotlin, pour que les deux s'accordent sur la
  /// semaine en cours.
  static int epochDay(DateTime day) =>
      DateTime.utc(day.year, day.month, day.day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;

  /// Configure l'onglet : les applications choisies, et la moyenne mesuree.
  Future<ScreenTimeSettings> start(List<TrackedApp> apps, BaselineMeasure baseline) async {
    final current = await store.readSettings();
    final settings = current
        .copyWith(apps: apps)
        .startingOn(clock(), math.max(0, baseline.minutes).toDouble());
    await store.saveSettings(settings);
    return settings;
  }
}
