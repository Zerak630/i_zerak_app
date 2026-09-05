import 'package:i_zerak_app/models/subscription_dao.dart';

abstract class ISubscriptions {
  Future<List<Subscription>> getAll();

  /// Cree l'abonnement s'il n'a pas encore d'identifiant, le met a jour sinon.
  Future<void> updateSubscription(Subscription subscription);

  Future<void> delete(String id);
}
