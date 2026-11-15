import 'package:flutter/material.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/commute_dao.dart' show dateOnly;
import 'package:i_zerak_app/models/recap_dao.dart';
import 'package:i_zerak_app/models/sport_dao.dart' show Sport;
import 'package:i_zerak_app/pages/commute/widgets/commute_ui.dart' show CommuteFormat;
import 'package:i_zerak_app/pages/sport/widgets/sport_ui.dart';
import 'package:i_zerak_app/services/recap/recap_service.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_sport.dart';

/// Le bilan d'une semaine ou d'un mois : ce que le velo a economise, le temps
/// repris aux reseaux, et le temps de sport — chacun dans son unite.
class RecapPage extends StatefulWidget {
  const RecapPage({super.key, required this.service, required this.sport, this.clock});

  final RecapService service;

  /// Pour les noms et couleurs des sports.
  final ISport sport;

  final DateTime Function()? clock;

  @override
  State<RecapPage> createState() => _RecapPageState();
}

class _RecapPageState extends State<RecapPage> {
  late RecapRange _range = RecapRange.weekOf(_today);
  Recap? _recap;
  Recap? _previous;
  RecapSettings? _settings;
  List<Sport> _sports = const [];

  DateTime get _today => dateOnly((widget.clock ?? DateTime.now)());

  @override
  void initState() {
    super.initState();
    _load();
    widget.service.readSettings().then((settings) {
      if (mounted) {
        setState(() => _settings = settings);
      }
      if (settings.weekly || settings.monthly) {
        widget.service.ensureNotifications();
      }
    });
  }

  Future<void> _load() async {
    final recaps = await widget.service.build([_range, _range.previous]);
    final sports = await widget.sport.getSports();
    if (!mounted) {
      return;
    }
    setState(() {
      _recap = recaps.first;
      _previous = recaps.last;
      _sports = sports;
    });
  }

  void _show(RecapRange range) {
    setState(() {
      _range = range;
      _recap = null;
    });
    _load();
  }

  Future<void> _saveSettings(RecapSettings settings) async {
    setState(() => _settings = settings);
    await widget.service.saveSettings(settings);
  }

  Future<void> _pickTime() async {
    final settings = _settings;
    if (settings == null) {
      return;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: settings.hour, minute: settings.minute),
    );
    if (time != null) {
      await _saveSettings(settings.copyWith(hour: time.hour, minute: time.minute));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final recap = _recap;
    final current = _range.contains(_today);
    final settings = _settings;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.recap_page_title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          SegmentedButton<RecapPeriod>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: RecapPeriod.week, label: Text(l10n.sport_period_week)),
              ButtonSegment(value: RecapPeriod.month, label: Text(l10n.recap_month)),
            ],
            selected: {_range.period},
            onSelectionChanged: (selection) => _show(RecapRange.of(selection.first, _today)),
          ),
          const SizedBox(height: 8),
          Row(children: [
            IconButton(
              onPressed: () => _show(_range.previous),
              tooltip: l10n.recap_previous,
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                _rangeLabel(context, l10n),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
            ),
            IconButton(
              onPressed: current ? null : () => _show(_range.next),
              tooltip: l10n.recap_next,
              icon: const Icon(Icons.chevron_right),
            ),
          ]),
          if (current)
            Text(
              l10n.recap_in_progress,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline),
            ),
          const SizedBox(height: 12),
          if (recap == null)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            _BikeCard(recap: recap, previous: _previous),
            const SizedBox(height: 10),
            if (recap.freeTime != null) ...[
              _FreeCard(recap: recap, previous: _previous),
              const SizedBox(height: 10),
            ],
            _SportCard(recap: recap, previous: _previous, sports: _sports),
          ],
          if (settings != null) ...[
            const SizedBox(height: 24),
            Text(l10n.recap_notifications, style: theme.textTheme.titleSmall),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.recap_notify_weekly),
              subtitle: Text(l10n.recap_notify_weekly_hint),
              value: settings.weekly,
              onChanged: (value) => _saveSettings(settings.copyWith(weekly: value)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.recap_notify_monthly),
              subtitle: Text(l10n.recap_notify_monthly_hint),
              value: settings.monthly,
              onChanged: (value) => _saveSettings(settings.copyWith(monthly: value)),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.free_settings_report_time),
              trailing: Text(
                TimeOfDay(hour: settings.hour, minute: settings.minute).format(context),
                style: theme.textTheme.titleSmall,
              ),
              enabled: settings.weekly || settings.monthly,
              onTap: _pickTime,
            ),
            Text(
              l10n.recap_notify_hint,
              style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  String _rangeLabel(BuildContext context, AppLocalizations l10n) {
    final format = CommuteFormat(context);
    if (_range.period == RecapPeriod.month) {
      return format.month(_range.start);
    }
    final sport = SportFormat(context);
    return l10n.recap_week_range(sport.dayMonth(_range.start), sport.dayMonth(_range.end));
  }
}

