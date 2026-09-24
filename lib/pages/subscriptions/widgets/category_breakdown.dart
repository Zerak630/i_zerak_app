import 'dart:math';

import 'package:flutter/material.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/subscription_dao.dart';
import 'package:i_zerak_app/pages/subscriptions/widgets/subscription_ui.dart';

/// La repartition par categorie : une barre, sa legende, et le detail qu'un
/// appui deplie.
///
/// Depliee plutot qu'ouverte dans un ecran a part : avec une poignee
/// d'abonnements, une page entiere de repartition ne ferait que repeter la
/// liste avec d'autres etiquettes.
class CategoryBreakdown extends StatelessWidget {
  const CategoryBreakdown({
    super.key,
    required this.totals,
    required this.categories,
    required this.unit,
    required this.expanded,
    required this.onToggle,
    required this.selectedCategoryId,
    required this.onSelect,
  });

  final List<CategoryTotal> totals;
  final List<SubscriptionCategory> categories;
  final SubscriptionFrequency unit;
  final bool expanded;
  final VoidCallback onToggle;

  /// La categorie qui filtre la liste, nulle quand tout est affiche.
  final String? selectedCategoryId;
  final ValueChanged<String?> onSelect;

  Color _colorOf(BuildContext context, String? categoryId) =>
      subscriptionColor(context, categoryId, categories);

  String _labelOf(AppLocalizations l10n, String? categoryId) =>
      categoryLabelOf(l10n, categoryId, categories);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = SubscriptionFormat(context);

    // Une seule categorie ne se repartit pas : la barre afficherait « 100 % »
    // et la legende repeterait la liste.
    if (totals.length < 2) {
      return const SizedBox.shrink();
    }

    final legend = totals.take(3).toList();
    final hidden = totals.length - legend.length;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Semantics(
              label: l10n.sub_expand_detail,
              child: SizedBox(
                height: 10,
                child: Row(children: [
                  for (var i = 0; i < totals.length; i++) ...[
                    if (i > 0) const SizedBox(width: 2),
                    Expanded(
                      // Au moins 1 : un flex nul ferait disparaitre la part la
                      // plus faible, et la barre ne totaliserait plus 100 %.
                      flex: max(1, (totals[i].share * 1000).round()),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: _colorOf(context, totals[i].categoryId),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ],
                ]),
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              for (final total in legend) ...[
                _Dot(color: _colorOf(context, total.categoryId)),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    '${_labelOf(l10n, total.categoryId)} ${format.percent(total.share)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
                const SizedBox(width: 11),
              ],
              const Spacer(),
              if (hidden > 0)
                Text(
                  '+ $hidden',
                  style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline),
                ),
              AnimatedRotation(
                turns: expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 180),
                child: Icon(Icons.expand_more, size: 18, color: scheme.outline),
              ),
            ]),
          ]),
        ),
      ),
      if (expanded) ...[
        const SizedBox(height: 4),
        for (final total in totals)
          InkWell(
            onTap: () => onSelect(total.categoryId == selectedCategoryId ? null : total.categoryId),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              decoration: BoxDecoration(
                color: total.categoryId == selectedCategoryId
                    ? scheme.secondaryContainer
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                _Dot(color: _colorOf(context, total.categoryId)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _labelOf(l10n, total.categoryId),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                Text(
                  format.euros(total.amount),
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    format.percent(total.share),
                    textAlign: TextAlign.end,
                    style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline),
                  ),
                ),
              ]),
            ),
          ),
      ],
    ]);
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}
