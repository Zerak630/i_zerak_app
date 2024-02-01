import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class SubscriptionDao {
  final String? id;
  String name;
  double price;
  bool isActive;
  SubscriptionFrequency subscriptionType;
  int iconCode;

  SubscriptionDao(
      {this.id,
      this.name = "",
      this.price = 0.0,
      this.isActive = true,
      this.subscriptionType = SubscriptionFrequency.weekly,
      this.iconCode = 983915});

  factory SubscriptionDao.fromJson(String? id, Map<String, dynamic> json) => SubscriptionDao(
      id: id,
      name: json["name"],
      price: double.parse(json["price"].toString()),
      isActive: json["isActive"],
      subscriptionType: SubscriptionFrequency.values.byName(json["subscriptionType"]),
      iconCode: json["iconCode"]);

  Map<String, dynamic> toJson() => {
        "name": name,
        "price": price,
        "isActive": isActive,
        "subscriptionType": subscriptionType.name,
        "iconCode": iconCode
      };
}

enum SubscriptionFrequency {
  weekly,
  monthly,
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
