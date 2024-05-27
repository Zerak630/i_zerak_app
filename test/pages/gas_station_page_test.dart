import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:i_zerak_app/pages/gas_station_page.dart';
import 'package:i_zerak_app/services/gas_service.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import '../__mocks__/http_client_mock.dart' as mocks;

@GenerateMocks([http.Client])
void main() {
  late mocks.MockClient client;

  setUp(() {
    client = mocks.MockClient();

    when(client.get(Uri.parse(
            'https://data.economie.gouv.fr/api/explore/v2.1/catalog/datasets/prix-des-carburants-en-france-flux-instantane-v2/records?where=id%3A%2249400004%22')))
        .thenAnswer((_) async => http.Response(
            '{"total_count":1,"results":[{"id":49400004,"adresse":"ZI EcoparcSaint Lambert des Levées", "ville": "Saumur","gazole_prix":1.5}]}',
            200));
  });

  testWidgets('GasStationPage renders correctly', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: GasStationPage(service: GasService(client: client))));

    //expect(find.text('Gas Station'), findsOneWidget);
    //expect(find.byType(ListView), findsOneWidget);
  });
}