/// Une carte du bilan : une icone, un chiffre, et ce qui l'accompagne.
class _RecapCard extends StatelessWidget {
  const _RecapCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
    this.detail,
    this.trend,
    this.children = const [],
  });

  final IconData icon;
  final String title;
  final String value;
  final Color color;
  final String? detail;
  final String? trend;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: theme.textTheme.labelMedium?.copyWith(
                letterSpacing: 0.7,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          if (trend != null)
            Text(trend!, style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline)),
        ]),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700, color: color),
          ),
        ),
        if (detail != null) ...[
          const SizedBox(height: 2),
          Text(detail!, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
        ],
        ...children,
      ]),
    );
  }
}

String? _trend(AppLocalizations l10n, String Function(num) format, num now, num? before) {
  if (before == null || before <= 0) {
    return null;
  }
  return l10n.recap_before(format(before));
}

class _BikeCard extends StatelessWidget {
  const _BikeCard({required this.recap, required this.previous});

  final Recap recap;
  final Recap? previous;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = CommuteFormat(context);
    final payback = recap.payback;

    return _RecapCard(
      icon: Icons.pedal_bike,
      title: l10n.recap_bike_title,
      value: format.euros(recap.fuelSaved),
      color: scheme.primary,
      detail: l10n.payback_saved(recap.bikeDays),
      trend: _trend(l10n, (v) => format.euros(v.toDouble()), recap.fuelSaved, previous?.fuelSaved),
      children: [
        if (payback != null && payback.lines.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: Text(
                l10n.payback_count(payback.paidCount, payback.lines.length),
                style: theme.textTheme.titleSmall,
              ),
            ),
            Text(
              l10n.payback_amount(format.euros(payback.covered), format.euros(payback.total)),
              style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ]),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: payback.ratio,
              minHeight: 6,
              color: scheme.primary,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final line in payback.lines)
              if (line.paid)
                Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(Icons.check, size: 16, color: scheme.primary),
                  label: Text(line.subscription.name),
                ),
          ]),
        ],
      ],
    );
  }
}

class _FreeCard extends StatelessWidget {
  const _FreeCard({required this.recap, required this.previous});

  final Recap recap;
  final Recap? previous;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final free = recap.freeTime!;
    final writer = _minutes(l10n);

    return _RecapCard(
      icon: Icons.hourglass_bottom,
      title: l10n.free_regained_title,
      value: writer(free.regainedMinutes),
      color: scheme.secondary,
      detail: l10n.recap_free_detail(free.keptDays, free.measuredDays, writer(free.overMinutes)),
      trend: _trend(l10n, writer, free.regainedMinutes, previous?.freeTime?.regainedMinutes),
    );
  }
}

class _SportCard extends StatelessWidget {
  const _SportCard({required this.recap, required this.previous, required this.sports});

  final Recap recap;
  final Recap? previous;
  final List<Sport> sports;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final writer = _minutes(l10n);
    final share = recap.sportShareOfRegained;
    String label(String id) {
      for (final sport in sports) {
        if (sport.id == id) {
          return sportLabel(l10n, sport);
        }
      }
      return sportLabel(l10n, null);
    }

    return _RecapCard(
      icon: Icons.fitness_center,
      title: l10n.bb_sport,
      value: writer(recap.sportMinutes),
      color: scheme.tertiary,
      detail: recap.planned > 0
          ? '${l10n.sport_sessions(recap.sportSessions)} · ${l10n.sport_plan_progress(recap.plannedDone, recap.planned)}'
          : l10n.sport_sessions(recap.sportSessions),
      trend: _trend(l10n, writer, recap.sportMinutes, previous?.sportMinutes),
      children: [
        if (recap.bySport.isNotEmpty) const SizedBox(height: 8),
        for (final total in recap.bySport)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Expanded(child: Text(label(total.sportId), style: theme.textTheme.bodyMedium)),
              Text(
                '${writer(total.minutes)} · ${l10n.sport_sessions_short(total.sessions)}',
                style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ]),
          ),
        // Seulement quand le sport tient dans le temps repris : « 1 h 15 des
        // 51 min reprises » ne voudrait rien dire.
        if (share != null && recap.sportMinutes > 0 && share < 1) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: scheme.tertiaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              l10n.recap_sport_share(
                writer(recap.freeTime!.regainedMinutes),
                writer(recap.sportMinutes),
              ),
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onTertiaryContainer),
            ),
          ),
        ],
      ],
    );
  }
}

String Function(num) _minutes(AppLocalizations l10n) => (value) => sportMinutes(l10n, value.round());
