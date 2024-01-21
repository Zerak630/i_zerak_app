import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:i_zerak_app/components/subscription_modal.dart';
import 'package:i_zerak_app/dao/subscription_dao.dart';

class SubscriptionsPage extends StatefulWidget {
  const SubscriptionsPage({Key? key}) : super(key: key);

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
              case SubscriptionType.WEEKLY:
                _totalPerWeek += sub.price;
                _totalPerMonth += sub.price * 4.5;
                _totalPerYear += sub.price * 52;
              case SubscriptionType.MONTHLY:
                _totalPerWeek += sub.price / 4.5;
                _totalPerMonth += sub.price;
                _totalPerYear += sub.price * 12;
              case SubscriptionType.YEARLY:
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
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Subscriptions'),
      ),
      body: Column(
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
                              style: Theme.of(context).textTheme.headlineMedium),
                        ),
                        Expanded(
                          child: Text("$_totalPerMonth€",
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.headlineMedium),
                        ),
                        Expanded(
                          child: Text("$_totalPerYear€",
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.headlineMedium),
                        ),
                      ],
                    )),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Expanded(
                      child: Text("/week",
                          textAlign: TextAlign.center,
                          style: TextStyle(fontStyle: FontStyle.italic)),
                    ),
                    Expanded(
                      child: Text("/month",
                          textAlign: TextAlign.center,
                          style: TextStyle(fontStyle: FontStyle.italic)),
                    ),
                    Expanded(
                      child: Text("/year",
                          textAlign: TextAlign.center,
                          style: TextStyle(fontStyle: FontStyle.italic)),
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
                    buffer
                        .add(SubscriptionDao.fromJson(doc.id, doc.data() as Map<String, dynamic>));
                  }

                  return ListView.builder(
                    itemCount: buffer.length,
                    itemBuilder: (BuildContext context, int index) {
                      return Card(
                        color: buffer[index].isActive
                            ? Theme.of(context).colorScheme.surface
                            : Theme.of(context).colorScheme.surface.withOpacity(0.5),
                        child: ListTile(
                          title: Text(buffer[index].name,
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(
                            "${buffer[index].price}€ / ${parseDate(buffer[index].subscriptionType)}",
                            style: const TextStyle(fontStyle: FontStyle.italic),
                          ),
                          leading:
                              Icon(IconData(buffer[index].iconCode, fontFamily: 'MaterialIcons')),
                          trailing: PopupMenuButton(
                            itemBuilder: (BuildContext context) {
                              return [
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      Padding(
                                        padding: EdgeInsets.all(4.0),
                                        child: Icon(Icons.edit),
                                      ),
                                      Padding(
                                        padding: EdgeInsets.all(4.0),
                                        child: Text('Edit'),
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
                                          child:
                                              Text(buffer[index].isActive ? 'Disable' : 'Enable')),
                                    ],
                                  ),
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
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showModalBottomSheet(
              context: context,
              builder: (BuildContext context) {
                return SubscriptionModal();
              });
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  parseDate(SubscriptionType subscriptionType) {
    switch (subscriptionType) {
      case SubscriptionType.WEEKLY:
        return 'week';
      case SubscriptionType.MONTHLY:
        return 'month';
      case SubscriptionType.YEARLY:
        return 'year';
    }
  }
}
