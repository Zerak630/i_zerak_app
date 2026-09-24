import 'package:flutter/material.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/subscription_dao.dart';
import 'package:i_zerak_app/pages/subscriptions/subscription_payments_page.dart';
import 'package:i_zerak_app/pages/subscriptions/widgets/category_breakdown.dart';
import 'package:i_zerak_app/pages/subscriptions/widgets/subscription_row.dart';
import 'package:i_zerak_app/pages/subscriptions/widgets/subscription_sheet.dart';
import 'package:i_zerak_app/pages/subscriptions/widgets/subscription_ui.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_subscriptions.dart';
import 'package:i_zerak_app/services/service_locator.dart';
import 'package:i_zerak_app/utils/confirmation_snack_bar.dart';

/// L'onglet Abonnements.
///
/// Un seul chiffre mis en avant, et un selecteur qui change l'unite de toute la
/// page : sans lui, 18 € par semaine et 720 € par an restent incomparables.
class SubscriptionsPage extends StatefulWidget {
  SubscriptionsPage({super.key, ISubscriptions? subscriptionService, DateTime Function()? clock})
      : subscriptionService = subscriptionService ?? getIt<ISubscriptions>(),
        clock = clock ?? DateTime.now;

  final ISubscriptions subscriptionService;
  final DateTime Function() clock;

  @override
  State<SubscriptionsPage> createState() => _SubscriptionsPageState();
}

class _SubscriptionsPageState extends State<SubscriptionsPage> {
  List<Subscription> _subscriptions = const [];
  List<SubscriptionCategory> _categories = const [];
  Object? _error;
  bool _loading = true;

