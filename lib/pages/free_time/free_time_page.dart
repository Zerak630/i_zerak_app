import 'package:flutter/material.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/commute_dao.dart' show Goal;
import 'package:i_zerak_app/models/screen_time_dao.dart';
import 'package:i_zerak_app/pages/commute/widgets/commute_ui.dart' show CommuteFormat;
import 'package:i_zerak_app/pages/commute/widgets/goal_sheets.dart';
import 'package:i_zerak_app/pages/commute/widgets/pot_carousel.dart';
import 'package:i_zerak_app/pages/free_time/free_time_settings_page.dart';
import 'package:i_zerak_app/pages/free_time/free_time_setup_page.dart';
import 'package:i_zerak_app/pages/free_time/widgets/free_time_ui.dart';
import 'package:i_zerak_app/services/screen_time/screen_time_service.dart';
import 'package:i_zerak_app/services/service_locator.dart';

/// L'onglet Temps libre : le temps passe aujourd'hui sur les reseaux, le
/// quota qui baisse chaque semaine, et la cagnotte de ce qui a ete gagne.
///
/// Rien ne se saisit ici : Android mesure, l'onglet compte.
class FreeTimePage extends StatefulWidget {
  FreeTimePage({super.key, ScreenTimeService? service})
      : service = service ?? getIt<ScreenTimeService>();

  final ScreenTimeService service;

  @override
  State<FreeTimePage> createState() => _FreeTimePageState();
}

class _FreeTimePageState extends State<FreeTimePage> {
  late final AppLifecycleListener _lifecycle;

  ScreenTimeLedger? _ledger;
  bool _access = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // Revenir sur l'application, c'est souvent revenir d'Instagram : la
    // journee a bouge, la mesure doit suivre.
    _lifecycle = AppLifecycleListener(onResume: _sync);
    _sync();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _sync() async {
    final ledger = await widget.service.sync();
    final access = await widget.service.source.hasAccess();
    if (!mounted) {
      return;
    }
    setState(() {
      _ledger = ledger;
      _access = access;
      _loading = false;
    });
  }

  Future<void> _openSetup() async {
    final done = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => FreeTimeSetupPage(service: widget.service)),
    );
    if (done == true) {
      await _sync();
    }
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FreeTimeSettingsPage(service: widget.service)),
    );
    await _sync();
  }

  /// Ce qui manque a un objectif, traduit en heures loin des reseaux.
  double? _hoursFor(double amount) {
    final rate = _ledger?.settings.ratePerHour ?? 0;
    return rate <= 0 || amount <= 0 ? null : amount / rate;
  }

  Future<void> _newGoal() async {
    final l10n = AppLocalizations.of(context)!;
    final ledger = _ledger!;
    final goal = await showNewGoalSheet(
      context,
      book: ledger.book,
      missingHint: (missing) {
        final hours = _hoursFor(missing);
        return hours == null
            ? null
            : l10n.free_goal_missing_hours(_hoursLabel(hours), CommuteFormat(context).euros(ledger.settings.ratePerHour));
      },
    );
    if (goal == null) {
      return;
    }
    await widget.service.store.saveGoal(goal);
    await _sync();
  }

  Future<void> _validateGoal(Goal goal) async {
    final confirmed = await showValidateGoalSheet(context, goal: goal, book: _ledger!.book);
    if (!confirmed || !_ledger!.book.progressOf(goal).reached) {
      return;
    }
    await widget.service.store.saveGoal(goal.validated(DateTime.now()));
    await _sync();
  }

  Future<void> _deleteGoal(Goal goal) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.goal_delete),
        content: Text(l10n.delete_confirm(goal.name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.delete)),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.service.store.deleteGoal(goal.id);
      await _sync();
    }
  }

  /// « 3 h », « 1,5 h » : un ordre de grandeur, pas un chronometre.
  String _hoursLabel(double hours) => CommuteFormat(context).number(
        hours >= 10 ? hours.roundToDouble() : (hours * 2).ceilToDouble() / 2,
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final ledger = _ledger!;
    final source = widget.service.source;

    if (!source.isSupported) {
      return _Message(
        icon: Icons.phone_android,
        title: l10n.free_unsupported_title,
        body: l10n.free_unsupported_body,
      );
    }
    if (!ledger.settings.isConfigured) {
      return _Message(
        icon: Icons.hourglass_bottom,
        title: l10n.free_intro_title,
        body: l10n.free_intro_body,
        action: FilledButton.icon(
          onPressed: _openSetup,
          icon: const Icon(Icons.play_arrow),
          label: Text(l10n.free_intro_action),
        ),
      );
    }

    final format = CommuteFormat(context);
    return RefreshIndicator(
      onRefresh: _sync,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          GoalCarousel(
            book: ledger.book,
            leading: _FreePotTile(ledger: ledger),
            remainingLabel: (remaining) {
              final hours = _hoursFor(remaining);
              return hours == null
                  ? l10n.goal_remaining_amount(format.euros(remaining))
                  : l10n.free_goal_remaining(format.euros(remaining), _hoursLabel(hours));
            },
            onValidate: _validateGoal,
            onNewGoal: _newGoal,
            onDeleteGoal: _deleteGoal,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const SizedBox(height: 12),
              if (!_access) ...[
                _AccessLostCard(onFix: source.openAccessSettings),
                const SizedBox(height: 12),
              ],
              _TodayCard(ledger: ledger, onSettings: _openSettings),
              const SizedBox(height: 12),
              _WeekCard(ledger: ledger),
              const SizedBox(height: 12),
              _HoursCard(ledger: ledger),
              const SizedBox(height: 8),
              _RecentDays(ledger: ledger),
            ]),
          ),
        ],
      ),
    );
  }
}

