import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/screen_time_dao.dart';
import 'package:i_zerak_app/pages/commute/widgets/commute_ui.dart' show CommuteFormat, parseDecimal;
import 'package:i_zerak_app/pages/free_time/free_time_setup_page.dart';
import 'package:i_zerak_app/pages/free_time/widgets/free_time_ui.dart';
import 'package:i_zerak_app/pages/settings/widgets/settings_ui.dart';
import 'package:i_zerak_app/services/screen_time/screen_time_service.dart';
import 'package:i_zerak_app/services/service_locator.dart';

/// La categorie « Temps libre » : les applications suivies et le quota.
/// Chaque changement est enregistre tout de suite.
///
/// Le bilan du soir, lui, est range avec les autres notifications.
///
/// Rien ici ne touche aux journees deja terminees : leur quota et leur gain
/// ont ete figes a minuit.
class FreeTimeSection extends StatefulWidget {
  FreeTimeSection({super.key, ScreenTimeService? service})
      : service = service ?? getIt<ScreenTimeService>();

  final ScreenTimeService service;

  @override
  State<FreeTimeSection> createState() => _FreeTimeSectionState();
}

class _FreeTimeSectionState extends State<FreeTimeSection> {
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
    // Relu avant d'ecrire : le bilan du soir se regle dans une autre
    // categorie, et sa copie ici peut dater.
    final stored = await widget.service.store.readSettings();
    await widget.service.store.saveSettings(stored.copyWith(
      apps: settings.apps,
      weeklyDecrease: settings.weeklyDecrease,
      floorMinutes: settings.floorMinutes,
    ));
    // Le widget et le bilan du soir recalculent le quota de leur cote : ils
    // doivent connaitre les nouvelles regles sans attendre l'ouverture de
    // l'onglet.
    await widget.service.sync();
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

  Future<void> _editFloor() async {
    final l10n = AppLocalizations.of(context)!;
    final value = await _askMinutes(title: l10n.free_settings_floor, initial: _settings.floorMinutes);
    if (value != null && value >= 0) {
      await _save(_settings.copyWith(floorMinutes: value.round()));
    }
  }

  Future<double?> _askMinutes({required String title, required int initial}) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: '$initial');
    final result = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(suffixText: 'min'),
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

  /// Premiere mise en route, ou nouvelle mesure de la moyenne.
  Future<void> _setup({required bool confirm}) async {
    final l10n = AppLocalizations.of(context)!;
    if (confirm) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.free_settings_restart),
          content: Text(l10n.free_settings_restart_confirm),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
            TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l10n.free_settings_restart_action)),
          ],
        ),
      );
      if (confirmed != true || !mounted) {
        return;
      }
    }
    final done = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => FreeTimeSetupPage(service: widget.service)),
    );
    if (done == true && mounted) {
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
    if (_loading) {
      return const SettingsLoading();
    }

    // Tant que la moyenne de depart n'est pas mesuree, il n'y a rien a
    // regler : tout part de la mise en route.
    if (!_settings.isConfigured) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(l10n.settings_free_time_not_ready,
            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: () => _setup(confirm: false),
          icon: const Icon(Icons.play_arrow),
          label: Text(l10n.settings_free_time_setup),
        ),
      ]);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SettingsSubtitle(l10n.free_settings_tracking, first: true),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.apps),
        title: Text(l10n.free_settings_apps),
        subtitle: Text(appsSummary(l10n, _settings.apps)),
        trailing: const Icon(Icons.chevron_right),
        onTap: _pickApps,
      ),
      if (_appsChanged)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(l10n.free_settings_apps_changed,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.tertiary)),
        ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.restart_alt),
        title: Text(l10n.free_settings_restart),
        subtitle: Text(l10n.free_settings_baseline(
          formatMinutes(l10n, _settings.baselineMinutes!),
          format.dayMonth(_settings.startDate!),
        )),
        onTap: () => _setup(confirm: true),
      ),
      SettingsSubtitle(l10n.free_settings_quota),
      Text(l10n.free_settings_decrease, style: theme.textTheme.bodyLarge),
      const SizedBox(height: 8),
      SegmentedButton<double>(
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
        onSelectionChanged: (selection) => _save(_settings.copyWith(weeklyDecrease: selection.first)),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.vertical_align_bottom),
        title: Text(l10n.free_settings_floor),
        subtitle: Text(l10n.free_settings_floor_hint),
        trailing: Text(formatMinutes(l10n, _settings.floorMinutes.toDouble()),
            style: theme.textTheme.titleSmall),
        onTap: _editFloor,
      ),
    ]);
  }
}
