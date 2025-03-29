import 'package:hive/hive.dart';
import 'package:i_zerak_app/models/subscription_dao.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_subscriptions.dart';

class SubscriptionAdapter implements ISubscriptions {
  final Box<Subscription> _box;

  SubscriptionAdapter(this._box);

  @override
  Future<List<Subscription>> getAll() {
    return Future.value(_box.values.toList());
  }

  @override
  void updateSubscription(Subscription subscription) async {
    await _box.put(subscription.id, subscription);
  }
}
