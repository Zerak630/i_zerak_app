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

  /// Une confirmation breve, qui s'efface seule : le geste est deja fait, et le
  /// bandeau ne doit pas attendre qu'on s'en occupe.
  void _confirm(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: AppLocalizations.of(context)!.ok,
          onPressed: messenger.hideCurrentSnackBar,
        ),
      ));
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
      _confirm(result == SubscriptionSheetResult.deleted ? l10n.sub_deleted : l10n.sub_saved);
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
          if (totals.length > 1) ...[
            _filters(context, l10n, ledger, totals, filter),
            const SizedBox(height: 10),
          ],
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
      child: ListTile(
        onTap: _openPayments,
        leading: const Icon(Icons.event_outlined),
        title: Text(
          days <= 1 ? '$title · ${format.shortDay(next.date)}' : title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          others == 0
              ? next.subscription.name
              : '${next.subscription.name} · ${l10n.sub_more_this_month(others)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Chip(
          label: Text(format.euros(next.amount)),
          backgroundColor: scheme.primaryContainer,
          labelStyle: theme.textTheme.labelLarge?.copyWith(color: scheme.onPrimaryContainer),
          side: BorderSide.none,
        ),
      ),
    );
  }

  Widget _filters(
    BuildContext context,
    AppLocalizations l10n,
    SubscriptionLedger ledger,
    List<CategoryTotal> totals,
    String? filter,
  ) =>
      SizedBox(
        height: 36,
        // Une rangee defilante, et non une `ListView` : avec une poignee de
        // categories, tout construire d'un coup evite qu'une puce hors ecran
        // n'existe pas encore quand on la cherche.
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            ChoiceChip(
              selected: filter == null,
              onSelected: (_) => setState(() => _filter = null),
              label: Text(l10n.sub_filter_all(ledger.active.length)),
            ),
            for (final total in totals) ...[
              const SizedBox(width: 8),
              ChoiceChip(
                selected: filter == total.categoryId,
                onSelected: (selected) =>
                    setState(() => _filter = selected ? total.categoryId : null),
                avatar: CircleAvatar(
                  radius: 5,
                  backgroundColor: subscriptionColor(context, total.categoryId, _categories),
                ),
                label: Text(categoryLabelOf(l10n, total.categoryId, _categories)),
              ),
            ],
          ]),
        ),
      );

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
