import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:i_zerak_app/models/subscription_dao.dart';
import 'package:i_zerak_app/pages/subscriptions/widgets/subscription_detail.dart';

class SubscriptionCard extends StatelessWidget {
  const SubscriptionCard({
    super.key,
    required this.subscription,
    this.onChanged,
  });

  final Subscription subscription;

  /// Notifie le parent apres un retour de la page de detail, sans quoi la liste
  /// continuait d'afficher les anciennes valeurs.
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8.0),
      child: ListTile(
        leading: const Icon(Icons.subscriptions),
        title: Text(subscription.name),
        subtitle: Text('${subscription.price.toStringAsFixed(2)} € '
            '/ ${SubscriptionFrequency.getLocaleAdjective(context, subscription.subscriptionType)}'),
        trailing: subscription.isActive
            ? Icon(Icons.check_circle,
                color: Colors.green, semanticLabel: AppLocalizations.of(context)!.active)
            : Icon(Icons.cancel,
                color: Theme.of(context).colorScheme.error,
                semanticLabel: AppLocalizations.of(context)!.inactive),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SubscriptionDetailPage(subscription: subscription),
            ),
          );
          onChanged?.call();
        },
      ),
    );
  }
}
