import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:i_zerak_app/models/gas_station_dao.dart';

class GasService {
  final http.Client client;

  GasService({http.Client? client}) : client = client ?? http.Client();

  Future<List<int>> getSavedGasStations() async {
    //TODO: Store favorite gas stations in a database
    final List<int> savedGasStations = [
      49400004,
      49412001,
      49400007,
      49400006,
      79100003,
      79100001,
      79100006
    ];

    return Future.value(savedGasStations);
  }

  Future<GasStationDao> getGasStationById(int id) async {
    final response = await client.get(Uri.parse(
        'https://data.economie.gouv.fr/api/explore/v2.1/catalog/datasets/prix-des-carburants-en-france-flux-instantane-v2/records?where=id%3A%22$id%22'));

    if (response.statusCode == 200) {
      Map<String, dynamic> data = json.decode(response.body);

      if (data['total_count'] > 1) {
        throw Exception('More than one result found for this ID');
      }

      return GasStationDao.fromJson(data['results'][0]);
    } else {
      throw Exception('Failed to load data from API');
    }
  }
}
