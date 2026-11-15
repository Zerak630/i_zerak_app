import 'package:flutter/material.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/commute_dao.dart' show dateOnly;
import 'package:i_zerak_app/models/sport_dao.dart';
import 'package:i_zerak_app/pages/recap/recap_page.dart';
import 'package:i_zerak_app/pages/sport/sport_plan_page.dart';
import 'package:i_zerak_app/pages/sport/widgets/sport_sheets.dart';
import 'package:i_zerak_app/pages/sport/widgets/sport_ui.dart';
import 'package:i_zerak_app/services/recap/recap_service.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_sport.dart';
import 'package:i_zerak_app/services/service_locator.dart';

/// L'onglet Sport : la semaine, le programme a remplir, et le temps passe sur
/// chaque sport.
///
/// Tout se saisit a la main, et c'est voulu : dire chaque semaine ce qui a ete
/// fait — ou pas — est ce qui fait tenir l'habitude.
class SportPage extends StatefulWidget {
  SportPage({super.key, ISport? store, RecapService? recap, DateTime Function()? clock})
      : store = store ?? getIt<ISport>(),
        recap = recap ?? (getIt.isRegistered<RecapService>() ? getIt<RecapService>() : null),
        clock = clock ?? DateTime.now;

  final ISport store;

  /// Le bilan, qui met le sport a cote du velo et des reseaux. Nul dans les
  /// tests qui ne s'en servent pas : le bouton disparait.
  final RecapService? recap;
  final DateTime Function() clock;

  @override
  State<SportPage> createState() => _SportPageState();
}

/// Les periodes du temps par sport.
enum _Period { week, month, all }

class _SportPageState extends State<SportPage> {
  SportLedger? _ledger;

  /// Le lundi de la semaine affichee : la semaine en cours, ou une passee
  /// qu'on remplit apres coup.
  late DateTime _monday = weekStart(_today);
  var _period = _Period.month;

