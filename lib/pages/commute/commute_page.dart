import 'package:flutter/material.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/commute_dao.dart';
import 'package:i_zerak_app/pages/commute/commute_history_page.dart';
import 'package:i_zerak_app/pages/commute/commute_settings_page.dart';
import 'package:i_zerak_app/pages/commute/widgets/car_reason_sheet.dart';
import 'package:i_zerak_app/pages/commute/widgets/commute_ui.dart';
import 'package:i_zerak_app/pages/commute/widgets/goal_sheets.dart';
import 'package:i_zerak_app/pages/commute/widgets/pot_carousel.dart';
import 'package:i_zerak_app/pages/gas_stations/widgets/fuel_label.dart';
import 'package:i_zerak_app/services/commute_price_service.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_commute.dart';
import 'package:i_zerak_app/services/service_locator.dart';

/// L'onglet Velo : un appui par jour, a velo ou en voiture, et ce que ca
/// rapporte.
class CommutePage extends StatefulWidget {
  CommutePage({
    super.key,
    ICommute? store,
    CommutePriceService? prices,
    DateTime Function()? clock,
  })  : store = store ?? getIt<ICommute>(),
        prices = prices ?? getIt<CommutePriceService>(),
        clock = clock ?? DateTime.now;

  final ICommute store;
  final CommutePriceService prices;
  final DateTime Function() clock;

  @override
  State<CommutePage> createState() => _CommutePageState();
}

class _CommutePageState extends State<CommutePage> {
  CommuteSettings _settings = const CommuteSettings();
  CommuteLedger _ledger = CommuteLedger(const [], const []);

  /// Prix du jour. Nul tant que la premiere resolution n'est pas revenue : les
  /// journees s'affichent sans l'attendre.
  ResolvedPrice? _price;
  DateTime? _priceDay;

  bool _loading = true;
  bool _busy = false;

  DateTime get _today => dateOnly(widget.clock());

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _reload();
    await _refreshPrice();
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

  Future<void> _refreshPrice() async {
    final today = _today;
    final price = await widget.prices.resolve(_settings.fuel, day: today);
    if (!mounted) {
      return;
    }
    setState(() {
      _price = price;
      _priceDay = today;
    });
  }

  /// Le prix deja resolu s'il date d'aujourd'hui : l'appui repond tout de
  /// suite, sans aller-retour reseau. L'onglet reste parfois ouvert jusqu'au
  /// lendemain, d'ou la verification du jour.
  Future<ResolvedPrice> _todayPrice() async {
    if (_price == null || _priceDay != _today) {
      await _refreshPrice();
    }
    return _price ?? const ResolvedPrice.fallback();
  }

  Future<void> _guard(Future<void> Function() action) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _recordBike() => _guard(() async {
        final l10n = AppLocalizations.of(context)!;
        final format = CommuteFormat(context);
        final day = CommuteDay.bike(_today, _settings, await _todayPrice());
        await widget.store.saveDay(day);
        await _reload();
        _confirm(l10n.commute_snack_bike(format.euros(day.amount)));
      });

  Future<void> _recordCar() => _guard(() async {
        final l10n = AppLocalizations.of(context)!;
        final format = CommuteFormat(context);
        final price = await _todayPrice();
        if (!mounted) {
          return;
        }
        final reason = await showCarReasonSheet(
          context,
          reasons: _settings.reasons,
          subtitle: l10n.commute_why_car_detail(
            format.longDay(_today),
            format.euros(_settings.tripValue(price.pricePerLitre)),
          ),
          onAddReason: _addReason,
        );
        if (reason == null) {
          return;
        }
        final day = CommuteDay.car(_today, _settings, price, reason);
        await widget.store.saveDay(day);
        await _reload();
        if (mounted) {
          _confirm(l10n.commute_snack_car(carReasonLabel(l10n, reason)));
        }
      });

  Future<CarReason?> _addReason() async {
    final reason = await showAddReasonDialog(context);
    if (reason == null) {
      return null;
    }
    final settings = _settings.copyWith(reasons: [..._settings.reasons, reason]);
    await widget.store.saveSettings(settings);
    if (mounted) {
      setState(() => _settings = settings);
    }
    return reason;
  }

