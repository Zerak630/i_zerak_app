import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/commute_dao.dart';
import 'package:i_zerak_app/models/recap_dao.dart';
import 'package:i_zerak_app/models/screen_time_dao.dart';
import 'package:i_zerak_app/models/sport_dao.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_app_preferences.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_commute.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_screen_time.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_sport.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_subscriptions.dart';

/// Ce que l'application transmet au bilan natif (cf. RecapReport.kt).
abstract interface class IRecapBridge {
  bool get isSupported;

  Future<void> configure(Map<String, Object?> config);

  /// Demande l'autorisation de notifier (Android 13 et plus). Vrai si elle
  /// est accordee ; sans effet si elle l'est deja.
  Future<bool> requestNotifications();
}

class AndroidRecapBridge implements IRecapBridge {
  AndroidRecapBridge({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('izerak/screen_time');

  final MethodChannel _channel;

  @override
  bool get isSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<void> configure(Map<String, Object?> config) async {
    if (isSupported) {
      await _channel.invokeMethod<void>('configureRecap', config);
    }
  }

  @override
  Future<bool> requestNotifications() async =>
      isSupported && (await _channel.invokeMethod<bool>('requestNotifications') ?? false);
}

/// Le bilan de la semaine et du mois : a l'ecran, et en notification.
///
/// La notification part application fermee, le dimanche soir et le dernier
/// jour du mois. Le natif ne lit pas Hive : chaque fois que l'application
/// passe en arriere-plan, elle lui transmet les textes deja rediges du bilan
/// en cours et du precedent. Au moment de notifier, il prend celui dont la
/// periode se termine ce jour-la. Le bilan dit donc ce qui a ete saisi
/// jusqu'a la derniere ouverture d'iZerak.
class RecapService {
  RecapService({
    required this.commute,
    required this.subscriptions,
    required this.sport,
    required this.preferences,
    required this.bridge,
    this.screenTime,
    DateTime Function()? clock,
    Locale Function()? locale,
  })  : clock = clock ?? DateTime.now,
        locale = locale ?? (() => PlatformDispatcher.instance.locale);

  final ICommute commute;
  final ISubscriptions subscriptions;
  final ISport sport;
  final IAppPreferences preferences;
  final IRecapBridge bridge;

  /// Nul hors Android : le Temps libre n'y existe pas.
  final IScreenTime? screenTime;

  final DateTime Function() clock;

  /// La langue des notifications : celle du telephone, comme l'application.
  final Locale Function() locale;

  /// Les bilans de [ranges], lus une seule fois dans les depots.
  Future<List<Recap>> build(List<RecapRange> ranges) async {
    final today = dateOnly(clock());
    final settings = await commute.readSettings();
    final ledger = CommuteLedger(await commute.getDays(), const []);
    final subs = await subscriptions.getAll();
    final sportLedger = SportLedger(
      sports: await sport.getSports(),
      plan: await sport.getPlan(),
      sessions: await sport.getSessions(),
      today: today,
    );
    ScreenTimeLedger? free;
    final store = screenTime;
    if (store != null) {
      final freeSettings = await store.readSettings();
      if (freeSettings.isConfigured) {
        free = ScreenTimeLedger(settings: freeSettings, days: await store.getDays(), today: today);
      }
    }
    return [
      for (final range in ranges)
        buildRecap(
          range,
          commuteSettings: settings,
          commute: ledger,
          subscriptions: subs,
          screenTime: free,
          sport: sportLedger,
        ),
    ];
  }

  Future<Recap> recapOf(RecapRange range) async => (await build([range])).single;

  Future<RecapSettings> readSettings() => preferences.readRecapSettings();

  Future<void> saveSettings(RecapSettings settings) async {
    await preferences.saveRecapSettings(settings);
    if (settings.weekly || settings.monthly) {
      await ensureNotifications();
    }
    await push();
  }

  /// Demande l'autorisation de notifier, une fois que les bilans sont a
  /// l'ecran : c'est la qu'on comprend a quoi elle sert. Le Temps libre la
  /// demande aussi, mais on peut faire du sport sans lui.
  Future<void> ensureNotifications() async {
    if (!bridge.isSupported) {
      return;
    }
    try {
      await bridge.requestNotifications();
    } on Exception catch (error) {
      debugPrint('Autorisation de notifier non demandee : $error');
    }
  }

  /// Transmet au natif les reglages et les textes des bilans.
  Future<void> push() async {
    if (!bridge.isSupported) {
      return;
    }
    try {
      await bridge.configure(await config());
    } on Exception catch (error) {
      // Le bilan est un plus : son echec ne doit rien bloquer.
      debugPrint('Bilan non programme : $error');
    }
  }

  /// Les reglages, et les bilans de la semaine et du mois en cours et
  /// precedents, chacun avec le jour ou il se termine.
  @visibleForTesting
  Future<Map<String, Object?>> config() async {
    final settings = await readSettings();
    final today = dateOnly(clock());
    final week = RecapRange.weekOf(today);
    final month = RecapRange.monthOf(today);
    final recaps = await build([week, week.previous, month, month.previous]);
    final l10n = lookupAppLocalizations(_supported(locale()));
    final writer = RecapWriter(l10n, locale().toLanguageTag());
    return {
      'weekly': settings.weekly,
      'monthly': settings.monthly,
      'hour': settings.hour,
      'minute': settings.minute,
      'entries': [
        for (final recap in recaps)
          {
            'kind': recap.range.period.name,
            'endEpochDay': epochDay(recap.range.end),
            'title': writer.title(recap),
            'text': writer.text(recap),
          },
      ],
    };
  }

  static Locale _supported(Locale locale) =>
      AppLocalizations.supportedLocales.any((supported) => supported.languageCode == locale.languageCode)
          ? Locale(locale.languageCode)
          : const Locale('en');

  /// Meme formule que cote Kotlin (cf. ScreenTimeService.epochDay).
  static int epochDay(DateTime day) =>
      DateTime.utc(day.year, day.month, day.day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;
}

/// Le texte d'un bilan, tel que la notification et la carte de l'accueil le
/// disent. Une ligne par habitude, dans son unite.
class RecapWriter {
  RecapWriter(this.l10n, this.locale);

  final AppLocalizations l10n;
  final String locale;

  String euros(double value) =>
      NumberFormat.currency(locale: locale, symbol: '€', decimalDigits: 2).format(value);

  String minutes(num value) {
    final total = value.round();
    if (total < 60) {
      return l10n.free_minutes(total);
    }
    return l10n.free_hours(total ~/ 60, (total % 60).toString().padLeft(2, '0'));
  }

  String title(Recap recap) => recap.range.period == RecapPeriod.week
      ? l10n.recap_title_week
      : l10n.recap_title_month(DateFormat('MMMM', locale).format(recap.range.start));

  String? bikeLine(Recap recap) {
    if (!recap.commuteConfigured && recap.bikeDays == 0) {
      return null;
    }
    final line = l10n.recap_bike(euros(recap.fuelSaved), recap.bikeDays);
    final payback = recap.payback;
    if (payback == null || payback.lines.isEmpty) {
      return line;
    }
    return '$line · ${l10n.recap_payback(payback.paidCount, payback.lines.length)}';
  }

  String? freeLine(Recap recap) {
    final free = recap.freeTime;
    if (free == null) {
      return null;
    }
    return l10n.recap_free(minutes(free.regainedMinutes), free.keptDays, free.measuredDays);
  }

  String sportLine(Recap recap) {
    if (recap.sportSessions == 0) {
      return l10n.recap_sport_none;
    }
    final line = l10n.recap_sport(minutes(recap.sportMinutes), recap.sportSessions);
    return recap.planned > 0
        ? '$line · ${l10n.sport_plan_progress(recap.plannedDone, recap.planned)}'
        : line;
  }

  String text(Recap recap) => [
        if (bikeLine(recap) case final String line) '🚲 $line',
        if (freeLine(recap) case final String line) '📱 $line',
        '💪 ${sportLine(recap)}',
      ].join('\n');
}
