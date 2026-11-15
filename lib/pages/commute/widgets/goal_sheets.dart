import 'package:flutter/material.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/commute_dao.dart';
import 'package:i_zerak_app/pages/commute/widgets/commute_ui.dart';

/// Creation d'un palier : un gros achat a rentabiliser. Renvoie le palier, pas
/// encore enregistre.
///
/// Il n'y a plus d'achat a financer : la cagnotte ou l'on puisait a laisse la
/// place aux abonnements rembourses. Reste ce qui se rentabilise avec le
/// temps — le velo, un telephone, du materiel de sport.
///
/// [missingHint] traduit ce qui manque en trajets a velo. Nul quand il n'a
/// rien a dire.
Future<Goal?> showNewGoalSheet(
  BuildContext context, {
  required GoalBook book,
  required DateTime today,
  String? Function(double missing)? missingHint,
}) =>
    showModalBottomSheet<Goal>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _NewGoalSheet(book: book, today: today, missingHint: missingHint),
    );

class _NewGoalSheet extends StatefulWidget {
  const _NewGoalSheet({required this.book, required this.today, required this.missingHint});

  final GoalBook book;
  final DateTime today;
  final String? Function(double missing)? missingHint;

  @override
  State<_NewGoalSheet> createState() => _NewGoalSheetState();
}

class _NewGoalSheetState extends State<_NewGoalSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _amount = TextEditingController();
  var _icon = GoalIcon.bike;

  /// Nul : compte depuis le premier trajet. Sinon, depuis la date d'achat.
  DateTime? _since;

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

  Future<void> _pickSince() async {
    final chosen = await showDatePicker(
      context: context,
      initialDate: _since ?? widget.today,
      firstDate: DateTime(2000),
      lastDate: widget.today,
    );
    if (chosen != null) {
      setState(() => _since = dateOnly(chosen));
    }
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
        kind: GoalKind.milestone,
        icon: _icon,
        createdAt: now,
        since: _since,
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
    final current = widget.book.savedSince(_since);

    return Form(
      key: _formKey,
      child: CommuteSheet(children: [
        Text(l10n.goal_new, style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          l10n.goal_new_hint,
          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 18),
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
        Text(l10n.goal_since, style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: false, label: Text(l10n.goal_since_start)),
            ButtonSegment(
              value: true,
              label: Text(_since == null ? l10n.goal_since_purchase : format.shortDayWithYear(_since!)),
            ),
          ],
          selected: {_since != null},
          onSelectionChanged: (selection) {
            if (selection.first) {
              _pickSince();
            } else {
              setState(() => _since = null);
            }
          },
        ),
        const SizedBox(height: 6),
        Text(
          l10n.goal_since_hint,
          style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline),
        ),
        const SizedBox(height: 16),
        Text(l10n.goal_icon, style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 10, children: [
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
    final hint = missing > 0 ? widget.missingHint?.call(missing) : null;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          missing <= 0
              ? l10n.goal_already_reached
              : l10n.goal_preview(format.euros(current), format.euros(missing)),
          style: theme.textTheme.titleSmall,
        ),
        if (hint != null) ...[
          const SizedBox(height: 4),
          Text(
            hint,
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ]),
    );
  }
}

/// Confirmation d'un palier franchi. Renvoie `true` s'il faut le valider.
///
/// Valider ne depense rien : le palier rejoint la liste de ceux qui sont
/// rentabilises.
Future<bool> showValidateGoalSheet(
  BuildContext context, {
  required Goal goal,
  required GoalBook book,
}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _ValidateGoalSheet(goal: goal, book: book),
    ) ??
    false;

class _ValidateGoalSheet extends StatelessWidget {
  const _ValidateGoalSheet({required this.goal, required this.book});

  final Goal goal;
  final GoalBook book;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = CommuteFormat(context);
    final color = scheme.primary;

    return CommuteSheet(children: [
      Align(
        alignment: Alignment.centerLeft,
        child: CircleAvatar(
          radius: 26,
          backgroundColor: color.withValues(alpha: 0.18),
          foregroundColor: color,
          child: Icon(goalIconData(goal.icon), size: 26),
        ),
      ),
      const SizedBox(height: 14),
      Text(l10n.goal_validate_title(goal.name), style: theme.textTheme.titleLarge),
      const SizedBox(height: 6),
      Text(
        l10n.goal_validate_detail(
            format.euros(book.progressOf(goal).current), format.euros(goal.target)),
        style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
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
            style: FilledButton.styleFrom(backgroundColor: color, foregroundColor: scheme.onPrimary),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.goal_validate_milestone),
          ),
        ),
      ]),
    ]);
  }
}
