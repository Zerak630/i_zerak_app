import 'dart:math';

import 'package:flutter/material.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/components/subscription_modal.dart';
import 'package:i_zerak_app/models/subscription_dao.dart';
import 'package:i_zerak_app/pages/subscriptions/widgets/subscription_card.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_subscriptions.dart';
import 'package:i_zerak_app/services/service_locator.dart';

class SubscriptionsPage extends StatefulWidget {
  final ISubscriptions subscriptionService;

  SubscriptionsPage({super.key, ISubscriptions? subscriptionService})
      : subscriptionService = subscriptionService ?? getIt<ISubscriptions>();

  @override
  State<SubscriptionsPage> createState() => _SubscriptionsPageState();
}

class _SubscriptionsPageState extends State<SubscriptionsPage> {
  double _totalPerWeek = 0.0;
  double _totalPerMonth = 0.0;
  double _totalPerYear = 0.0;

  /// Conserve en champ, et non recree dans build() : un Future construit a
  /// chaque rebuild relancait la lecture et refaisait clignoter le loader.
  late Future<List<Subscription>> _subscriptions;

  @override
  void initState() {
    super.initState();
    _subscriptions = _load();
  }

  Future<List<Subscription>> _load() async {
    final subscriptions = await widget.subscriptionService.getAll();
    if (mounted) {
      _calculateTotals(subscriptions);
    }
    return subscriptions;
  }

  void _refresh() => setState(() => _subscriptions = _load());

  void _calculateTotals(List<Subscription> subscriptions) {
    double weeklyTotal = 0.0;
    double monthlyTotal = 0.0;
    double yearlyTotal = 0.0;

    for (var subscription in subscriptions) {
      if (!subscription.isActive) {
        continue;
      }
      switch (subscription.subscriptionType) {
        // La frequence hebdomadaire n'etait traitee nulle part, alors qu'elle
        // est la valeur par defaut du modele : tout abonnement cree sans
        // changer la frequence etait absent des trois totaux.
        case SubscriptionFrequency.weekly:
          weeklyTotal += subscription.price;
          monthlyTotal += subscription.price * 52 / 12;
          yearlyTotal += subscription.price * 52;
          break;
        case SubscriptionFrequency.monthly:
          monthlyTotal += subscription.price;
          yearlyTotal += subscription.price * 12;
          weeklyTotal += subscription.price * 12 / 52;
          break;
        case SubscriptionFrequency.yearly:
          yearlyTotal += subscription.price;
          monthlyTotal += subscription.price / 12;
          weeklyTotal += subscription.price / 52;
          break;
      }
    }

    setState(() {
      _totalPerWeek = weeklyTotal;
      _totalPerMonth = monthlyTotal;
      _totalPerYear = yearlyTotal;
    });
  }

  Future<void> _openModal() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => const SubscriptionModal(),
    );
    if (saved == true) {
      _refresh();
    }
  }

  double _totalFontSize(BuildContext context) => min(
        MediaQuery.of(context).size.width * 0.05,
        Theme.of(context).textTheme.headlineMedium?.fontSize ?? 24.0,
      );

  Widget _total(BuildContext context, double value) => Expanded(
        child: Text('${value.toStringAsFixed(2)} €',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: _totalFontSize(context), fontWeight: FontWeight.bold)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder: (Widget child, Animation<double> animation) {
                        return FadeTransition(
                          opacity: Tween<double>(begin: 0, end: 1).animate(animation),
                          child: child,
                        );
                      },
                      child: Row(
                        // La cle ne portait que sur le total hebdomadaire : une
                        // variation des seuls totaux mois/annee ne declenchait
                        // aucune transition.
                        key: ValueKey<String>('$_totalPerWeek|$_totalPerMonth|$_totalPerYear'),
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _total(context, _totalPerWeek),
                          _total(context, _totalPerMonth),
                          _total(context, _totalPerYear),
                        ],
                      )),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Expanded(
                        child: Text(AppLocalizations.of(context)!.per_week,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontStyle: FontStyle.italic)),
                      ),
                      Expanded(
                        child: Text(AppLocalizations.of(context)!.per_month,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontStyle: FontStyle.italic)),
                      ),
                      Expanded(
                        child: Text(AppLocalizations.of(context)!.per_year,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontStyle: FontStyle.italic)),
                      )
                    ],
                  )
                ],
              ),
            ),
            Flexible(
              child: FutureBuilder<List<Subscription>>(
                future: _subscriptions,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  } else if (snapshot.hasError) {
                    return Center(
                        child: Text(AppLocalizations.of(context)!.loading_error(
                      snapshot.error.toString(),
                    )));
                  } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return Center(child: Text(AppLocalizations.of(context)!.no_subscription));
                  } else {
                    return ListView.builder(
                      itemCount: snapshot.data!.length,
                      itemBuilder: (context, index) {
                        final subscription = snapshot.data![index];
                        return SubscriptionCard(
                          key: ValueKey<String?>(subscription.id),
                          subscription: subscription,
                          onChanged: _refresh,
                        );
                      },
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openModal,
        child: const Icon(Icons.add),
      ),
    );
  }
}
