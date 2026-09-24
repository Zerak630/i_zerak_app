import 'package:i_zerak_app/models/subscription_dao.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_subscriptions.dart';

/// Depot des abonnements en memoire : le comportement Hive est verifie a part.
class MemorySubscriptions implements ISubscriptions {
  MemorySubscriptions([List<Subscription>? items])
      : items = {
          for (final item in items ?? const <Subscription>[]) item.id ?? item.name: item,
        };

  final Map<String, Subscription> items;
  final List<SubscriptionCategory> custom = [];
  int _sequence = 0;

  @override
  Future<List<Subscription>> getAll() async => [...items.values];

  @override
  Future<void> updateSubscription(Subscription subscription) async {
    subscription.id ??= 'id-${++_sequence}';
    items[subscription.id!] = subscription;
  }

  @override
  Future<void> delete(String id) async => items.remove(id);

  @override
  Future<List<SubscriptionCategory>> getCategories() async =>
      [...SubscriptionCategory.builtIn, ...custom];

  @override
  Future<void> saveCategory(SubscriptionCategory category) async {
    custom.removeWhere((existing) => existing.id == category.id);
    custom.add(category);
  }
}

Subscription sub(
  String name,
  double price, {
  SubscriptionFrequency frequency = SubscriptionFrequency.monthly,
  String? category,
  DateTime? next,
  bool active = true,
  String? icon,
}) =>
    Subscription(
      id: name,
      name: name,
      price: price,
      subscriptionType: frequency,
      categoryId: category,
      nextPayment: next,
      isActive: active,
      iconId: icon,
    );
