import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/screen_time_dao.dart';
import 'package:i_zerak_app/pages/commute/widgets/commute_ui.dart' show CommuteFormat, parseDecimal;
import 'package:i_zerak_app/pages/free_time/free_time_setup_page.dart';
import 'package:i_zerak_app/pages/free_time/widgets/free_time_ui.dart';
import 'package:i_zerak_app/services/screen_time/screen_time_service.dart';

/// Reglages de l'onglet Temps libre. Chaque changement est enregistre tout de
/// suite.
///
/// Rien ici ne touche aux journees deja terminees : leur quota et leur gain
/// ont ete figes a minuit.
class FreeTimeSettingsPage extends StatefulWidget {
  const FreeTimeSettingsPage({super.key, required this.service});

  final ScreenTimeService service;

  @override
  State<FreeTimeSettingsPage> createState() => _FreeTimeSettingsPageState();
}

class _FreeTimeSettingsPageState extends State<FreeTimeSettingsPage> {
  ScreenTimeSettings _settings = const ScreenTimeSettings();
  bool _loading = true;

  /// Les applications ont change depuis la mesure de la moyenne : elle ne
  /// compare plus la meme chose.
  bool _appsChanged = false;

  static const List<double> _decreases = [0.05, 0.10, 0.15, 0.20];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await widget.service.store.readSettings();
    if (mounted) {
      setState(() {
        _settings = settings;
        _loading = false;
      });
    }
  }

  Future<void> _save(ScreenTimeSettings settings) async {
    setState(() => _settings = settings);
    await widget.service.store.saveSettings(settings);
  }

  Future<void> _pickApps() async {
    final available = await widget.service.source.launchableApps();
    if (!mounted) {
      return;
    }
    final apps = await Navigator.push<List<TrackedApp>>(
      context,
      MaterialPageRoute(builder: (_) => AppPickerPage(available: available, selected: _settings.apps)),
    );
    if (apps == null || apps.isEmpty) {
      return;
    }
    final changed = !setEquals({for (final app in apps) app.package}, _settings.packages);
    await _save(_settings.copyWith(apps: apps));
    if (mounted && changed) {
      setState(() => _appsChanged = true);
    }
  }

  Future<void> _editRate() async {
    final l10n = AppLocalizations.of(context)!;
    final value = await _askNumber(
      title: l10n.free_settings_rate,
      initial: _settings.ratePerHour,
      suffix: l10n.free_per_hour_suffix,
    );
    if (value != null && value >= 0) {
      await _save(_settings.copyWith(ratePerHour: roundTo2(value)));
    }
  }

  Future<void> _editFloor() async {
    final l10n = AppLocalizations.of(context)!;
    final value = await _askNumber(
      title: l10n.free_settings_floor,
      initial: _settings.floorMinutes.toDouble(),
      suffix: 'min',
    );
    if (value != null && value >= 0) {
      await _save(_settings.copyWith(floorMinutes: value.round()));
    }
  }

  static double roundTo2(double value) => (value * 100).roundToDouble() / 100;

  Future<double?> _askNumber({
    required String title,
    required double initial,
    required String suffix,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final text = initial == initial.roundToDouble()
        ? initial.toStringAsFixed(0)
        : initial.toStringAsFixed(2);
    final controller = TextEditingController(
        text: Localizations.localeOf(context).languageCode == 'fr' ? text.replaceAll('.', ',') : text);
    final result = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(suffixText: suffix),
          onSubmitted: (value) => Navigator.pop(context, parseDecimal(value)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(context, parseDecimal(controller.text)),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _toggleReport(bool enabled) async {
    if (enabled) {
      await widget.service.source.requestNotifications();
    }
    await _save(_settings.copyWith(reportEnabled: enabled));
  }

  Future<void> _pickReportTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _settings.reportHour, minute: _settings.reportMinute),
    );
    if (time != null) {
      await _save(_settings.copyWith(reportHour: time.hour, reportMinute: time.minute));
    }
  }

  Future<void> _restart() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.free_settings_restart),
        content: Text(l10n.free_settings_restart_confirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.free_settings_restart_action)),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final done = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => FreeTimeSetupPage(service: widget.service)),
    );
    if (done == true) {
      setState(() => _appsChanged = false);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = CommuteFormat(context);

    // L'onglet relit les reglages au retour, et reprogramme le bilan avec.
    return Scaffold(
        appBar: AppBar(title: Text(l10n.free_settings_title)),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(children: [
                _Section(l10n.free_settings_tracking),
                ListTile(
                  leading: const Icon(Icons.apps),
                  title: Text(l10n.free_settings_apps),
                  subtitle: Text(appsSummary(l10n, _settings.apps)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _pickApps,
                ),
                if (_appsChanged)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(l10n.free_settings_apps_changed,
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.tertiary)),
                  ),
                if (_settings.baselineMinutes != null)
                  ListTile(
                    leading: const Icon(Icons.restart_alt),
                    title: Text(l10n.free_settings_restart),
                    subtitle: Text(l10n.free_settings_baseline(
                      formatMinutes(l10n, _settings.baselineMinutes!),
                      format.dayMonth(_settings.startDate!),
                    )),
                    onTap: _restart,
                  ),
                _Section(l10n.free_settings_quota),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: Text(l10n.free_settings_decrease, style: theme.textTheme.bodyLarge),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: SegmentedButton<double>(
                    segments: [
                      for (final decrease in _decreases)
                        ButtonSegment(value: decrease, label: Text('−${(decrease * 100).round()} %')),
                    ],
                    selected: {
                      _decreases.firstWhere(
                        (d) => (d - _settings.weeklyDecrease).abs() < 0.001,
                        orElse: () => 0.10,
                      ),
                    },
                    onSelectionChanged: (selection) =>
                        _save(_settings.copyWith(weeklyDecrease: selection.first)),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.vertical_align_bottom),
                  title: Text(l10n.free_settings_floor),
                  subtitle: Text(l10n.free_settings_floor_hint),
                  trailing: Text(formatMinutes(l10n, _settings.floorMinutes.toDouble()),
                      style: theme.textTheme.titleSmall),
                  onTap: _editFloor,
                ),
                _Section(l10n.free_settings_pot),
                ListTile(
                  leading: const Icon(Icons.savings_outlined),
                  title: Text(l10n.free_settings_rate),
                  subtitle: Text(l10n.free_settings_rate_hint),
                  trailing: Text(l10n.free_per_hour(format.euros(_settings.ratePerHour)),
                      style: theme.textTheme.titleSmall),
                  onTap: _editRate,
                ),
                _Section(l10n.free_settings_report),
                SwitchListTile(
                  secondary: const Icon(Icons.notifications_outlined),
                  title: Text(l10n.free_settings_report_enabled),
                  subtitle: Text(l10n.free_settings_report_hint),
                  value: _settings.reportEnabled,
                  onChanged: _toggleReport,
                ),
                ListTile(
                  enabled: _settings.reportEnabled,
                  leading: const Icon(Icons.schedule),
                  title: Text(l10n.free_settings_report_time),
                  trailing: Text(
                    TimeOfDay(hour: _settings.reportHour, minute: _settings.reportMinute)
                        .format(context),
                    style: theme.textTheme.titleSmall,
                  ),
                  onTap: _pickReportTime,
                ),
                const SizedBox(height: 24),
              ]),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(label, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
    );
  }
}
