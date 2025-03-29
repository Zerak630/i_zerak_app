import 'package:i_zerak_app/models/subscription_dao.dart';

abstract class ISubscriptions {
  Future<List<Subscription>> getAll();
  void updateSubscription(Subscription subscription);
}