  /// Simple accuse de reception : l'annulation se fait depuis la carte du jour,
  /// qui reste affichee. Une action rend une snackbar persistante par defaut,
  /// d'ou `persist: false` pour qu'elle parte seule.
  void _confirm(String message) {
    if (!mounted) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
        persist: false,
        action: SnackBarAction(label: l10n.ok, onPressed: messenger.hideCurrentSnackBar),
      ));
  }

  Future<void> _undo(DateTime date) async {
    await widget.store.deleteDay(date);
    await _reload();
  }

  Future<void> _newGoal() async {
    final goal = await showNewGoalSheet(context, ledger: _ledger, tripValue: _tripValue);
    if (goal == null) {
      return;
    }
    await widget.store.saveGoal(goal);
    await _reload();
  }

  Future<void> _validateGoal(Goal goal) async {
    final confirmed = await showValidateGoalSheet(context, goal: goal, ledger: _ledger);
    // Relu apres la feuille : un trajet annule entre-temps pourrait avoir fait
    // repasser l'achat sous son montant.
    if (!confirmed || !_ledger.progressOf(goal).reached) {
      return;
    }
    await widget.store.saveGoal(goal.validated(widget.clock()));
    await _reload();
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
    if (confirmed != true) {
      return;
    }
    await widget.store.deleteGoal(goal.id);
    await _reload();
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CommuteSettingsPage(store: widget.store, prices: widget.prices),
      ),
    );
    final fuel = _settings.fuel;
    await _reload();
    // Un autre carburant, un autre prix.
    if (_settings.fuel != fuel) {
      await _refreshPrice();
    }
  }

  Future<void> _openHistory() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CommuteHistoryPage(
          store: widget.store,
          prices: widget.prices,
          clock: widget.clock,
        ),
      ),
    );
    await _reload();
  }

  double get _tripValue =>
      _price == null ? 0 : _settings.tripValue(_price!.pricePerLitre);

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final today = _today;
    final recorded = _ledger.dayOn(today);

    return RefreshIndicator(
      onRefresh: _refreshPrice,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          PotCarousel(
            ledger: _ledger,
            today: today,
            tripValue: _tripValue,
            onValidate: _validateGoal,
            onNewGoal: _newGoal,
            onDeleteGoal: _deleteGoal,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const SizedBox(height: 16),
              if (!_settings.isConfigured)
                _SetupCard(onSetup: _openSettings)
              else if (recorded != null)
                _RecordedCard(
                  day: recorded,
                  reasons: _settings.reasons,
                  onUndo: () => _undo(recorded.date),
                )
              else
                _TodayActions(
                  today: today,
                  tripValue: _price == null ? null : _tripValue,
                  busy: _busy,
                  onBike: _recordBike,
                  onCar: _recordCar,
                ),
              const SizedBox(height: 12),
              _BucketTotals(totals: _ledger.totals),
              const SizedBox(height: 12),
              if (_price != null)
                _PriceCard(
                  price: _price!,
                  fuelLabel: fuelLabel(AppLocalizations.of(context)!, _settings.fuel),
                  tripValue: _settings.isConfigured ? _tripValue : null,
                  onTap: _openSettings,
                ),
              const SizedBox(height: 8),
              _RecentDays(
                ledger: _ledger,
                reasons: _settings.reasons,
                today: today,
                onSeeAll: _openHistory,
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _TodayActions extends StatelessWidget {
  const _TodayActions({
    required this.today,
    required this.tripValue,
    required this.busy,
    required this.onBike,
    required this.onCar,
  });

  final DateTime today;

  /// Nulle tant que le prix du jour n'est pas connu.
  final double? tripValue;

  final bool busy;
  final VoidCallback onBike;
  final VoidCallback onCar;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = CommuteFormat(context);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: Text(l10n.commute_today(format.longDay(today)),
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
        ),
        Text(l10n.commute_nothing_today,
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline)),
      ]),
      const SizedBox(height: 10),
      SizedBox(
        height: 68,
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            flex: 16,
            child: FilledButton(
              onPressed: busy ? null : onBike,
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.centerLeft,
              ),
              child: Row(children: [
                const Icon(Icons.pedal_bike, size: 26),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.commute_by_bike,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      if (tripValue != null)
                        Text(l10n.commute_by_bike_gain(format.euros(tripValue!)),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w400)),
                    ],
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 10,
            child: OutlinedButton(
              onPressed: busy ? null : onCar,
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                foregroundColor: scheme.onSurface,
                side: BorderSide(color: scheme.outline),
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.directions_car_outlined),
                const SizedBox(height: 4),
                Text(l10n.commute_by_car, maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
          ),
        ]),
      ),
    ]);
  }
}

class _RecordedCard extends StatelessWidget {
  const _RecordedCard({required this.day, required this.reasons, required this.onUndo});

  final CommuteDay day;
  final List<CarReason> reasons;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = CommuteFormat(context);
    final colors = dayContainerColors(scheme, day);
    final amount = day.isBike ? '+ ${format.euros(day.amount)}' : format.euros(day.amount);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(color: colors.background, borderRadius: BorderRadius.circular(20)),
      child: Row(children: [
        CircleAvatar(
          radius: 17,
          backgroundColor: colors.foreground,
          foregroundColor: colors.background,
          child: Icon(day.isBike ? Icons.check : Icons.directions_car_outlined, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              day.isBike ? l10n.commute_recorded_bike : l10n.commute_recorded_car(dayLabel(l10n, day, reasons)),
              style: theme.textTheme.titleSmall?.copyWith(color: colors.foreground),
            ),
            Text(
              l10n.commute_recorded_detail(amount, format.longDay(day.date)),
              style: theme.textTheme.bodySmall?.copyWith(color: colors.foreground),
            ),
          ]),
        ),
        OutlinedButton(
          onPressed: onUndo,
          style: OutlinedButton.styleFrom(
            foregroundColor: colors.foreground,
            side: BorderSide(color: colors.foreground),
          ),
          child: Text(l10n.commute_undo),
        ),
      ]),
    );
  }
}