  DateTime get _today => dateOnly(widget.clock());

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final sports = await widget.store.getSports();
    final plan = await widget.store.getPlan();
    final sessions = await widget.store.getSessions();
    if (!mounted) {
      return;
    }
    setState(() {
      _ledger = SportLedger(sports: sports, plan: plan, sessions: sessions, today: _today);
    });
  }

  Future<void> _addSession() async {
    final session = await showNewSessionSheet(context, sports: _ledger!.sports, today: _today);
    if (session == null) {
      return;
    }
    await widget.store.saveSession(session);
    await _reload();
  }

  Future<void> _answer(WeekSlot slot) async {
    final answer = await showSlotSheet(
      context,
      slot: slot,
      sport: _ledger!.sportById(slot.slot.sportId),
    );
    switch (answer) {
      case null:
        return;
      case SlotDone(:final minutes):
        await widget.store.saveSession(SportSession.forSlot(slot.slot, slot.date, minutes: minutes));
      case SlotSkipped():
        await widget.store.saveSession(SportSession.skipped(slot.slot, slot.date));
      case SlotCleared():
        await widget.store.deleteSession(SportSession.slotSessionId(slot.slot, slot.date));
    }
    await _reload();
  }

  Future<void> _deleteSession(SportSession session) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.sport_delete_session),
        content: Text(l10n.delete_confirm(sportLabel(l10n, _ledger!.sportById(session.sportId)))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.delete)),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.store.deleteSession(session.id);
      await _reload();
    }
  }

  Future<void> _openPlan() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SportPlanPage(store: widget.store)),
    );
    await _reload();
  }

  Future<void> _openRecap() => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RecapPage(service: widget.recap!, sport: widget.store, clock: widget.clock),
        ),
      );

  void _shiftWeek(int weeks) => setState(
        () => _monday = DateTime(_monday.year, _monday.month, _monday.day + 7 * weeks),
      );

  @override
  Widget build(BuildContext context) {
    final ledger = _ledger;
    if (ledger == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final current = weekStart(_today);
    final isCurrent = _monday == current;
    final slots = ledger.slotsOf(_monday);
    final extras = ledger.extrasOf(_monday);
    // Ce qui reste a saisir de la semaine derniere, rappele sur la semaine en
    // cours : c'est la qu'on regarde.
    final previousPending = isCurrent
        ? [for (final slot in ledger.pending) if (slot.date.isBefore(current)) slot]
        : const <WeekSlot>[];

    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _addSession,
                icon: const Icon(Icons.add),
                label: Text(l10n.sport_new_session),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              onPressed: _openPlan,
              icon: const Icon(Icons.event_note_outlined),
              label: Text(l10n.sport_plan),
            ),
            if (widget.recap != null) ...[
              const SizedBox(width: 4),
              IconButton.filledTonal(
                onPressed: _openRecap,
                tooltip: l10n.recap_open,
                icon: const Icon(Icons.insights),
              ),
            ],
          ]),
          const SizedBox(height: 12),
          _WeekCard(
            week: ledger.weekOf(_monday),
            streak: ledger.weekStreak,
            isCurrent: isCurrent,
            canGoForward: _monday.isBefore(current),
            onShift: _shiftWeek,
          ),
          if (previousPending.isNotEmpty) ...[
            const SizedBox(height: 16),
            _SectionTitle(l10n.sport_pending_last_week),
            for (final slot in previousPending)
              _SlotRow(slot: slot, ledger: ledger, onTap: () => _answer(slot)),
          ],
          const SizedBox(height: 16),
          _SectionTitle(l10n.sport_planned_section),
          if (slots.isEmpty)
            _EmptyPlan(onOpen: _openPlan)
          else
            for (final slot in slots) _SlotRow(slot: slot, ledger: ledger, onTap: () => _answer(slot)),
          if (extras.isNotEmpty) ...[
            const SizedBox(height: 16),
            _SectionTitle(l10n.sport_extras_section),
            for (final session in extras)
              _SessionRow(
                session: session,
                ledger: ledger,
                onLongPress: () => _deleteSession(session),
              ),
          ],
          const SizedBox(height: 16),
          _BySportCard(
            ledger: ledger,
            period: _period,
            monday: _monday,
            today: _today,
            onPeriod: (period) => setState(() => _period = period),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.sport_delete_hint,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelMedium?.copyWith(
          letterSpacing: 0.7,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// La semaine : son temps, ses seances, son programme, et jour par jour.
class _WeekCard extends StatelessWidget {
  const _WeekCard({
    required this.week,
    required this.streak,
    required this.isCurrent,
    required this.canGoForward,
    required this.onShift,
  });

  final WeekSummary week;
  final int streak;
  final bool isCurrent;
  final bool canGoForward;
  final ValueChanged<int> onShift;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = SportFormat(context);
    final max = week.perDay.fold(0, (m, v) => v > m ? v : m);

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          IconButton(
            onPressed: () => onShift(-1),
            tooltip: l10n.sport_previous_week,
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Text(
              isCurrent ? l10n.sport_this_week.toUpperCase() : l10n.sport_week_of(format.dayMonth(week.monday)).toUpperCase(),
              textAlign: TextAlign.center,
              style: theme.textTheme.labelMedium?.copyWith(
                letterSpacing: 0.7,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          IconButton(
            onPressed: canGoForward ? () => onShift(1) : null,
            tooltip: l10n.sport_next_week,
            icon: const Icon(Icons.chevron_right),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                sportMinutes(l10n, week.minutes),
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.primary,
                  letterSpacing: -1,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              week.planned == 0
                  ? l10n.sport_sessions(week.sessions)
                  : '${l10n.sport_sessions(week.sessions)} · ${l10n.sport_plan_progress(week.plannedDone, week.planned)}',
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 64,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (var day = 0; day < 7; day++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Container(
                        height: max <= 0 ? 3 : 3 + 61 * week.perDay[day] / max,
                        decoration: BoxDecoration(
                          color: week.perDay[day] > 0 ? scheme.primary : scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 4),
            Row(children: [
              for (var day = 1; day <= 7; day++)
                Expanded(
                  child: Text(
                    format.weekdayShort(day),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline),
                  ),
                ),
            ]),
            if (isCurrent) ...[
              const SizedBox(height: 12),
              Row(children: [
                Icon(Icons.local_fire_department_outlined, size: 18, color: scheme.tertiary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n.sport_streak(streak),
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ]),
            ],
          ]),
        ),
      ]),
    );
  }
}

/// Un creneau du programme, et ce qu'il en est.
class _SlotRow extends StatelessWidget {
  const _SlotRow({required this.slot, required this.ledger, required this.onTap});

  final WeekSlot slot;
  final SportLedger ledger;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = SportFormat(context);
    final sport = ledger.sportById(slot.slot.sportId);
    final status = slot.status;

    final (String label, Color color, IconData icon) = switch (status) {
      SlotStatus.done => (
          sportMinutes(l10n, slot.session!.minutes),
          scheme.primary,
          Icons.check_circle,
        ),
      SlotStatus.skipped => (l10n.sport_slot_status_skipped, scheme.outline, Icons.remove_circle_outline),
      SlotStatus.pending => (l10n.sport_slot_status_pending, scheme.tertiary, Icons.edit_note),
      SlotStatus.upcoming => (l10n.sport_slot_status_upcoming, scheme.outline, Icons.schedule),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        leading: SportAvatar(
          sport: sport,
          color: sportColor(scheme, ledger.sports, slot.slot.sportId),
          muted: status == SlotStatus.skipped,
        ),
        title: Text(sportLabel(l10n, sport)),
        subtitle: Text('${format.shortDay(slot.date)} · ${sportMinutes(l10n, slot.slot.minutes)}'),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: theme.textTheme.labelLarge?.copyWith(color: color)),
          const SizedBox(width: 6),
          Icon(icon, color: color, size: 20),
        ]),
      ),
    );
  }
}

