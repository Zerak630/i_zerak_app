import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/commute_dao.dart';
import 'package:i_zerak_app/models/reminder_dao.dart';
import 'package:i_zerak_app/models/sport_dao.dart';
import 'package:i_zerak_app/pages/sport/widgets/sport_ui.dart' show sportLabel;
import 'package:i_zerak_app/services/repositories/interfaces/i_app_preferences.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_commute.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_sport.dart';

/// Ce que l'application demande aux rappels natifs (cf. Reminders.kt).
abstract interface class IReminderBridge {
  bool get isSupported;

  Future<void> configure(Map<String, Object?> config);

  /// Les reponses donnees depuis les notifications de sport, une seule fois.
  Future<List<String>> takePendingSlotAnswers();

  /// Demande l'autorisation de notifier (Android 13 et plus).
  Future<bool> requestNotifications();
}

class AndroidReminderBridge implements IReminderBridge {
  AndroidReminderBridge({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('izerak/reminders');

  final MethodChannel _channel;

  @override
  bool get isSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<void> configure(Map<String, Object?> config) async {
    if (isSupported) {
      await _channel.invokeMethod<void>('configure', config);
    }
  }

  @override
  Future<List<String>> takePendingSlotAnswers() async {
    if (!isSupported) {
      return const [];
    }
    final raw = await _channel.invokeListMethod<Object?>('takePendingSlotAnswers') ?? const [];
    return [for (final item in raw) if (item is String) item];
  }

  @override
  Future<bool> requestNotifications() async =>
      isSupported && (await _channel.invokeMethod<bool>('requestNotifications') ?? false);
}

/// Les rappels du soir : de quoi ne pas oublier de remplir l'application.
///
/// Les jours ouvres, « Velo ou voiture aujourd'hui ? » si la journee n'est
/// pas saisie ; les jours ou le programme prevoit du sport, « Seance faite ? »
/// pour chaque creneau sans reponse. Les deux se repondent depuis la
/// notification : « Velo » passe par le meme chemin que le widget, « Faite »
/// et « Pas faite » sont notes cote natif et enregistres ici au lancement
/// suivant.
///
/// Comme pour le bilan, le natif ne lit pas Hive : l'application lui transmet
/// ce qui est deja saisi chaque fois qu'elle passe en arriere-plan.
class ReminderService {
  ReminderService({
    required this.commute,
    required this.sport,
    required this.preferences,
    required this.bridge,
    DateTime Function()? clock,
    Locale Function()? locale,
  })  : clock = clock ?? DateTime.now,
        locale = locale ?? (() => PlatformDispatcher.instance.locale);

  final ICommute commute;
  final ISport sport;
  final IAppPreferences preferences;
  final IReminderBridge bridge;
  final DateTime Function() clock;
  final Locale Function() locale;

  /// Jusqu'ou remonter les reponses deja donnees : une notification restee
  /// dans le volet quelques jours doit encore pouvoir disparaitre.
  static const int _lookbackDays = 14;

  /// Faux hors Android : les rappels n'y partent pas, leurs reglages n'ont
  /// rien a y faire.
  bool get isSupported => bridge.isSupported;

  Future<ReminderSettings> readSettings() => preferences.readReminderSettings();

  Future<void> saveSettings(ReminderSettings settings) async {
    await preferences.saveReminderSettings(settings);
    if (settings.commute || settings.sport) {
      await ensureNotifications();
    }
    await push();
  }

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

  /// Au lancement : demande l'autorisation si un rappel a de quoi partir,
  /// puis programme les rappels.
  Future<void> start() async {
    if (!bridge.isSupported) {
      return;
    }
    final settings = await readSettings();
    final commuteDue = settings.commute && (await commute.readSettings()).isConfigured;
    final sportDue = settings.sport && (await sport.getPlan()).isNotEmpty;
    if (commuteDue || sportDue) {
      await ensureNotifications();
    }
    await push();
  }

  /// Transmet au natif les reglages et ce qui est deja saisi.
  Future<void> push() async {
    if (!bridge.isSupported) {
      return;
    }
    try {
      await bridge.configure(await config());
    } on Exception catch (error) {
      debugPrint('Rappels non programmes : $error');
    }
  }

  /// Enregistre les reponses donnees depuis les notifications de sport.
  /// Renvoie le nombre de creneaux remplis.
  ///
  /// Un creneau deja saisi dans l'application n'est pas ecrase.
  Future<int> importPendingAnswers() async {
    if (!bridge.isSupported) {
      return 0;
    }
    final raw = await bridge.takePendingSlotAnswers();
    if (raw.isEmpty) {
      return 0;
    }
    final plan = {for (final slot in await sport.getPlan()) slot.id: slot};
    final known = {for (final session in await sport.getSessions()) session.id};
    var added = 0;
    for (final item in raw.toSet()) {
      final answer = PendingSlotAnswer.parse(item, parseDayKey);
      final slot = answer == null ? null : plan[answer.slotId];
      if (answer == null || slot == null) {
        continue;
      }
      final id = SportSession.slotSessionId(slot, answer.day);
      if (known.contains(id)) {
        continue;
      }
      await sport.saveSession(answer.done
          ? SportSession.forSlot(slot, answer.day, minutes: slot.minutes)
          : SportSession.skipped(slot, answer.day));
      known.add(id);
      added++;
    }
    return added;
  }

  @visibleForTesting
  Future<Map<String, Object?>> config() async {
    final settings = await readSettings();
    final today = dateOnly(clock());
    final since = DateTime(today.year, today.month, today.day - _lookbackDays);
    final l10n = lookupAppLocalizations(_supported(locale()));
    final tag = locale().toLanguageTag();

    final commuteSettings = await commute.readSettings();
    final observed = await commute.latestPrice(commuteSettings.fuel, onOrBefore: today);
    final tripValue = commuteSettings.tripValue(observed?.price ?? kFallbackFuelPrice);
    final euros = NumberFormat.simpleCurrency(locale: tag, name: 'EUR').format(tripValue);
    final recorded = [
      for (final day in await commute.getDays())
        if (!day.date.isBefore(since)) dayKey(day.date),
    ];

    final sports = {for (final s in await sport.getSports()) s.id: s};
    final plan = await sport.getPlan();
    final answered = [
      for (final session in await sport.getSessions())
        if (session.slotId != null && !session.slotDay.isBefore(since))
          '${session.slotId}|${dayKey(session.slotDay)}',
    ];

    return {
      'commute': {
        'enabled': settings.commute,
        'hour': settings.commuteHour,
        'minute': settings.commuteMinute,
        'configured': commuteSettings.isConfigured,
        'answered': recorded,
        'title': l10n.reminder_commute_title,
        'text': l10n.reminder_commute_text(euros),
        'bike': l10n.reminder_commute_bike,
        'car': l10n.reminder_commute_car,
      },
      'sport': {
        'enabled': settings.sport,
        'hour': settings.sportHour,
        'minute': settings.sportMinute,
        'slots': [
          for (final slot in plan)
            {
              'id': slot.id,
              'weekday': slot.weekday,
              'title': l10n.reminder_sport_title(sportLabel(l10n, sports[slot.sportId]), slot.minutes),
              'text': l10n.reminder_sport_text,
            },
        ],
        'answered': answered,
        'done': l10n.reminder_sport_done,
        'skipped': l10n.reminder_sport_skipped,
      },
    };
  }

  static Locale _supported(Locale locale) =>
      AppLocalizations.supportedLocales.any((supported) => supported.languageCode == locale.languageCode)
          ? Locale(locale.languageCode)
          : const Locale('en');
}