class _SetupCard extends StatelessWidget {
  const _SetupCard({required this.onSetup});

  final VoidCallback onSetup;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l10n.commute_setup_title,
            style: theme.textTheme.titleMedium?.copyWith(color: scheme.onPrimaryContainer)),
        const SizedBox(height: 4),
        Text(l10n.commute_setup_hint,
            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onPrimaryContainer)),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: onSetup,
          icon: const Icon(Icons.tune),
          label: Text(l10n.commute_setup_action),
        ),
      ]),
    );
  }
}

class _BucketTotals extends StatelessWidget {
  const _BucketTotals({required this.totals});

  final CommuteTotals totals;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        child: _TotalCard(
          label: l10n.commute_essential,
          amount: totals.essential,
          days: totals.essentialDays,
          color: scheme.secondary,
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: _TotalCard(
          label: l10n.commute_missed,
          amount: totals.missed,
          days: totals.missedDays,
          color: scheme.tertiary,
        ),
      ),
    ]);
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration:
          BoxDecoration(color: scheme.surfaceContainer, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
          ),
        ]),
        const SizedBox(height: 4),
        Text(CommuteFormat(context).euros(amount),
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: color)),
        Text(l10n.commute_days(days),
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline)),
      ]),
    );
  }
}

class _PriceCard extends StatelessWidget {
  const _PriceCard({
    required this.price,
    required this.fuelLabel,
    required this.tripValue,
    required this.onTap,
  });

  final ResolvedPrice price;
  final String fuelLabel;
  final double? tripValue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = CommuteFormat(context);
    final perLitre = format.perLitre(price.pricePerLitre);

    final (String title, String? detail) = switch (price.source) {
      PriceSource.live => (l10n.commute_price_live(fuelLabel, perLitre), price.stationLabel),
      PriceSource.lastKnown => (
          l10n.commute_price_last_known(perLitre),
          price.observedOn == null
              ? price.stationLabel
              : l10n.commute_price_last_known_detail(format.dayMonth(price.observedOn!)),
        ),
      PriceSource.fallback => (
          l10n.commute_price_fallback(perLitre),
          l10n.commute_price_fallback_detail
        ),
    };

    return Material(
      color: scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            Icon(
              price.source == PriceSource.live ? Icons.local_gas_station : Icons.history,
              size: 20,
              color: price.source == PriceSource.live ? scheme.onSurfaceVariant : scheme.tertiary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                if (detail != null)
                  Text(detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline)),
              ]),
            ),
            if (tripValue != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(format.euros(tripValue!),
                    style: theme.textTheme.labelLarge?.copyWith(color: scheme.onPrimaryContainer)),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

class _RecentDays extends StatelessWidget {
  const _RecentDays({
    required this.ledger,
    required this.reasons,
    required this.today,
    required this.onSeeAll,
  });

  final CommuteLedger ledger;
  final List<CarReason> reasons;
  final DateTime today;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final days = ledger.days.take(5).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text(l10n.commute_recent, style: theme.textTheme.titleSmall)),
        TextButton(onPressed: onSeeAll, child: Text(l10n.commute_see_all)),
      ]),
      for (final day in days) ...[
        CommuteDayRow(day: day, reasons: reasons, today: today),
        if (day != days.last) Divider(height: 1, color: theme.colorScheme.surfaceContainerHigh),
      ],
    ]);
  }
}

/// Une ligne de journee, reprise dans l'historique.
class CommuteDayRow extends StatelessWidget {
  const CommuteDayRow({
    super.key,
    required this.day,
    required this.reasons,
    required this.today,
    this.onTap,
  });

  final CommuteDay day;
  final List<CarReason> reasons;
  final DateTime today;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = CommuteFormat(context);
    final color = dayColor(scheme, day);
    final isToday = day.date == today;

    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 44,
        child: Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isToday ? l10n.commute_today_short : format.shortDay(day.date),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: isToday ? FontWeight.w500 : FontWeight.w400),
            ),
          ),
          Text(dayLabel(l10n, day, reasons), style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline)),
          SizedBox(
            width: 72,
            child: Text(
              day.isBike ? '+ ${format.euros(day.amount)}' : format.euros(day.amount),
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500, color: color),
            ),
          ),
          if (onTap != null) Icon(Icons.chevron_right, size: 18, color: scheme.outline),
        ]),
      ),
    );
  }
}
