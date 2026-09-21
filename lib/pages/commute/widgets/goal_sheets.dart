import 'package:flutter/material.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/commute_dao.dart';
import 'package:i_zerak_app/pages/commute/widgets/commute_ui.dart';

/// Creation d'un objectif. Renvoie l'objectif, pas encore enregistre.
Future<Goal?> showNewGoalSheet(
  BuildContext context, {
  required CommuteLedger ledger,
  required double tripValue,
}) =>
    showModalBottomSheet<Goal>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _NewGoalSheet(ledger: ledger, tripValue: tripValue),
    );

class _NewGoalSheet extends StatefulWidget {
  const _NewGoalSheet({required this.ledger, required this.tripValue});

  final CommuteLedger ledger;
  final double tripValue;

  @override
  State<_NewGoalSheet> createState() => _NewGoalSheetState();
}

class _NewGoalSheetState extends State<_NewGoalSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _amount = TextEditingController();
  var _kind = GoalKind.purchase;
  var _icon = GoalIcon.gift;

  @override
  void initState() {
    super.initState();
    // L'apercu suit la saisie du montant.
    _amount.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final now = DateTime.now();
    Navigator.pop(
      context,
      Goal(
        id: 'goal-${now.microsecondsSinceEpoch}',
        name: _name.text.trim(),
        target: roundCents(parseDecimal(_amount.text)!),
        kind: _kind,
        icon: _icon,
        createdAt: now,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = CommuteFormat(context);

    final target = parseDecimal(_amount.text);
    final current =
        _kind == GoalKind.purchase ? widget.ledger.balance : widget.ledger.totalSaved;

    return Form(
      key: _formKey,
      child: CommuteSheet(children: [
        Text(l10n.goal_new, style: theme.textTheme.titleLarge),
        const SizedBox(height: 16),
        Row(children: [
          for (final kind in GoalKind.values) ...[
            if (kind != GoalKind.values.first) const SizedBox(width: 10),
            Expanded(
              child: _KindCard(
                title: kind == GoalKind.purchase ? l10n.goal_kind_purchase : l10n.goal_kind_milestone,
                hint: kind == GoalKind.purchase
                    ? l10n.goal_kind_purchase_hint
                    : l10n.goal_kind_milestone_hint,
                selected: _kind == kind,
                color: goalColor(scheme, kind),
                onTap: () => setState(() => _kind = kind),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 20),
        TextFormField(
          controller: _name,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: l10n.goal_name, border: const OutlineInputBorder()),
          validator: (value) =>
              (value ?? '').trim().isEmpty ? l10n.please_enter_a_name : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: l10n.goal_amount,
            suffixText: '€',
            border: const OutlineInputBorder(),
          ),
          validator: (value) {
            final amount = parseDecimal(value ?? '');
            return amount == null || amount <= 0 ? l10n.goal_invalid_amount : null;
          },
        ),
        const SizedBox(height: 16),
        Text(l10n.goal_icon, style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(spacing: 10, children: [
          for (final icon in GoalIcon.values)
            IconButton(
              isSelected: _icon == icon,
              style: IconButton.styleFrom(
                fixedSize: const Size.square(52),
                backgroundColor: _icon == icon ? scheme.primaryContainer : null,
                side: BorderSide(
                  color: _icon == icon ? scheme.primary : scheme.outlineVariant,
                  width: _icon == icon ? 2 : 1,
                ),
              ),
              icon: Icon(goalIconData(icon)),
              onPressed: () => setState(() => _icon = icon),
            ),
        ]),
        if (target != null && target > 0) ...[
          const SizedBox(height: 16),
          _preview(context, l10n, format, target: target, current: current),
        ],
        const SizedBox(height: 20),
        Row(children: [
          Expanded(
            child: TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
          ),
          const SizedBox(width: 8),
          Expanded(flex: 2, child: FilledButton(onPressed: _submit, child: Text(l10n.goal_create))),
        ]),
      ]),
    );
  }

  Widget _preview(
    BuildContext context,
    AppLocalizations l10n,
    CommuteFormat format, {
    required double target,
    required double current,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final missing = roundCents(target - current);
    final trips = tripsFor(missing, widget.tripValue);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          missing <= 0 ? l10n.goal_already_reached : l10n.goal_missing(format.euros(missing)),
          style: theme.textTheme.titleSmall,
        ),
        if (missing > 0 && trips != null) ...[
          const SizedBox(height: 4),
          Text(
            l10n.goal_missing_trips(trips, format.euros(widget.tripValue)),
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ]),
    );
  }
}

class _KindCard extends StatelessWidget {
  const _KindCard({
    required this.title,
    required this.hint,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String hint;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: selected ? color.withValues(alpha: 0.14) : scheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: selected ? color : scheme.outlineVariant, width: selected ? 2 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: theme.textTheme.titleSmall?.copyWith(color: selected ? color : null)),
            const SizedBox(height: 2),
            Text(hint, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ]),
        ),
      ),
    );
  }
}