  SubscriptionFrequency _unit = SubscriptionFrequency.monthly;
  bool _expanded = false;
  String? _filter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final subscriptions = await widget.subscriptionService.getAll();
      final categories = await widget.subscriptionService.getCategories();
      if (!mounted) {
        return;
      }
      setState(() {
        _subscriptions = subscriptions;
        _categories = categories;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  Future<void> _edit([Subscription? subscription]) async {
    final l10n = AppLocalizations.of(context)!;
    final result = await showSubscriptionSheet(
      context,
      subscription: subscription,
      store: widget.subscriptionService,
      categories: _categories,
      clock: widget.clock,
    );
    if (result == null || !mounted) {
      return;
    }
    await _load();
    if (mounted) {
      showConfirmation(
        context,
        result == SubscriptionSheetResult.deleted ? l10n.sub_deleted : l10n.sub_saved,
      );
    }
  }

  Future<void> _openPayments() => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SubscriptionPaymentsPage(
            subscriptionService: widget.subscriptionService,
            clock: widget.clock,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      body: _body(context, l10n),
      floatingActionButton: _loading
          ? null
          : FloatingActionButton(
              onPressed: () => _edit(),
              tooltip: l10n.add_subscription,
              child: const Icon(Icons.add),
            ),
    );
  }

  Widget _body(BuildContext context, AppLocalizations l10n) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(l10n.loading_error(_error.toString())));
    }
    if (_subscriptions.isEmpty) {
      return _empty(context, l10n);
    }

    final ledger = SubscriptionLedger(_subscriptions);
    final totals = ledger.byCategory(_unit);
    // Un filtre dont la categorie n'a plus d'abonnement ne doit pas vider la
    // liste sans explication : il retombe alors sur « toutes ».
    final filter = totals.any((total) => total.categoryId == _filter) ? _filter : null;
    final visible = filter == null
        ? ledger.active
        : [
            for (final subscription in ledger.active)
              if (subscription.categoryId == filter) subscription,
          ];

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        children: [
          _header(context, l10n, ledger, totals),
          const SizedBox(height: 12),
          _nextPayment(context, l10n, ledger),
          const SizedBox(height: 14),
          _listHeader(context, l10n, visible, filter),
          for (final subscription in visible) ...[
            SubscriptionRow(
              key: ValueKey(subscription.id),
              subscription: subscription,
              unit: _unit,
              categories: _categories,
              onTap: () => _edit(subscription),
            ),
            if (subscription != visible.last) const Divider(height: 1),
          ],
          if (ledger.suspended.isNotEmpty) _suspended(context, l10n, ledger),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.subscriptions_outlined, size: 48, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text(l10n.no_subscription, style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            l10n.sub_empty_hint,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
          ),
        ]),
      ),
    );
  }

  Widget _header(
    BuildContext context,
    AppLocalizations l10n,
    SubscriptionLedger ledger,
    List<CategoryTotal> totals,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = SubscriptionFormat(context);
    final heaviest = ledger.active.isEmpty ? null : ledger.active.first;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            costTitle(l10n, _unit).toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              format.euros(ledger.totalIn(_unit)),
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: scheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            [
              l10n.sub_active_count(ledger.active.length),
              if (ledger.suspended.isNotEmpty) l10n.sub_suspended_count(ledger.suspended.length),
            ].join(' · '),
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          SegmentedButton<SubscriptionFrequency>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: [
              for (final unit in SubscriptionFrequency.values)
                ButtonSegment(value: unit, label: Text(unitShortLabel(l10n, unit))),
            ],
            selected: {_unit},
            onSelectionChanged: (selection) => setState(() => _unit = selection.first),
          ),
          const SizedBox(height: 10),
          CategoryBreakdown(
            totals: totals,
            categories: _categories,
            unit: _unit,
            expanded: _expanded,
            onToggle: () => setState(() => _expanded = !_expanded),
            selectedCategoryId: _filter,
            onSelect: (categoryId) => setState(() => _filter = categoryId),
          ),
          if (_expanded && heaviest != null) ...[
            const SizedBox(height: 10),
            Text(
              l10n.sub_heaviest(
                heaviest.name,
                format.euros(heaviest.amountIn(SubscriptionFrequency.yearly)),
              ),
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
            ),
          ],
        ]),
      ),
    );
  }

  /// Le prochain prelevement, et ce qui reste a tomber ce mois-ci.
  Widget _nextPayment(BuildContext context, AppLocalizations l10n, SubscriptionLedger ledger) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = SubscriptionFormat(context);
    final today = dateOnly(widget.clock());
    final endOfMonth = DateTime(today.year, today.month, daysInMonth(today.year, today.month));
    final upcoming = ledger.paymentsIn(today, endOfMonth);
    final next = upcoming.isEmpty ? null : upcoming.first;

    if (next == null) {
      return Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          leading: const Icon(Icons.event_outlined),
          title: Text(l10n.sub_no_upcoming),
          subtitle: Text(l10n.sub_no_upcoming_hint),
          onTap: _openPayments,
        ),
      );
    }

    final days = next.date.difference(today).inDays;
    final title = switch (days) {
      0 => l10n.sub_today,
      1 => l10n.sub_tomorrow,
      _ => SubscriptionFormat(context).longDay(next.date),
    };
    final others = upcoming.length - 1;

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: _openPayments,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(children: [
            Icon(Icons.event_outlined, color: scheme.onSurfaceVariant),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // La carte disait quand et combien, jamais de quoi il
                // s'agissait : le titre porte desormais son nom.
                Text(
                  l10n.sub_next_payment,
                  style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 3),
                Text(
                  days <= 1 ? '$title · ${format.shortDay(next.date)}' : title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 2),
                Text(
                  others == 0
                      ? next.subscription.name
                      : '${next.subscription.name} · ${l10n.sub_more_this_month(others)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
                ),
              ]),
            ),
            const SizedBox(width: 10),
            Chip(
              label: Text(format.euros(next.amount)),
              backgroundColor: scheme.primaryContainer,
              labelStyle: theme.textTheme.labelLarge?.copyWith(color: scheme.onPrimaryContainer),
              side: BorderSide.none,
            ),
          ]),
        ),
      ),
    );
  }

  Widget _listHeader(
    BuildContext context,
    AppLocalizations l10n,
    List<Subscription> visible,
    String? filter,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = SubscriptionFormat(context);
    final total = visible.fold(0.0, (sum, item) => sum + item.amountIn(_unit));

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(children: [
        Expanded(
          child: Text(
            filter == null
                ? l10n.sub_sorted_by_cost
                : '${categoryLabelOf(l10n, filter, _categories)} · '
                    '${l10n.sub_active_count(visible.length)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          filter == null
              ? unitLabel(l10n, _unit)
              : '${format.euros(total)} ${unitLabel(l10n, _unit)}',
          style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline),
        ),
        // La sortie du filtre : il se pose depuis le detail deplie, qui peut
        // etre referme entre-temps. Sans ce bouton, la liste resterait
        // amputee sans moyen visible de la completer.
        if (filter != null)
          IconButton(
            onPressed: () => setState(() => _filter = null),
            icon: const Icon(Icons.close, size: 18),
            visualDensity: VisualDensity.compact,
            tooltip: l10n.sub_clear_filter,
          ),
      ]),
    );
  }

  Widget _suspended(BuildContext context, AppLocalizations l10n, SubscriptionLedger ledger) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = SubscriptionFormat(context);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 22),
      Row(children: [
        Text(
          '${l10n.sub_suspended_section} · ${ledger.suspended.length}',
          style: theme.textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(width: 10),
        const Expanded(child: Divider(height: 1)),
        const SizedBox(width: 10),
        Text(
          l10n.sub_out_of_totals,
          style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline),
        ),
      ]),
      for (final subscription in ledger.suspended)
        SubscriptionRow(
          key: ValueKey(subscription.id),
          subscription: subscription,
          unit: _unit,
          categories: _categories,
          onTap: () => _edit(subscription),
        ),
      const SizedBox(height: 6),
      Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            Expanded(
              child: Text(l10n.sub_if_resumed, style: theme.textTheme.bodySmall),
            ),
            Text(
              '${format.euros(ledger.totalIn(_unit) + ledger.suspendedTotalIn(_unit))} '
              '${unitLabel(l10n, _unit)}',
              style: theme.textTheme.labelLarge?.copyWith(color: scheme.secondary),
            ),
          ]),
        ),
      ),
    ]);
  }
}
