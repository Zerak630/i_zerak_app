import 'package:http/http.dart' as http;
import 'package:i_zerak_app/dao/gas_station_dao.dart';
import 'package:i_zerak_app/services/gas_service.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../__mocks__/http_client_mock.dart' as mocks;

@GenerateMocks([http.Client])
void main() {
  const stationId = 49400004;
  late mocks.MockClient client;

  setUp(() {
    client = mocks.MockClient();

    when(client.get(Uri.parse(
            'https://data.economie.gouv.fr/api/explore/v2.1/catalog/datasets/prix-des-carburants-en-france-flux-instantane-v2/records?where=id%3A%22$stationId%22')))
        .thenAnswer((_) async => http.Response(
            '{"total_count":1,"results":[{"id":49400004,"adresse":"ZI EcoparcSaint Lambert des Levées", "ville": "Saumur","gazole_prix":1.5}]}',
            200));
  });

  group(
      "Testing GasStationService methods",
      () => {
            test("Request should retrieve data", () async {
              expectLater(await GasService(client: client).getGasStationById(stationId),
                  isA<GasStationDao>());
            }),
            test("Request should parse data correctly", () async {
              final sub = await GasService(client: client).getGasStationById(stationId);

              expect(sub.id, stationId);
              expect(sub.location, "ZI EcoparcSaint Lambert des Levées, Saumur");
            })
          });
}