/// Confirmation d'un objectif atteint. Renvoie `true` s'il faut le valider.
///
/// Pour un achat, la feuille montre ce que la depense retire aux autres
/// achats avant de confirmer : ils puisent tous dans le meme solde.
Future<bool> showValidateGoalSheet(
  BuildContext context, {
  required Goal goal,
  required CommuteLedger ledger,
}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _ValidateGoalSheet(goal: goal, ledger: ledger),
    ) ??
    false;

class _ValidateGoalSheet extends StatelessWidget {
  const _ValidateGoalSheet({required this.goal, required this.ledger});

  final Goal goal;
  final CommuteLedger ledger;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = CommuteFormat(context);
    final purchase = goal.kind == GoalKind.purchase;
    final after = CommuteLedger(ledger.days, [
      for (final other in ledger.goals) other.id == goal.id ? other.validated(DateTime.now()) : other
    ]);

    return CommuteSheet(children: [
      Align(
        alignment: Alignment.centerLeft,
        child: CircleAvatar(
          radius: 26,
          backgroundColor: goalColor(scheme, goal.kind).withValues(alpha: 0.18),
          foregroundColor: goalColor(scheme, goal.kind),
          child: Icon(goalIconData(goal.icon), size: 26),
        ),
      ),
      const SizedBox(height: 14),
      Text(l10n.goal_validate_title(goal.name), style: theme.textTheme.titleLarge),
      const SizedBox(height: 6),
      Text(
        purchase
            ? l10n.goal_validate_purchase_detail(format.euros(goal.target))
            : l10n.goal_validate_milestone_detail,
        style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration:
            BoxDecoration(color: scheme.surfaceContainer, borderRadius: BorderRadius.circular(16)),
        child: Column(children: [
          if (purchase)
            _ChangeRow(
              label: l10n.goal_row_pot,
              before: format.euros(ledger.balance),
              after: format.euros(after.balance),
              color: scheme.primary,
            ),
          for (final other in ledger.activeGoals)
            if (other.id != goal.id)
              if (purchase && other.kind == GoalKind.purchase)
                _ChangeRow(
                  label: other.name,
                  before: format.percent(ledger.progressOf(other).ratio),
                  after: format.percent(after.progressOf(other).ratio),
                  color: goalColor(scheme, other.kind),
                )
              else if (other.kind == GoalKind.milestone)
                _ChangeRow(
                  label: other.name,
                  after: format.percent(ledger.progressOf(other).ratio),
                  color: goalColor(scheme, other.kind),
                  note: l10n.goal_unchanged,
                ),
          _ChangeRow(
            label: l10n.goal_row_saved,
            after: format.euros(ledger.totalSaved),
            color: scheme.onSurface,
            note: l10n.goal_unchanged,
          ),
        ]),
      ),
      const SizedBox(height: 20),
      Row(children: [
        Expanded(
          child: TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(purchase ? l10n.goal_spend(format.euros(goal.target)) : l10n.goal_validate_milestone),
          ),
        ),
      ]),
    ]);
  }
}

class _ChangeRow extends StatelessWidget {
  const _ChangeRow({
    required this.label,
    required this.after,
    required this.color,
    this.before,
    this.note,
  });

  final String label;
  final String? before;
  final String after;
  final Color color;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return SizedBox(
      height: 52,
      child: Row(children: [
        Expanded(child: Text(label, style: theme.textTheme.bodyMedium, overflow: TextOverflow.ellipsis)),
        if (before != null) ...[
          Text(before!, style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Icon(Icons.arrow_forward, size: 16, color: muted),
          ),
        ],
        if (note != null) ...[
          Text(note!, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
          const SizedBox(width: 10),
        ],
        Text(after, style: theme.textTheme.titleSmall?.copyWith(color: color)),
      ]),
    );
  }
}
