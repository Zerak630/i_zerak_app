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

  // getSavedGasStations en renvoie sept, et la page les demande toutes.
  // L'ancienne version ne stubbait que la premiere : les six autres appels
  // levaient MissingStubError et le test echouait systematiquement.
  const savedStationCount = 7;

  setUp(() {
    client = mocks.MockClient();

    when(client.get(any)).thenAnswer((invocation) async {
      final uri = invocation.positionalArguments.first as Uri;
      final id = RegExp(r'id%3A%22(\d+)%22').firstMatch(uri.toString())?.group(1) ?? '0';
      return http.Response(
        '{"total_count":1,"results":[{"id":$id,'
        '"adresse":"ZI Ecoparc","ville":"Saumur","gazole_prix":1.5}]}',
        200,
      );
    });
  });

  testWidgets('GasStationPage affiche une carte par station', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: GasStationPage(service: GasService(client: client))));
    await tester.pumpAndSettle();

    expect(find.byType(ListTile), findsNWidgets(savedStationCount));
    expect(find.text('1.500€'), findsNWidgets(savedStationCount));
  });

  testWidgets('la page part vide avant reponse du service', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: GasStationPage(service: GasService(client: client))));

    // Aucun pumpAndSettle : les futures ne sont pas encore resolus.
    expect(find.byType(ListTile), findsNothing);
  });
}
