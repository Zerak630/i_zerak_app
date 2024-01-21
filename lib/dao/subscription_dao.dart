class SubscriptionDao {
  final String? id;
  String name;
  double price;
  bool isActive;
  SubscriptionType subscriptionType;
  int iconCode;

  static const String defaultName = "Not mentionned";
  static const double defaultPrice = 0.0;
  static const bool defaultIsActive = false;
  static const String defaultSubscroptionType = "WEEKLY";
  static const int defaultIconCode = 983915; // Default icon is a question mark

  SubscriptionDao(
      {this.id,
      required this.name,
      required this.price,
      required this.isActive,
      required this.subscriptionType,
      required this.iconCode});

  factory SubscriptionDao.fromJson(String? id, Map<String, dynamic> json) => SubscriptionDao(
      id: id,
      name: json["name"] ?? defaultName,
      price: json["price"] ?? defaultPrice,
      isActive: json["isActive"] ?? defaultIsActive,
      subscriptionType:
          SubscriptionType.values.byName(json["subscriptionType"] ?? defaultSubscroptionType),
      iconCode: json["iconCode"] ?? defaultIconCode);

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