/// Couleur d'une journee : primaire sous le quota, tertiaire au-dessus,
/// neutre sans mesure.
Color _dayColor(ColorScheme scheme, ScreenTimeDay? day) {
  if (day == null) {
    return scheme.surfaceContainerHighest;
  }
  return day.underQuota ? scheme.primary : scheme.tertiary;
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.body, this.action});

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListView(padding: const EdgeInsets.all(24), children: [
      const SizedBox(height: 24),
      CircleAvatar(
        radius: 36,
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        child: Icon(icon, size: 36),
      ),
      const SizedBox(height: 20),
      Text(title, textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
      const SizedBox(height: 10),
      Text(body,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
      if (action != null) ...[
        const SizedBox(height: 24),
        Center(child: action!),
      ],
    ]);
  }
}

class _FreePotTile extends StatelessWidget {
  const _FreePotTile({required this.ledger});

  final ScreenTimeLedger ledger;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = CommuteFormat(context);
    final today = ledger.today;

    final String subtitle;
    if (ledger.book.spent > 0) {
      subtitle = l10n.commute_saved_and_spent(
          format.euros(ledger.totalSaved), format.euros(ledger.book.spent));
    } else if (ledger.days.isEmpty) {
      subtitle = l10n.free_pot_first_day;
    } else {
      subtitle = l10n.free_pot_hours(
          formatMinutes(l10n, ledger.hoursSaved * 60), format.dayMonth(ledger.settings.startDate!));
    }

    return PotTileFrame(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        PotTileHeader(
          icon: Icons.savings_outlined,
          label: l10n.free_pot,
          color: scheme.primary,
        ),
        const SizedBox(height: 10),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            format.euros(ledger.balance),
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.primary,
              letterSpacing: -1,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
        const Spacer(),
        Row(children: [
          for (var offset = 14; offset >= 1; offset--) ...[
            Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                color: _dayColor(scheme,
                    ledger.dayOn(DateTime(today.year, today.month, today.day - offset))),
                shape: BoxShape.circle,
              ),
            ),
            if (offset > 1) const SizedBox(width: 7),
          ],
        ]),
        const SizedBox(height: 8),
        Text(l10n.free_last_14_days,
            style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline)),
      ]),
    );
  }
}

class _AccessLostCard extends StatelessWidget {
  const _AccessLostCard({required this.onFix});

