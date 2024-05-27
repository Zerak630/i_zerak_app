import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:i_zerak_app/dao/subscription_dao.dart';
import 'package:test/test.dart';

void main() {
  const url = 'http://192.168.1.4:8080/subscriptions';

  test("Request should retrieve data", () async {
    final response = await http.get(Uri.parse(url));
    print(response.body);

    expect(response.statusCode, equals(200));
  });

  test("Request should parse data correctly", () async {
    final response = await http.get(Uri.parse(url));

    print(response.body);

    final sub = SubscriptionDao.fromJson(null, jsonDecode(response.body));

    print(sub.toString());

    expect(response.statusCode, equals(200));
  });
}
