import 'package:flutter/material.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/commute_dao.dart';
import 'package:i_zerak_app/pages/commute/commute_import_page.dart';
import 'package:i_zerak_app/pages/commute/commute_page.dart';
import 'package:i_zerak_app/pages/commute/widgets/commute_ui.dart';
import 'package:i_zerak_app/services/commute_price_service.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_commute.dart';
import 'package:i_zerak_app/services/timeline_import.dart';

/// Ce qui a ete choisi dans la feuille d'un jour.
sealed class _DayChoice {
  const _DayChoice();
}

class _Bike extends _DayChoice {
  const _Bike();
}

class _Car extends _DayChoice {
  const _Car(this.reason);
  final CarReason reason;
}

class _Clear extends _DayChoice {
  const _Clear();
}

/// Le mois en calendrier, et de quoi corriger ou rattraper une journee.
class CommuteHistoryPage extends StatefulWidget {
  const CommuteHistoryPage({
    super.key,
    required this.store,
    required this.prices,
    required this.clock,
  });

  final ICommute store;
  final CommutePriceService prices;
  final DateTime Function() clock;

  @override
  State<CommuteHistoryPage> createState() => _CommuteHistoryPageState();
}

class _CommuteHistoryPageState extends State<CommuteHistoryPage> {
  late DateTime _month = _firstOfMonth(widget.clock());
  CommuteSettings _settings = const CommuteSettings();
  CommuteLedger _ledger = CommuteLedger(const [], const []);
  bool _loading = true;
  bool _reading = false;

  static DateTime _firstOfMonth(DateTime day) => DateTime(day.year, day.month);

