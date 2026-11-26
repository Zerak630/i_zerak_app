import 'package:flutter/material.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/recap_dao.dart';
import 'package:i_zerak_app/models/screen_time_dao.dart';
import 'package:i_zerak_app/pages/settings/widgets/settings_ui.dart';
import 'package:i_zerak_app/services/recap/recap_service.dart';
import 'package:i_zerak_app/services/screen_time/screen_time_service.dart';
import 'package:i_zerak_app/services/service_locator.dart';

/// La categorie « Notifications et rappels » : tout ce que l'appli envoie
/// d'elle-meme, reuni pour qu'on voie d'un coup d'oeil a quelle heure le
/// telephone va sonner.
///
/// Chaque groupe garde son stockage — le bilan du soir vit avec le Temps
/// libre, les bilans dans les preferences — et chaque changement s'applique
/// aussitot.
class NotificationsSection extends StatefulWidget {
  NotificationsSection({super.key, ScreenTimeService? screenTime, RecapService? recap})
      : screenTime = screenTime ??
            (getIt.isRegistered<ScreenTimeService>() ? getIt<ScreenTimeService>() : null),
        recap = recap ?? (getIt.isRegistered<RecapService>() ? getIt<RecapService>() : null);

  final ScreenTimeService? screenTime;
  final RecapService? recap;

  @override
  State<NotificationsSection> createState() => _NotificationsSectionState();
}

class _NotificationsSectionState extends State<NotificationsSection> {
  ScreenTimeSettings? _freeTime;
  RecapSettings? _recap;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final freeTime = await widget.screenTime?.store.readSettings();
    final recap = await widget.recap?.readSettings();
    if (mounted) {
      setState(() {
        _freeTime = freeTime;
        _recap = recap;
        _loading = false;
      });
    }
  }

  // --- Bilan du soir du Temps libre ------------------------------------------

  Future<void> _saveFreeTime({bool? enabled, TimeOfDay? time}) async {
    final service = widget.screenTime!;
    if (enabled == true) {
      await service.source.requestNotifications();
    }
    // Relu : les applis et le quota se reglent dans une autre categorie.
    final stored = await service.store.readSettings();
    final next = stored.copyWith(
      reportEnabled: enabled,
      reportHour: time?.hour,
      reportMinute: time?.minute,
    );
    if (mounted) {
      setState(() => _freeTime = next);
    }
    await service.store.saveSettings(next);
    // Reprogramme le bilan tout de suite, sans attendre l'onglet.
    await service.sync();
  }

  // --- Bilans de la semaine et du mois --------------------------------------

  Future<void> _saveRecap(RecapSettings settings) async {
    setState(() => _recap = settings);
    await widget.recap!.saveSettings(settings);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final hintStyle =
        theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline, height: 1.4);
    if (_loading) {
      return const SettingsLoading();
    }
    final freeTime = _freeTime;
    final recap = _recap;

    // Les rappels du soir (trajet, sport) prendront place en tete.
    final groups = <List<Widget>>[
      // Sans moyenne de depart, le bilan du soir n'aurait rien a dire.
      if (freeTime != null && freeTime.isConfigured)
        [
          SettingsSubtitle(l10n.free_settings_report),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.hourglass_bottom),
            title: Text(l10n.free_settings_report_enabled),
            subtitle: Text(l10n.free_settings_report_hint),
            value: freeTime.reportEnabled,
            onChanged: (value) => _saveFreeTime(enabled: value),
          ),
          SettingsTimeTile(
            title: l10n.free_settings_report_time,
            hour: freeTime.reportHour,
            minute: freeTime.reportMinute,
            enabled: freeTime.reportEnabled,
            onChanged: (time) => _saveFreeTime(time: time),
          ),
        ],
      if (recap != null)
        [
          SettingsSubtitle(l10n.recap_notifications),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.date_range),
            title: Text(l10n.recap_notify_weekly),
            subtitle: Text(l10n.recap_notify_weekly_hint),
            value: recap.weekly,
            onChanged: (value) => _saveRecap(recap.copyWith(weekly: value)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.calendar_month),
            title: Text(l10n.recap_notify_monthly),
            subtitle: Text(l10n.recap_notify_monthly_hint),
            value: recap.monthly,
            onChanged: (value) => _saveRecap(recap.copyWith(monthly: value)),
          ),
          SettingsTimeTile(
            title: l10n.free_settings_report_time,
            hour: recap.hour,
            minute: recap.minute,
            enabled: recap.weekly || recap.monthly,
            onChanged: (time) => _saveRecap(recap.copyWith(hour: time.hour, minute: time.minute)),
          ),
          Text(l10n.recap_notify_hint, style: hintStyle),
        ],
    ];

    if (groups.isEmpty) {
      return Text(l10n.settings_notifications_none, style: hintStyle);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < groups.length; i++) ...[
        // Le premier intertitre colle a l'en-tete de la categorie.
        if (i == 0)
          SettingsSubtitle((groups[i].first as SettingsSubtitle).text, first: true)
        else
          groups[i].first,
        ...groups[i].skip(1),
      ],
    ]);
  }
}