  final VoidCallback onFix;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l10n.free_access_lost,
            style: theme.textTheme.titleMedium?.copyWith(color: scheme.onErrorContainer)),
        const SizedBox(height: 4),
        Text(l10n.free_access_lost_hint,
            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onErrorContainer)),
        const SizedBox(height: 10),
        FilledButton(onPressed: onFix, child: Text(l10n.free_setup_access_action)),
      ]),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        child: child,
      );
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.ledger, required this.onSettings});

  final ScreenTimeLedger ledger;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = CommuteFormat(context);
    final live = ledger.live;
    final quota = ledger.todayQuota;
    final under = ledger.todayUnderQuota;
    final color = under ? scheme.primary : scheme.tertiary;
    final ratio = quota <= 0 ? (live.seconds > 0 ? 1.0 : 0.0) : (live.minutes / quota).clamp(0.0, 1.0);

    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text(l10n.commute_today(format.longDay(ledger.today)),
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
          ),
          IconButton(
            onPressed: onSettings,
            tooltip: l10n.free_settings_title,
            icon: const Icon(Icons.tune),
            visualDensity: VisualDensity.compact,
          ),
        ]),
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Text(formatMinutes(l10n, live.minutes),
              style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700, color: color)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(l10n.free_today_quota(formatMinutes(l10n, quota)),
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
          ),
        ]),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 10,
            color: color,
            backgroundColor: scheme.surfaceContainerHighest,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          under
              ? l10n.free_today_left(formatMinutes(l10n, quota - live.minutes))
              : l10n.free_today_over(formatMinutes(l10n, live.minutes - quota)),
          style: theme.textTheme.bodySmall?.copyWith(color: color),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: _Figure(
              icon: Icons.touch_app_outlined,
              value: '${live.opens}',
              label: l10n.free_opens(live.opens),
            ),
          ),
          Expanded(
            child: _Figure(
              icon: Icons.savings_outlined,
              value: '+ ${format.euros(ledger.todayGain)}',
              label: l10n.free_today_gain,
            ),
          ),
        ]),
        if (live.ranked.isNotEmpty) ...[
          const SizedBox(height: 8),
          Divider(color: scheme.surfaceContainerHighest),
          for (final entry in live.ranked)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                Expanded(
                  child: Text(ledger.settings.labelOf(entry.key),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
                ),
                Text(l10n.free_opens_short(entry.value.opens),
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline)),
                SizedBox(
                  width: 72,
                  child: Text(formatMinutes(l10n, entry.value.seconds / 60),
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                ),
              ]),
            ),
        ],
      ]),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.icon, required this.value, required this.label});

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(children: [
      Icon(icon, size: 20, color: scheme.onSurfaceVariant),
      const SizedBox(width: 8),
      Flexible(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: theme.textTheme.titleMedium),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline)),
        ]),
      ),
    ]);
  }
}

class _WeekCard extends StatelessWidget {
  const _WeekCard({required this.ledger});

  final ScreenTimeLedger ledger;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = CommuteFormat(context);
    final average = ledger.weekAverage;
    final trend = ledger.trend;
    final streak = ledger.streak;

    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l10n.free_week_title, style: theme.textTheme.titleSmall),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: _Figure(
              icon: Icons.local_fire_department_outlined,
              value: l10n.free_streak_days(streak),
              label: l10n.free_streak,
            ),
          ),
          Expanded(
            child: _Figure(
              icon: Icons.trending_down,
              value: trend == null ? '—' : '${trend > 0 ? '+' : ''}${format.percent(trend)}',
              label: average == null
                  ? l10n.free_week_no_data
                  : l10n.free_week_average(formatMinutes(l10n, average)),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Text(
          l10n.free_week_quota(
            formatMinutes(l10n, ledger.todayQuota),
            formatMinutes(l10n, ledger.nextWeekQuota),
          ),
          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        Text(
          l10n.free_week_baseline(formatMinutes(l10n, ledger.settings.baselineMinutes ?? 0)),
          style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
        ),
      ]),
    );
  }
}

/// Les heures ou la main part toute seule, sur une semaine.
class _HoursCard extends StatelessWidget {
  const _HoursCard({required this.ledger});

  final ScreenTimeLedger ledger;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final profile = ledger.hourlyProfile;
    final peak = ledger.peakHour;
    final max = profile.fold(0.0, (m, v) => v > m ? v : m);

    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l10n.free_hours_title, style: theme.textTheme.titleSmall),
        const SizedBox(height: 2),
        Text(
          peak == null
              ? l10n.free_hours_empty
              : l10n.free_hours_peak(formatHour(context, peak), formatMinutes(l10n, profile[peak])),
          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 64,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (var hour = 0; hour < 24; hour++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1.5),
                  child: Container(
                    height: max <= 0 ? 2 : 2 + 62 * profile[hour] / max,
                    decoration: BoxDecoration(
                      color: hour == peak ? scheme.tertiary : scheme.primary.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          for (final hour in const [0, 6, 12, 18, 23])
            Text(formatHour(context, hour), style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline)),
        ]),
      ]),
    );
  }
}

class _RecentDays extends StatelessWidget {
  const _RecentDays({required this.ledger});

  final ScreenTimeLedger ledger;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = CommuteFormat(context);
    final days = ledger.days.take(7).toList();
    if (days.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(l10n.commute_recent, style: theme.textTheme.titleSmall),
      ),
      for (final day in days) ...[
        SizedBox(
          height: 44,
          child: Row(children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: _dayColor(scheme, day), shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(format.shortDay(day.date), style: theme.textTheme.bodyMedium)),
            Text(
              l10n.free_day_detail(formatMinutes(l10n, day.minutes), formatMinutes(l10n, day.quotaMinutes)),
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
            ),
            SizedBox(
              width: 72,
              child: Text(
                '+ ${format.euros(day.amount)}',
                textAlign: TextAlign.right,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w500, color: _dayColor(scheme, day)),
              ),
            ),
          ]),
        ),
        if (day != days.last) Divider(height: 1, color: scheme.surfaceContainerHigh),
      ],
    ]);
  }
}
