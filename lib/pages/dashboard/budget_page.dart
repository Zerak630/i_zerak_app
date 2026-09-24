import 'package:flutter/material.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/budget_dao.dart';
import 'package:i_zerak_app/models/commute_dao.dart' hide dateOnly, roundCents;
import 'package:i_zerak_app/models/subscription_dao.dart';
import 'package:i_zerak_app/pages/subscriptions/widgets/subscription_ui.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_commute.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_subscriptions.dart';

/// Ce que le mois coute, abonnements et trajets en voiture reunis.
///
/// Les deux sources sont deja enregistrees ailleurs : cet ecran ne demande
/// aucune saisie, il additionne. Ce que le velo a evite figure a cote du
/// total, sans jamais s'y ajouter — c'est une depense qui n'a pas eu lieu.
class BudgetPage extends StatefulWidget {
  const BudgetPage({
    super.key,
    required this.subscriptionService,
    required this.commuteService,
    required this.clock,
  });

  final ISubscriptions subscriptionService;
  final ICommute commuteService;
  final DateTime Function() clock;

  @override
  State<BudgetPage> createState() => _BudgetPageState();
}

class _BudgetPageState extends State<BudgetPage> {
  SubscriptionLedger _subscriptions = SubscriptionLedger(const []);
  CommuteLedger _commute = CommuteLedger(const [], const []);
  bool _loading = true;

  late final DateTime _today = widget.clock();
  late DateTime _month = DateTime(_today.year, _today.month);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final subscriptions = await widget.subscriptionService.getAll();
    final days = await widget.commuteService.getDays();
    if (!mounted) {
      return;
    }
    setState(() {
      _subscriptions = SubscriptionLedger(subscriptions);
      _commute = CommuteLedger(days, const []);
      _loading = false;
    });
  }

  void _shiftMonth(int months) =>
      setState(() => _month = DateTime(_month.year, _month.month + months));

  bool get _isCurrentMonth => _month.year == _today.year && _month.month == _today.month;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final format = SubscriptionFormat(context);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.budget_title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final budget =
        budgetOf(_month, subscriptions: _subscriptions, commute: _commute);
    final previous = budgetOf(
      DateTime(_month.year, _month.month - 1),
      subscriptions: _subscriptions,
      commute: _commute,
    );
    final history =
        budgetHistory(_month, subscriptions: _subscriptions, commute: _commute);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.budget_title)),
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
              // Le mois a venir n'a encore rien preleve : l'avance s'arrete au
              // mois courant, comme l'historique.
              onPressed: _isCurrentMonth ? null : () => _shiftMonth(1),
              icon: const Icon(Icons.chevron_right),
              tooltip: l10n.sub_next_month,
            ),
          ]),
          _total(context, l10n, budget, previous),
          const SizedBox(height: 14),
          _line(
            context,
            color: theme.colorScheme.primary,
            title: l10n.subscription_title,
            detail: l10n.sub_payments_count(budget.subscriptionCount),
            amount: format.euros(budget.subscriptions),
          ),
          const Divider(height: 1),
          _line(
            context,
            color: theme.colorScheme.secondary,
            title: l10n.budget_car,
            detail: l10n.commute_days(budget.carDays),
            amount: format.euros(budget.carTrips),
          ),
          const SizedBox(height: 16),
          _bike(context, l10n, budget),
          const SizedBox(height: 16),
          _history(context, l10n, history),
          const SizedBox(height: 16),
          Text(
            l10n.budget_note,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }

  Widget _total(
    BuildContext context,
    AppLocalizations l10n,
    MonthBudget budget,
    MonthBudget previous,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = SubscriptionFormat(context);
    final difference = budget.total - previous.total;
    final previousMonth = format.monthName(previous.month);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            l10n.budget_outflow.toUpperCase(),
            style: theme.textTheme.labelSmall
                ?.copyWith(color: scheme.onSurfaceVariant, letterSpacing: 0.8),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              format.euros(budget.total),
              style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          if (!previous.isEmpty) ...[
            const SizedBox(height: 8),
            Row(children: [
              Icon(
                difference < 0 ? Icons.south : Icons.north,
                size: 15,
                color: difference < 0 ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  difference < 0
                      ? l10n.budget_less_than(format.euros(-difference), previousMonth)
                      : l10n.budget_more_than(format.euros(difference), previousMonth),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: difference < 0 ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ]),
          ],
          if (!budget.isEmpty) ...[
            const SizedBox(height: 14),
            SizedBox(
              height: 10,
              child: Row(
                // Meme piege que la barre des categories : sans `stretch`, des
                // boites sans enfant se replient sur zero pixel.
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: _flex(budget.subscriptionShare),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  if (budget.carTrips > 0) ...[
                    const SizedBox(width: 3),
                    Expanded(
                      flex: _flex(1 - budget.subscriptionShare),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: scheme.secondary,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ]),
      ),
    );
  }

  static int _flex(double share) => share <= 0 ? 1 : (share * 1000).round();

  Widget _line(
    BuildContext context, {
    required Color color,
    required String title,
    required String detail,
    required String amount,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 2),
            Text(
              detail,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
            ),
          ]),
        ),
        Text(
          amount,
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
      ]),
    );
  }

  Widget _bike(BuildContext context, AppLocalizations l10n, MonthBudget budget) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = SubscriptionFormat(context);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(Icons.pedal_bike, size: 20, color: scheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l10n.budget_bike_avoided, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 2),
              Text(
                l10n.budget_bike_detail(
                  l10n.commute_days(budget.bikeDays),
                  format.euros(_commute.totalSaved),
                ),
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          Text(
            format.euros(budget.bikeSaved),
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w600, color: scheme.primary),
          ),
        ]),
      ),
    );
  }

  Widget _history(BuildContext context, AppLocalizations l10n, List<MonthBudget> history) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = SubscriptionFormat(context);
    final highest = history.fold(0.0, (top, month) => month.total > top ? month.total : top);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(l10n.budget_history, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 14),
          SizedBox(
            height: 110,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (final month in history)
                Expanded(
                  child: _HistoryBar(
                    // La barre du mois affiche porte la couleur d'accent : le
                    // graphique dit alors ou l'on se trouve, et les autres
                    // barres restent cliquables pour y aller. Le montant, lui,
                    // reste en haut de l'ecran : le repeter sous une colonne
                    // de cinquante pixels le couperait.
                    selected: month.month == _month,
                    height: highest <= 0 ? 0 : 84 * month.total / highest,
                    label: format.shortMonth(month.month),
                    onTap: () => setState(() => _month = month.month),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.budget_history_hint,
            style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline),
          ),
        ]),
      ),
    );
  }
}

class _HistoryBar extends StatelessWidget {
  const _HistoryBar({
    required this.selected,
    required this.height,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final double height;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
          Container(
            // Un filet reste visible meme a zero : une colonne absente se
            // confondrait avec un trou dans le graphique.
            height: height < 3 ? 3 : height,
            decoration: BoxDecoration(
              color: selected ? scheme.primary : scheme.surfaceContainerHighest,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            style: theme.textTheme.labelSmall?.copyWith(
              color: selected ? scheme.onSurface : scheme.outline,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ]),
      ),
    );
  }
}
