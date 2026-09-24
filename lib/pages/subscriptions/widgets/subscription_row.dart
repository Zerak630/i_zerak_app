import 'package:flutter/material.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/subscription_dao.dart';
import 'package:i_zerak_app/pages/subscriptions/widgets/subscription_ui.dart';

/// Une ligne de la liste : l'abonnement, sa facturation reelle, et son cout
/// ramene a l'unite affichee.
///
/// Les deux montants cohabitent a dessein : le premier est celui qui apparait
/// sur le compte, le second est celui qui se compare aux autres lignes.
class SubscriptionRow extends StatelessWidget {
  const SubscriptionRow({
    super.key,
    required this.subscription,
    required this.unit,
    required this.categories,
    this.onTap,
  });

  final Subscription subscription;
  final SubscriptionFrequency unit;
  final List<SubscriptionCategory> categories;
  final VoidCallback? onTap;

  /// « chaque mardi », « le 28 », « le 12 mars » : quand tombe l'echeance.
  String? _dateHint(AppLocalizations l10n, SubscriptionFormat format) {
    final date = subscription.nextPayment;
    if (date == null) {
      return null;
    }
    return switch (subscription.subscriptionType) {
      SubscriptionFrequency.weekly => l10n.sub_every_weekday(format.weekday(date)),
      SubscriptionFrequency.monthly => l10n.sub_on_date(date.day.toString()),
      SubscriptionFrequency.yearly => l10n.sub_on_date(format.shortDay(date)),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = SubscriptionFormat(context);
    final muted = !subscription.isActive;

    final billing = '${format.euros(subscription.price)} '
        '${unitLabel(l10n, subscription.subscriptionType)}';
    final hint = _dateHint(l10n, format);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(children: [
          SubscriptionAvatar(
            iconId: subscription.iconId,
            color: subscriptionColor(context, subscription.categoryId, categories),
            muted: muted,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                subscription.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: muted ? scheme.onSurfaceVariant : scheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                hint == null ? billing : '$billing · $hint',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
              ),
            ]),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(
              format.euros(subscription.amountIn(unit)),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: muted ? scheme.onSurfaceVariant : scheme.onSurface,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              unitLabel(l10n, unit),
              style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline),
            ),
          ]),
        ]),
      ),
    );
  }
}
