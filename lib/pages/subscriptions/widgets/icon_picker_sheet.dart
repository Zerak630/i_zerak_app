import 'package:flutter/material.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/subscription_dao.dart';
import 'package:i_zerak_app/pages/subscriptions/widgets/subscription_ui.dart';

/// Choix de l'icone d'un abonnement.
///
/// Une grille fermee plutot qu'un champ libre : l'ecran de detail demandait
/// jusqu'ici de taper le point de code d'une icone, que personne ne connait par
/// coeur, et un `IconData` construit a la volee empeche l'elagage des polices.
///
/// La couleur ne se choisit pas ici : elle vient de la categorie, ce que la
/// note du bas rappelle.
Future<String?> showIconPicker(
  BuildContext context, {
  required String? selected,
  required Color tint,
}) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _IconPicker(selected: selected, tint: tint),
    );

class _IconPicker extends StatelessWidget {
  const _IconPicker({required this.selected, required this.tint});

  final String? selected;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SubscriptionSheet(children: [
      Text(l10n.sub_choose_icon, style: theme.textTheme.titleLarge),
      for (final group in kSubscriptionIconGroups.entries) ...[
        Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 8),
          child: Text(
            iconGroupLabel(l10n, group.key),
            style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final id in group.value)
              _IconTile(
                id: id,
                tint: tint,
                isSelected: id == (selected ?? kDefaultSubscriptionIcon),
              ),
          ],
        ),
      ],
      const SizedBox(height: 20),
      Row(children: [
        Icon(Icons.palette_outlined, size: 18, color: scheme.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            l10n.sub_icon_color_hint,
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ]),
    ]);
  }
}

class _IconTile extends StatelessWidget {
  const _IconTile({required this.id, required this.tint, required this.isSelected});

  final String id;
  final Color tint;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      selected: isSelected,
      child: InkWell(
        onTap: () => Navigator.pop(context, id),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: isSelected ? tint.withValues(alpha: 0.18) : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
            border: isSelected ? Border.all(color: tint, width: 1.5) : null,
          ),
          child: Icon(
            subscriptionIcon(id),
            size: 24,
            color: isSelected ? tint : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
