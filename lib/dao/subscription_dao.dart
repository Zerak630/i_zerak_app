class SubscriptionDao {
  final String? id;
  String name;
  double price;
  bool isActive;
  SubscriptionType subscriptionType;
  int iconCode;

  SubscriptionDao(
      {this.id,
      this.name = "",
      this.price = 0.0,
      this.isActive = true,
      this.subscriptionType = SubscriptionType.weekly,
      this.iconCode = 983915});

  factory SubscriptionDao.fromJson(String? id, Map<String, dynamic> json) => SubscriptionDao(
      id: id,
      name: json["name"],
      price: json["price"],
      isActive: json["isActive"],
      subscriptionType: SubscriptionType.values.byName(json["subscriptionType"]),
      iconCode: json["iconCode"]);

  Map<String, dynamic> toJson() => {
        "name": name,
        "price": price,
        "isActive": isActive,
        "subscriptionType": subscriptionType.name,
        "iconCode": iconCode
      };
}

enum SubscriptionType {
  weekly,
  monthly,
  yearly;
}