/// Une seance en plus du programme.
class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session, required this.ledger, required this.onLongPress});

  final SportSession session;
  final SportLedger ledger;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sport = ledger.sportById(session.sportId);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onLongPress: onLongPress,
        leading: SportAvatar(sport: sport, color: sportColor(scheme, ledger.sports, session.sportId)),
        title: Text(sportLabel(l10n, sport)),
        subtitle: Text(SportFormat(context).shortDay(session.date)),
        trailing: Text(
          sportMinutes(l10n, session.minutes),
          style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary),
        ),
      ),
    );
  }
}

class _EmptyPlan extends StatelessWidget {
  const _EmptyPlan({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant, width: 1.5),
      ),
      child: Column(children: [
        Text(l10n.sport_plan_empty, style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        Text(
          l10n.sport_plan_empty_hint,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
        ),
        const SizedBox(height: 12),
        FilledButton.tonal(onPressed: onOpen, child: Text(l10n.sport_plan_prepare)),
      ]),
    );
  }
}

/// Le temps passe sur chaque sport, sur la semaine affichee, le mois en
/// cours ou depuis le debut.
class _BySportCard extends StatelessWidget {
  const _BySportCard({
    required this.ledger,
    required this.period,
    required this.monday,
    required this.today,
    required this.onPeriod,
  });

  final SportLedger ledger;
  final _Period period;
  final DateTime monday;
  final DateTime today;
  final ValueChanged<_Period> onPeriod;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final totals = switch (period) {
      _Period.week => ledger.totalsBySport(from: monday, to: dayOfWeek(monday, 7)),
      _Period.month => ledger.totalsBySport(from: DateTime(today.year, today.month), to: today),
      _Period.all => ledger.totalsBySport(),
    };
    final max = totals.isEmpty ? 0 : totals.first.minutes;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(l10n.sport_by_sport, style: theme.textTheme.titleSmall),
        const SizedBox(height: 10),
        SegmentedButton<_Period>(
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: [
            ButtonSegment(value: _Period.week, label: Text(l10n.sport_period_week)),
            ButtonSegment(value: _Period.month, label: Text(l10n.sport_period_month)),
            ButtonSegment(value: _Period.all, label: Text(l10n.goals_rate_window_all)),
          ],
          selected: {period},
          onSelectionChanged: (selection) => onPeriod(selection.first),
        ),
        const SizedBox(height: 12),
        if (totals.isEmpty)
          Text(
            l10n.sport_by_sport_empty,
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
          )
        else
          for (final total in totals)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                SportAvatar(
                  sport: ledger.sportById(total.sportId),
                  color: sportColor(scheme, ledger.sports, total.sportId),
                  size: 30,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      Expanded(
                        child: Text(
                          sportLabel(l10n, ledger.sportById(total.sportId)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      Text(
                        '${sportMinutes(l10n, total.minutes)} · ${l10n.sport_sessions_short(total.sessions)}',
                        style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: max <= 0 ? 0 : total.minutes / max,
                        minHeight: 6,
                        color: sportColor(scheme, ledger.sports, total.sportId),
                        backgroundColor: scheme.surfaceContainerHighest,
                      ),
                    ),
                  ]),
                ),
              ]),
            ),
      ]),
    );
  }
}
