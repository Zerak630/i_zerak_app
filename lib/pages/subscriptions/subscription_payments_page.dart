import 'package:flutter/material.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/subscription_dao.dart';
import 'package:i_zerak_app/pages/subscriptions/widgets/subscription_ui.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_subscriptions.dart';

/// Les prelevements d'un mois : ce qui est deja passe, ce qui reste a tomber.
///
/// C'est ce que la date de prochaine echeance rend possible : le total d'un
/// mois s'ecarte de la moyenne des que l'annuel tombe, et seul le calendrier
/// permet de le voir venir.
class SubscriptionPaymentsPage extends StatefulWidget {
  const SubscriptionPaymentsPage({
    super.key,
    required this.subscriptionService,
    required this.clock,
  });

  final ISubscriptions subscriptionService;
  final DateTime Function() clock;

  @override
  State<SubscriptionPaymentsPage> createState() => _SubscriptionPaymentsPageState();
}

class _SubscriptionPaymentsPageState extends State<SubscriptionPaymentsPage> {
  List<Subscription> _subscriptions = const [];
  List<SubscriptionCategory> _categories = const [];
  bool _loading = true;

  late final DateTime _today = dateOnly(widget.clock());
  late DateTime _month = DateTime(_today.year, _today.month);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final subscriptions = await widget.subscriptionService.getAll();
    final categories = await widget.subscriptionService.getCategories();
    if (!mounted) {
      return;
    }
    setState(() {
      _subscriptions = subscriptions;
      _categories = categories;
      _loading = false;
    });
  }

  void _shiftMonth(int months) =>
      setState(() => _month = DateTime(_month.year, _month.month + months));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = SubscriptionFormat(context);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.sub_payments_title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final ledger = SubscriptionLedger(_subscriptions);
    final last = DateTime(_month.year, _month.month, daysInMonth(_month.year, _month.month));
    final payments = ledger.paymentsIn(_month, last);
    final paid = [
      for (final payment in payments)
        if (payment.date.isBefore(_today)) payment,
    ];
    final upcoming = [
      for (final payment in payments)
        if (!payment.date.isBefore(_today)) payment,
    ];
    final monthTotal = SubscriptionLedger.totalOf(payments);
    final average = ledger.totalIn(SubscriptionFrequency.monthly);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.sub_payments_title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            IconButton(
              onPressed: () => _shiftMonth(-1),
              icon: const Icon(Icons.chevron_left),
              tooltip: l10n.sub_previous_month,
            ),
            Text(format.month(_month), style: theme.textTheme.titleMedium),
            IconButton(
              onPressed: () => _shiftMonth(1),
              icon: const Icon(Icons.chevron_right),
              tooltip: l10n.sub_next_month,
            ),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(
              child: _stat(
                context,
                label: l10n.sub_already_paid,
                amount: format.euros(SubscriptionLedger.totalOf(paid)),
                detail: l10n.sub_payments_count(paid.length),
                color: scheme.secondary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _stat(
                context,
                label: l10n.sub_remaining,
                amount: format.euros(SubscriptionLedger.totalOf(upcoming)),
                detail: l10n.sub_payments_count(upcoming.length),
                color: scheme.primary,
              ),
            ),
          ]),
          const SizedBox(height: 10),
          if (payments.isNotEmpty)
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Icon(Icons.info_outline, size: 20, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l10n.sub_month_vs_average(
                        format.month(_month),
                        format.euros(monthTotal),
                        format.euros(average),
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ]),
              ),
            ),
          const SizedBox(height: 14),
          _calendar(context, payments),
          const SizedBox(height: 18),
          if (payments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                l10n.sub_no_payment_this_month,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.outline),
              ),
            ),
          for (final payment in payments) _paymentRow(context, payment),
        ],
      ),
    );
  }

  Widget _stat(
    BuildContext context, {
    required String label,
    required String amount,
    required String detail,
    required Color color,
  }) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            label,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              amount,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold, color: color),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            detail,
            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline),
          ),
        ]),
      ),
    );
  }

  Widget _calendar(BuildContext context, List<Payment> payments) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final initials = SubscriptionFormat(context).weekdayInitials();
    final total = daysInMonth(_month.year, _month.month);
    // `weekday` vaut 1 le lundi : la grille commence donc sur la semaine
    // francaise, sans decalage a calculer ailleurs.
    final leading = DateTime(_month.year, _month.month).weekday - 1;
    final cells = leading + total;
    final rows = (cells / 7).ceil();

    final byDay = <int, List<Payment>>{};
    for (final payment in payments) {
      byDay.putIfAbsent(payment.date.day, () => []).add(payment);
    }

    return Column(children: [
      Row(children: [
        for (final initial in initials)
          Expanded(
            child: Center(
              child: Text(
                initial,
                style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline),
              ),
            ),
          ),
      ]),
      for (var row = 0; row < rows; row++)
        Row(children: [
          for (var column = 0; column < 7; column++)
            Expanded(
              child: Builder(builder: (context) {
                final day = row * 7 + column - leading + 1;
                if (day < 1 || day > total) {
                  return const SizedBox(height: 46);
                }
                final date = DateTime(_month.year, _month.month, day);
                final isToday = date == _today;
                final dots = byDay[day] ?? const [];
                return Container(
                  height: 46,
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: dots.isEmpty ? null : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: isToday ? Border.all(color: scheme.primary, width: 2) : null,
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(
                      '$day',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: dots.isEmpty ? scheme.outline : scheme.onSurface,
                        fontWeight: dots.isEmpty ? FontWeight.normal : FontWeight.w500,
                      ),
                    ),
                    if (dots.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        for (final payment in dots.take(3))
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 1),
                            child: Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: subscriptionColor(
                                  context,
                                  payment.subscription.categoryId,
                                  _categories,
                                ),
                              ),
                            ),
                          ),
                      ]),
                    ],
                  ]),
                );
              }),
            ),
        ]),
    ]);
  }

  Widget _paymentRow(BuildContext context, Payment payment) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = SubscriptionFormat(context);
    final past = payment.date.isBefore(_today);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: subscriptionColor(context, payment.subscription.categoryId, _categories),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 88,
          child: Text(
            format.shortDay(payment.date),
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: Text(
            payment.subscription.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: past ? scheme.onSurfaceVariant : scheme.onSurface,
            ),
          ),
        ),
        Text(
          format.euros(payment.amount),
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: past ? FontWeight.normal : FontWeight.w600,
            color: past ? scheme.onSurfaceVariant : scheme.onSurface,
          ),
        ),
      ]),
    );
  }
}
