import 'package:i_zerak_app/models/subscription_dao.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_subscriptions.dart';

class SubscriptionService implements ISubscriptions {
  @override
  Future<List<Subscription>> getAll() {
    // TODO: Faire un vrai stockage
    return Future.value([
      Subscription(
          id: '10',
          name: 'Netflix',
          iconCode: 450,
          isActive: true,
          price: 10.25,
          subscriptionType: SubscriptionFrequency.monthly),
      Subscription(
          id: '11',
          name: 'Prixtel',
          iconCode: 450,
          isActive: true,
          price: 10.25,
          subscriptionType: SubscriptionFrequency.monthly),
      Subscription(
          id: '12',
          name: 'Deezer',
          iconCode: 450,
          isActive: true,
          price: 10.25,
          subscriptionType: SubscriptionFrequency.monthly)
    ]);
  }

  @override
  Future<void> updateSubscription(Subscription subscription) async {
    //TODO
  }

  @override
  Future<void> delete(String id) async {
    //TODO
  }
}