  DateTime get _today => dateOnly(widget.clock());

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final settings = await widget.store.readSettings();
    final days = await widget.store.getDays();
    final goals = await widget.store.getGoals();
    if (!mounted) {
      return;
    }
    setState(() {
      _settings = settings;
      _ledger = CommuteLedger(days, goals);
      _loading = false;
    });
  }

  void _shiftMonth(int delta) =>
      setState(() => _month = DateTime(_month.year, _month.month + delta));

  /// Corrige une journee passee, ou en rattrape une oubliee.
  ///
  /// Le prix retenu est le dernier releve au plus tard ce jour-la : l'API ne
  /// publie que les prix de l'instant, et valoriser un jour d'aout au prix de
  /// septembre fausserait la cagnotte.
  Future<void> _editDay(DateTime date) async {
    final l10n = AppLocalizations.of(context)!;
    final format = CommuteFormat(context);
    final existing = _ledger.dayOn(date);

    final choice = await showModalBottomSheet<_DayChoice>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return CommuteSheet(children: [
          Text(_capitalize(format.longDay(date)), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ListTile(
            leading: Icon(Icons.pedal_bike, color: scheme.primary),
            title: Text(l10n.commute_by_bike),
            selected: existing?.isBike ?? false,
            onTap: () => Navigator.pop(context, const _Bike()),
          ),
          for (final reason in _settings.reasons)
            ListTile(
              leading: Icon(Icons.directions_car_outlined, color: bucketColor(scheme, reason.bucket)),
              title: Text(carReasonLabel(l10n, reason)),
              subtitle: Text(reason.bucket == CarBucket.missed
                  ? l10n.commute_bucket_missed
                  : l10n.commute_bucket_essential),
              selected: existing?.reasonId == reason.id,
              onTap: () => Navigator.pop(context, _Car(reason)),
            ),
          if (existing != null)
            ListTile(
              leading: Icon(Icons.delete_outline, color: scheme.error),
              title: Text(l10n.commute_clear_day, style: TextStyle(color: scheme.error)),
              onTap: () => Navigator.pop(context, const _Clear()),
            ),
        ]);
      },
    );
    if (choice == null) {
      return;
    }

    switch (choice) {
      case _Clear():
        await widget.store.deleteDay(date);
      case _Bike():
        final price = await widget.prices.resolve(_settings.fuel, day: date);
        await widget.store.saveDay(CommuteDay.bike(date, _settings, price));
      case _Car(:final reason):
        final price = await widget.prices.resolve(_settings.fuel, day: date);
        await widget.store.saveDay(CommuteDay.car(date, _settings, price, reason));
    }
    await _reload();
  }

  Future<void> _importTimeline() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    void say(String message) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));

    final List<TimelineBikeDay>? found;
    setState(() => _reading = true);
    try {
      found = await pickTimelineBikeDays();
    } on TimelineFormatException {
      say(l10n.commute_import_invalid);
      return;
    } finally {
      if (mounted) {
        setState(() => _reading = false);
      }
    }
    if (found == null || !mounted) {
      return;
    }
    if (found.isEmpty) {
      say(l10n.commute_import_empty);
      return;
    }

    final count = await Navigator.push<int>(
      context,
      MaterialPageRoute(
        builder: (_) => CommuteImportPage(
          found: found!,
          store: widget.store,
          prices: widget.prices,
          clock: widget.clock,
        ),
      ),
    );
    await _reload();
    if (count != null && count > 0) {
      say(l10n.commute_import_done(count));
    }
  }

  static String _capitalize(String text) =>
      text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = CommuteFormat(context);
    final today = _today;
    final isCurrentMonth = _month == _firstOfMonth(today);
    final totals = _ledger.monthTotals(_month.year, _month.month);
    final monthDays = [
      for (final day in _ledger.days)
        if (day.date.year == _month.year && day.date.month == _month.month) day,
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.commute_history_title),
        actions: [
          IconButton(
            tooltip: l10n.commute_import,
            icon: const Icon(Icons.upload_file),
            onPressed: _reading ? null : _importTimeline,
          ),
        ],
        // L'export pese plusieurs dizaines de Mo : sa lecture prend un moment.
        bottom: _reading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(4),
                child: LinearProgressIndicator(),
              )
            : null,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              children: [
                Row(children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    tooltip: MaterialLocalizations.of(context).previousMonthTooltip,
                    onPressed: () => _shiftMonth(-1),
                  ),
                  Expanded(
                    child: Text(format.month(_month),
                        textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    tooltip: MaterialLocalizations.of(context).nextMonthTooltip,
                    onPressed: isCurrentMonth ? null : () => _shiftMonth(1),
                  ),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  _MonthTotal(
                    label: l10n.commute_legend_bike,
                    amount: totals.bike,
                    days: totals.bikeDays,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 8),
                  _MonthTotal(
                    label: l10n.commute_legend_essential,
                    amount: totals.essential,
                    days: totals.essentialDays,
                    color: scheme.secondary,
                  ),
                  const SizedBox(width: 8),
                  _MonthTotal(
                    label: l10n.commute_legend_missed,
                    amount: totals.missed,
                    days: totals.missedDays,
                    color: scheme.tertiary,
                  ),
                ]),
                const SizedBox(height: 16),
                _calendar(context, format, today),
                const SizedBox(height: 12),
                Wrap(spacing: 14, runSpacing: 6, children: [
                  _Legend(color: scheme.primaryContainer, label: l10n.commute_legend_bike),
                  _Legend(color: scheme.secondaryContainer, label: l10n.commute_legend_essential),
                  _Legend(color: scheme.tertiaryContainer, label: l10n.commute_legend_missed),
                ]),
                const SizedBox(height: 8),
                Text(l10n.commute_history_hint,
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline)),
                const SizedBox(height: 8),
                for (final day in monthDays) ...[
                  CommuteDayRow(
                    day: day,
                    reasons: _settings.reasons,
                    today: today,
                    onTap: () => _editDay(day.date),
                  ),
                  Divider(height: 1, color: scheme.surfaceContainerHigh),
                ],
                if (_ledger.validatedGoals.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text(l10n.commute_validated_goals, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  for (final goal in _ledger.validatedGoals)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        goal.kind == GoalKind.milestone ? Icons.flag_outlined : goalIconData(goal.icon),
                        color: goalColor(scheme, goal.kind),
                      ),
                      title: Text(goal.name),
                      subtitle: Text(l10n.commute_validated_on(
                          format.euros(goal.target), format.dayMonth(goal.validatedAt!))),
                    ),
                ],
              ],
            ),
    );
  }

  Widget _calendar(BuildContext context, CommuteFormat format, DateTime today) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    // Lundi en tete : `weekday` vaut 1 le lundi.
    final leading = _month.weekday - 1;
    final cells = leading + daysInMonth;

    return Column(children: [
      Row(children: [
        for (final (index, initial) in format.weekdayInitials().indexed)
          Expanded(
            child: Center(
              child: Text(initial,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: index >= 5 ? scheme.outlineVariant : scheme.outline,
                  )),
            ),
          ),
      ]),
      const SizedBox(height: 6),
      GridView.count(
        crossAxisCount: 7,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        children: [
          for (var i = 0; i < cells; i++)
            if (i < leading)
              const SizedBox.shrink()
            else
              _DayCell(
                date: DateTime(_month.year, _month.month, i - leading + 1),
                today: today,
                day: _ledger.dayOn(DateTime(_month.year, _month.month, i - leading + 1)),
                onTap: _editDay,
              ),
        ],
      ),
    ]);
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.date, required this.today, required this.day, required this.onTap});

  final DateTime date;
  final DateTime today;
  final CommuteDay? day;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final future = date.isAfter(today);
    final weekend = date.weekday >= DateTime.saturday;
    final colors = day == null ? null : dayContainerColors(scheme, day!);

    final Color foreground;
    if (colors != null) {
      foreground = colors.foreground;
    } else if (future) {
      foreground = scheme.outlineVariant;
    } else {
      foreground = weekend ? scheme.outline : scheme.onSurfaceVariant;
    }

    return Material(
      color: colors?.background ?? Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: date == today ? BorderSide(color: scheme.primary, width: 2) : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // Un jour a venir ne se renseigne pas : le prix n'existe pas encore.
        onTap: future ? null : () => onTap(date),
        child: Center(
          child: Text(
            '${date.day}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: foreground,
              fontWeight: day != null || date == today ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

class _MonthTotal extends StatelessWidget {
  const _MonthTotal({
    required this.label,
    required this.amount,
    required this.days,
    required this.color,
  });

  final String label;
  final double amount;
  final int days;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration:
            BoxDecoration(color: scheme.surfaceContainer, borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(CommuteFormat(context).euros(amount),
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: color)),
          ),
          Text(l10n.commute_days(days),
              style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline)),
        ]),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
      ),
      const SizedBox(width: 6),
      Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    ]);
  }
}
