import 'package:flutter/material.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/screen_time_dao.dart';
import 'package:i_zerak_app/pages/commute/widgets/commute_ui.dart' show parseDecimal;
import 'package:i_zerak_app/pages/free_time/widgets/free_time_ui.dart';
import 'package:i_zerak_app/services/screen_time/screen_time_service.dart';

/// Mise en route de l'onglet : l'acces aux donnees, les applications a
/// suivre, puis la moyenne de depart. Renvoie `true` une fois l'onglet
/// configure.
///
/// Sert aussi a recalculer la moyenne depuis les reglages : les semaines du
/// quota repartent alors de zero, la cagnotte et l'historique restent.
class FreeTimeSetupPage extends StatefulWidget {
  const FreeTimeSetupPage({super.key, required this.service});

  final ScreenTimeService service;

  @override
  State<FreeTimeSetupPage> createState() => _FreeTimeSetupPageState();
}

class _FreeTimeSetupPageState extends State<FreeTimeSetupPage> {
  late final AppLifecycleListener _lifecycle;

  bool _loading = true;
  bool _access = false;
  List<TrackedApp> _available = const [];
  List<TrackedApp> _apps = const [];

  /// Mesuree apres le choix des applications. Nulle tant qu'on n'a pas mesure.
  BaselineMeasure? _baseline;
  bool _measured = false;
  bool _measuring = false;
  final _manual = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Au retour des reglages d'Android, ou l'acces vient peut-etre d'etre
    // accorde.
    _lifecycle = AppLifecycleListener(onResume: _checkAccess);
    _load();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _manual.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final source = widget.service.source;
    final settings = await widget.service.store.readSettings();
    final access = await source.hasAccess();
    final available = await source.launchableApps();
    if (!mounted) {
      return;
    }
    setState(() {
      _access = access;
      _available = available;
      _apps = settings.apps.isNotEmpty
          ? settings.apps
          : [
              for (final app in available)
                if (kSuggestedApps.containsKey(app.package)) app,
            ];
      _loading = false;
    });
  }

  Future<void> _checkAccess() async {
    final access = await widget.service.source.hasAccess();
    if (mounted && access != _access) {
      setState(() => _access = access);
    }
  }

  Future<void> _pickApps() async {
    final apps = await Navigator.push<List<TrackedApp>>(
      context,
      MaterialPageRoute(builder: (_) => AppPickerPage(available: _available, selected: _apps)),
    );
    if (apps != null && mounted) {
      setState(() {
        _apps = apps;
        _measured = false;
        _baseline = null;
      });
    }
  }

  Future<void> _measure() async {
    setState(() => _measuring = true);
    final baseline =
        await widget.service.measureBaseline({for (final app in _apps) app.package});
    if (!mounted) {
      return;
    }
    setState(() {
      _baseline = baseline;
      _measured = true;
      _measuring = false;
    });
  }

  /// La moyenne retenue : mesuree, ou saisie quand Android n'a rien garde.
  BaselineMeasure? get _chosenBaseline {
    if (_baseline != null) {
      return _baseline;
    }
    final minutes = parseDecimal(_manual.text);
    return minutes == null || minutes <= 0 ? null : (minutes: minutes, days: 0);
  }

  Future<void> _start() async {
    final baseline = _chosenBaseline;
    if (baseline == null) {
      return;
    }
    final settings = await widget.service.start(_apps, baseline);
    if (settings.reportEnabled) {
      await widget.service.source.requestNotifications();
    }
    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.free_setup_title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
              Text(l10n.free_setup_intro,
                  style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 20),
              _Step(
                number: 1,
                title: l10n.free_setup_access,
                done: _access,
                child: _access
                    ? Text(l10n.free_setup_access_ok)
                    : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(l10n.free_setup_access_hint),
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          onPressed: widget.service.source.openAccessSettings,
                          icon: const Icon(Icons.open_in_new),
                          label: Text(l10n.free_setup_access_action),
                        ),
                      ]),
              ),
              _Step(
                number: 2,
                title: l10n.free_setup_apps,
                done: _apps.isNotEmpty,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(appsSummary(l10n, _apps)),
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                    onPressed: _pickApps,
                    icon: const Icon(Icons.checklist),
                    label: Text(l10n.free_setup_apps_action),
                  ),
                ]),
              ),
              _Step(
                number: 3,
                title: l10n.free_setup_baseline,
                done: _chosenBaseline != null,
                last: true,
                child: _baselineStep(l10n, theme),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _access && _apps.isNotEmpty && _chosenBaseline != null ? _start : null,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                child: Text(l10n.free_setup_start),
              ),
            ]),
    );
  }

  Widget _baselineStep(AppLocalizations l10n, ThemeData theme) {
    final scheme = theme.colorScheme;
    if (!_measured) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l10n.free_setup_baseline_hint),
        const SizedBox(height: 10),
        FilledButton.tonalIcon(
          onPressed: _access && _apps.isNotEmpty && !_measuring ? _measure : null,
          icon: _measuring
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.query_stats),
          label: Text(l10n.free_setup_baseline_action),
        ),
      ]);
    }
    final baseline = _baseline;
    if (baseline == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l10n.free_setup_baseline_none),
        const SizedBox(height: 10),
        TextField(
          controller: _manual,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: l10n.free_setup_baseline_manual,
            suffixText: 'min',
            border: const OutlineInputBorder(),
          ),
        ),
      ]);
    }
    final preview = const ScreenTimeSettings()
        .copyWith(apps: _apps)
        .startingOn(DateTime.now(), baseline.minutes);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(formatMinutes(l10n, baseline.minutes),
          style: theme.textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.w700, color: scheme.primary)),
      Text(l10n.free_setup_baseline_result(baseline.days),
          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
      const SizedBox(height: 8),
      Text(l10n.free_setup_first_quota(formatMinutes(l10n, preview.quotaFor(DateTime.now())))),
    ]);
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.title,
    required this.done,
    required this.child,
    this.last = false,
  });

  final int number;
  final String title;
  final bool done;
  final Widget child;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Column(children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: done ? scheme.primary : scheme.surfaceContainerHighest,
            foregroundColor: done ? scheme.onPrimary : scheme.onSurfaceVariant,
            child: done ? const Icon(Icons.check, size: 16) : Text('$number'),
          ),
          if (!last)
            Expanded(child: Container(width: 2, color: scheme.outlineVariant)),
        ]),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 22),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(top: 3, bottom: 6),
                child: Text(title, style: theme.textTheme.titleMedium),
              ),
              child,
            ]),
          ),
        ),
      ]),
    );
  }
}
