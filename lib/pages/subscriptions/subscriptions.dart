import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:i_zerak_app/components/subscription_modal.dart';
import 'package:i_zerak_app/main.dart';
import 'package:i_zerak_app/models/subscription_dao.dart';
import 'package:i_zerak_app/pages/subscriptions/widgets/subscription_card.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_subscriptions.dart';
import 'package:i_zerak_app/services/subscriptions_service.dart';

class SubscriptionsPage extends StatefulWidget {
  final ISubscriptions subscriptionService = getIt<ISubscriptions>();

  SubscriptionsPage({super.key});

  @override
  _SubscriptionsPageState createState() => _SubscriptionsPageState();
}

class _SubscriptionsPageState extends State<SubscriptionsPage> {
  double _totalPerWeek = 0.0;
  double _totalPerMonth = 0.0;
  double _totalPerYear = 0.0;

  @override
  void initState() {
    super.initState();
    _loadSubscriptions();
  }

  Future<void> _loadSubscriptions() async {
    final subscriptions = await widget.subscriptionService.getAll();
    _calculateTotals(subscriptions);
  }

  void _calculateTotals(List<Subscription> subscriptions) {
    double weeklyTotal = 0.0;
    double monthlyTotal = 0.0;
    double yearlyTotal = 0.0;

    for (var subscription in subscriptions) {
      if (subscription.isActive) {
        if (subscription.subscriptionType == SubscriptionFrequency.monthly) {
          monthlyTotal += subscription.price;
          yearlyTotal += subscription.price * 12;
          weeklyTotal += subscription.price / 4; // Approximation
        } else if (subscription.subscriptionType == SubscriptionFrequency.yearly) {
          yearlyTotal += subscription.price;
          monthlyTotal += subscription.price / 12;
          weeklyTotal += subscription.price / 52; // Approximation
        }
      }
    }

    setState(() {
      _totalPerWeek = weeklyTotal;
      _totalPerMonth = monthlyTotal;
      _totalPerYear = yearlyTotal;
    });
  }

  @override
  Widget build(BuildContext context) {
    final subscriptionService = SubscriptionService();

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
                        key: ValueKey<String>(_totalPerWeek.toString()),
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Expanded(
                              child: Text('$_totalPerWeek€',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: min(MediaQuery.of(context).size.width * 0.05,
                                          Theme.of(context).textTheme.headlineMedium!.fontSize!),
                                      fontWeight: FontWeight.bold))),
                          Expanded(
                              child: Text('$_totalPerMonth€',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: min(MediaQuery.of(context).size.width * 0.05,
                                          Theme.of(context).textTheme.headlineMedium!.fontSize!),
                                      fontWeight: FontWeight.bold))),
                          Expanded(
                              child: Text('$_totalPerYear€',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: min(MediaQuery.of(context).size.width * 0.05,
                                          Theme.of(context).textTheme.headlineMedium!.fontSize!),
                                      fontWeight: FontWeight.bold))),
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
                future: subscriptionService.getAll(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  } else if (snapshot.hasError) {
                    return Center(child: Text('Erreur: ${snapshot.error}'));
                  } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Center(child: Text('Aucun abonnement trouvé'));
                  } else {
                    return ListView.builder(
                      itemCount: snapshot.data!.length,
                      itemBuilder: (context, index) {
                        final subscription = snapshot.data![index];
                        return SubscriptionCard(subscription: subscription);
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
        onPressed: () {
          showModalBottomSheet(
              context: context,
              builder: (BuildContext context) {
                return const SubscriptionModal();
              });
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
