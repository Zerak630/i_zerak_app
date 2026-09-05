import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:hive/hive.dart';

/// Les `TypeAdapter` correspondants sont ecrits a la main dans
/// `lib/services/repositories/hive/type_adapters.dart`. Toute modification des
/// champs ci-dessous doit y etre repercutee.
@HiveType(typeId: 0)
class Subscription {
  /// Nul tant que l'abonnement n'a pas ete enregistre une premiere fois ;
  /// `HiveSubscriptionRepository` lui attribue alors un identifiant. Mutable
  /// pour cette raison : un `id` final rendait toute persistance impossible.
  @HiveField(0)
  String? id;

  @HiveField(1)
  String name;

  @HiveField(2)
  double price;

  @HiveField(3)
  bool isActive;

  @HiveField(4)
  SubscriptionFrequency subscriptionType;

  @HiveField(5)
  int iconCode;

  /// `Icons.subscriptions.codePoint` — repli quand aucune icone n'a ete choisie.
  static const int defaultIconCode = 983915;

  Subscription(
      {this.id,
      this.name = '',
      this.price = 0.0,
      this.isActive = true,
      this.subscriptionType = SubscriptionFrequency.weekly,
      this.iconCode = defaultIconCode});

  factory Subscription.fromJson(String? id, Map<String, dynamic> json) => Subscription(
      id: id,
      name: json['name'],
      price: double.parse(json['price'].toString()),
      isActive: json['isActive'],
      subscriptionType: SubscriptionFrequency.values.byName(json['subscriptionType']),
      iconCode: json['iconCode']);

  Map<String, dynamic> toJson() => {
        'name': name,
        'price': price,
        'isActive': isActive,
        'subscriptionType': subscriptionType.name,
        'iconCode': iconCode
      };
}

@HiveType(typeId: 1)
enum SubscriptionFrequency {
  @HiveField(0)
  weekly,
  @HiveField(1)
  monthly,
  @HiveField(2)
  yearly;

  static String getLocaleName(context, SubscriptionFrequency type) {
    switch (type) {
      case SubscriptionFrequency.weekly:
        return AppLocalizations.of(context)!.per_week;
      case SubscriptionFrequency.monthly:
        return AppLocalizations.of(context)!.per_month;
      case SubscriptionFrequency.yearly:
        return AppLocalizations.of(context)!.per_year;
    }
  }

  static String getLocaleAdjective(context, SubscriptionFrequency type) {
    switch (type) {
      case SubscriptionFrequency.weekly:
        return AppLocalizations.of(context)!.per_week_adjective;
      case SubscriptionFrequency.monthly:
        return AppLocalizations.of(context)!.per_month_adjective;
      case SubscriptionFrequency.yearly:
        return AppLocalizations.of(context)!.per_year_adjective;
    }
  }
}
