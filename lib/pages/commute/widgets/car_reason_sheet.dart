import 'package:flutter/material.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/commute_dao.dart';
import 'package:i_zerak_app/pages/commute/widgets/commute_ui.dart';

/// Demande pourquoi la voiture a ete prise, et renvoie la raison choisie.
///
/// Chaque raison affiche la cagnotte qu'elle alimente : le choix se fait en
/// connaissance de cause, pas en le decouvrant apres coup dans les totaux.
///
/// `onAddReason` ajoute une raison aux reglages et la renvoie ; elle est alors
/// selectionnee d'office, puisqu'on vient de la creer pour ce trajet.
Future<CarReason?> showCarReasonSheet(
  BuildContext context, {
  required List<CarReason> reasons,
  required String subtitle,
  required Future<CarReason?> Function() onAddReason,
}) =>
    showModalBottomSheet<CarReason>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _CarReasonSheet(reasons: reasons, subtitle: subtitle, onAddReason: onAddReason),
    );

class _CarReasonSheet extends StatefulWidget {
  const _CarReasonSheet({required this.reasons, required this.subtitle, required this.onAddReason});

  final List<CarReason> reasons;
  final String subtitle;
  final Future<CarReason?> Function() onAddReason;

  @override
  State<_CarReasonSheet> createState() => _CarReasonSheetState();
}

class _CarReasonSheetState extends State<_CarReasonSheet> {
  late final List<CarReason> _reasons = [...widget.reasons];

  /// Rien n'est coche d'avance : une raison preselectionnee serait validee par
  /// reflexe, et fausserait les deux cagnottes sans qu'on s'en apercoive.
  CarReason? _selected;

  Future<void> _add() async {
    final reason = await widget.onAddReason();
    if (reason == null || !mounted) {
      return;
    }
    setState(() {
      _reasons.add(reason);
      _selected = reason;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return CommuteSheet(children: [
      Text(l10n.commute_why_car, style: theme.textTheme.titleLarge),
      const SizedBox(height: 4),
      Text(widget.subtitle,
          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
      const SizedBox(height: 16),
      for (final reason in _reasons) ...[
        _ReasonTile(
          label: carReasonLabel(l10n, reason),
          bucket: reason.bucket,
          selected: _selected?.id == reason.id,
          onTap: () => setState(() => _selected = reason),
        ),
        const SizedBox(height: 8),
      ],
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _add,
          icon: const Icon(Icons.add),
          label: Text(l10n.commute_add_reason),
        ),
      ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: FilledButton(
            onPressed: _selected == null ? null : () => Navigator.pop(context, _selected),
            child: Text(l10n.save),
          ),
        ),
      ]),
    ]);
  }
}

class _ReasonTile extends StatelessWidget {
  const _ReasonTile({
    required this.label,
    required this.bucket,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final CarBucket bucket;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final missed = bucket == CarBucket.missed;

    return Material(
      color: selected ? scheme.primaryContainer.withValues(alpha: 0.35) : scheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: selected ? scheme.primary : scheme.outline),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: theme.textTheme.titleMedium),
                Text(
                  missed ? l10n.commute_bucket_missed_hint : l10n.commute_bucket_essential_hint,
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ]),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: missed ? scheme.tertiaryContainer : scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                missed ? l10n.commute_chip_missed : l10n.commute_chip_essential,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: missed ? scheme.onTertiaryContainer : scheme.onSecondaryContainer,
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
