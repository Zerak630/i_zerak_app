import 'package:i_zerak_app/models/subscription_dao.dart';

abstract class ISubscriptions {
  Future<List<Subscription>> getAll();

  /// Cree l'abonnement s'il n'a pas encore d'identifiant, le met a jour sinon.
  Future<void> updateSubscription(Subscription subscription);

  Future<void> delete(String id);

  /// Les categories livrees, suivies de celles ajoutees a la main.
  Future<List<SubscriptionCategory>> getCategories();

  /// Ajoute une categorie, ou remplace celle qui porte le meme identifiant.
  /// Une categorie livree n'est pas stockee : elle existe deja dans le code.
  Future<void> saveCategory(SubscriptionCategory category);
}
