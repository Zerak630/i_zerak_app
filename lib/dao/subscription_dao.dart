// ignore_for_file: constant_identifier_names

class SubscriptionDao {
  final String? id;
  String name;
  double price;
  bool isActive;
  SubscriptionType subscriptionType;
  int iconCode;

  static const String DEFAULT_NAME = "Not mentionned";
  static const double DEFAULT_PRICE = 0.0;
  static const bool DEFAULT_IS_ACTIVE = false;
  static const String DEFAULT_SUBSCRIPTION_TYPE = "WEEKLY";
  static const int DEFAULT_ICON_CODE = 0;

  SubscriptionDao(
      {this.id,
      required this.name,
      required this.price,
      required this.isActive,
      required this.subscriptionType,
      required this.iconCode});

  factory SubscriptionDao.fromJson(String? id, Map<String, dynamic> json) =>
      SubscriptionDao(
          id: id,
          name: json["name"] ?? DEFAULT_NAME,
          price: json["price"] ?? DEFAULT_PRICE,
          isActive: json["isActive"] ?? DEFAULT_IS_ACTIVE,
          subscriptionType: SubscriptionType.values
              .byName(json["subscriptionType"] ?? DEFAULT_SUBSCRIPTION_TYPE),
          iconCode: json["iconCode"] ?? DEFAULT_ICON_CODE);

  Map<String, dynamic> toJson() => {
        "name": name,
        "price": price,
        "isActive": isActive,
        "subscriptionType": subscriptionType,
        "iconCode": iconCode
      };
}

enum SubscriptionType {
  WEEKLY,
  MONTHLY,
  YEARLY;
}
