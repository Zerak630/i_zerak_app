import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:i_zerak_app/components/subscription_modal.dart';
import 'package:i_zerak_app/dao/subscription_dao.dart';

class SubscriptionsPage extends StatefulWidget {
  const SubscriptionsPage({super.key});

  @override
  State<SubscriptionsPage> createState() => _SubscriptionsPageState();
}

class _SubscriptionsPageState extends State<SubscriptionsPage> {
  final db = FirebaseFirestore.instance;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _stream;

  double _totalPerWeek = 0;
  double _totalPerMonth = 0;
  double _totalPerYear = 0;

  @override
  void initState() {
    super.initState();
    _stream = db.collection("subscriptions").snapshots();

    _stream.listen((event) {
      if (event.docs.isNotEmpty) {
        _totalPerWeek = 0;
        _totalPerMonth = 0;
        _totalPerYear = 0;

        for (DocumentSnapshot doc in event.docs) {
          SubscriptionDao sub =
              SubscriptionDao.fromJson(doc.id, doc.data() as Map<String, dynamic>);
          if (sub.isActive) {
            switch (sub.subscriptionType) {
              case SubscriptionFrequency.weekly:
                _totalPerWeek += sub.price;
                _totalPerMonth += sub.price * 4.5;
                _totalPerYear += sub.price * 52;
              case SubscriptionFrequency.monthly:
                _totalPerWeek += sub.price / 4.5;
                _totalPerMonth += sub.price;
                _totalPerYear += sub.price * 12;
              case SubscriptionFrequency.yearly:
                _totalPerWeek += sub.price / 52;
                _totalPerMonth += sub.price / 12;
                _totalPerYear += sub.price;
            }
          }
        }

        _totalPerWeek = double.parse(_totalPerWeek.toStringAsFixed(2));
        _totalPerMonth = double.parse(_totalPerMonth.toStringAsFixed(2));
        _totalPerYear = double.parse(_totalPerYear.toStringAsFixed(2));
      }

      setState(() {}); //Update _totalPerXXX displays
    });
  }

  _parseMenuValue(SubscriptionDao subscription, String value) {
    switch (value) {
      case 'edit':
        showModalBottomSheet(
            context: context,
            builder: (BuildContext context) {
              return SubscriptionModal(subscription: subscription);
            });
        break;
      case 'disable':
        db
            .collection('subscriptions')
            .doc(subscription.id)
            .update({'isActive': !subscription.isActive});
        break;
      case 'delete':
        db.collection('subscriptions').doc(subscription.id).delete();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.subscription_title,
            style: Theme.of(context).appBarTheme.titleTextStyle),
      ),
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
                              child: Text("$_totalPerWeek€",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: min(MediaQuery.of(context).size.width * 0.3,
                                          Theme.of(context).textTheme.headlineMedium!.fontSize!),
                                      fontWeight: FontWeight.bold))),
                          Expanded(
                              child: Text("$_totalPerMonth€",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: min(MediaQuery.of(context).size.width * 0.3,
                                          Theme.of(context).textTheme.headlineMedium!.fontSize!),
                                      fontWeight: FontWeight.bold))),
                          Expanded(
                              child: Text("$_totalPerYear€",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: min(MediaQuery.of(context).size.width * 0.3,
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
              child: StreamBuilder(
                stream: _stream,
                builder: (BuildContext context, AsyncSnapshot snapshot) {
                  if (snapshot.hasData) {
                    List<SubscriptionDao> buffer = [];

                    for (DocumentSnapshot doc in snapshot.data.docs) {
                      buffer.add(
                          SubscriptionDao.fromJson(doc.id, doc.data() as Map<String, dynamic>));
                    }

                    return ListView.builder(
                      itemCount: buffer.length,
                      itemBuilder: (BuildContext context, int index) {
                        return Card(
                          color: buffer[index].isActive
                              ? Theme.of(context).colorScheme.surface
                              : Theme.of(context).colorScheme.onInverseSurface,
                          child: ListTile(
                            title: Text(buffer[index].name,
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(
                              "${buffer[index].price}€ ${SubscriptionFrequency.getLocaleName(context, buffer[index].subscriptionType)}",
                              style: const TextStyle(fontStyle: FontStyle.italic),
                            ),
                            leading:
                                Icon(IconData(buffer[index].iconCode, fontFamily: 'MaterialIcons')),
                            trailing: PopupMenuButton(
                              itemBuilder: (BuildContext context) {
                                return [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Row(
                                      children: [
                                        const Padding(
                                          padding: EdgeInsets.all(4.0),
                                          child: Icon(Icons.edit),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.all(4.0),
                                          child: Text(AppLocalizations.of(context)!.edit),
                                        ),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'disable',
                                    child: Row(
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.all(4.0),
                                          child: Icon(buffer[index].isActive
                                              ? Icons.do_disturb_alt_rounded
                                              : Icons.circle_outlined),
                                        ),
                                        Padding(
                                            padding: const EdgeInsets.all(4.0),
                                            child: Text(buffer[index].isActive
                                                ? AppLocalizations.of(context)!.disable
                                                : AppLocalizations.of(context)!.enable)),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Row(children: [
                                      const Padding(
                                        padding: EdgeInsets.all(4.0),
                                        child: Icon(Icons.delete),
                                      ),
                                      Padding(
                                          padding: const EdgeInsets.all(4.0),
                                          child: Text(AppLocalizations.of(context)!.delete)),
                                    ]),
                                  ),
                                ];
                              },
                              onSelected: (value) => _parseMenuValue(buffer[index], value),
                            ),
                          ),
                        );
                      },
                    );
                  } else {
                    return const Center(
                      child: CircularProgressIndicator(),
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
