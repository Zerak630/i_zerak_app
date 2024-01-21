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

  @override
  void initState() {
    super.initState();
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
      body: StreamBuilder(
        stream: db.collection("subscriptions").snapshots(),
        builder: (BuildContext context, AsyncSnapshot snapshot) {
          if (snapshot.hasData) {
            List<SubscriptionDao> buffer = [];

            for (DocumentSnapshot doc in snapshot.data.docs) {
              buffer.add(SubscriptionDao.fromJson(
                  doc.id, doc.data() as Map<String, dynamic>));
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
                    leading: Icon(IconData(buffer[index].iconCode,
                        fontFamily: 'MaterialIcons')),
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
                                    child: Text(buffer[index].isActive
                                        ? 'Disable'
                                        : 'Enable')),
                              ],
                            ),
                          ),
                        ];
                      },
                      onSelected: (value) =>
                          _parseMenuValue(buffer[index], value),
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
