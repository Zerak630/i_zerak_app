import 'package:i_zerak_app/models/commute_dao.dart';
import 'package:i_zerak_app/models/gas_station_dao.dart';
import 'package:i_zerak_app/services/gas_service.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_commute.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_gas_stations.dart';

/// Depot des trajets en memoire : le comportement Hive est verifie a part.
class MemoryCommute implements ICommute {
  MemoryCommute({CommuteSettings? settings, List<CommuteDay>? days, List<Goal>? goals})
      : settings = settings ?? const CommuteSettings(),
        days = {for (final day in days ?? const <CommuteDay>[]) dayKey(day.date): day},
        goals = {for (final goal in goals ?? const <Goal>[]) goal.id: goal};

  CommuteSettings settings;
  final Map<String, CommuteDay> days;
  final Map<String, Goal> goals;
  final Map<String, PriceObservation> prices = {};

  @override
  Future<CommuteSettings> readSettings() async => settings;

  @override
  Future<void> saveSettings(CommuteSettings settings) async => this.settings = settings;

  @override
  Future<List<CommuteDay>> getDays() async => [...days.values];

  @override
  Future<void> saveDay(CommuteDay day) async => days[dayKey(day.date)] = day;

  @override
  Future<void> deleteDay(DateTime date) async => days.remove(dayKey(date));

  @override
  Future<List<Goal>> getGoals() async => [...goals.values];

  @override
  Future<void> saveGoal(Goal goal) async => goals[goal.id] = goal;

  @override
  Future<void> deleteGoal(String id) async => goals.remove(id);

  @override
  Future<void> recordPrice(FuelType fuel, DateTime day, double price, String? station) async =>
      prices['${fuel.name}:${dayKey(day)}'] = (day: dateOnly(day), price: price, station: station);

  @override
  Future<PriceObservation?> latestPrice(FuelType fuel, {DateTime? onOrBefore}) async {
    PriceObservation? latest;
    for (final entry in prices.entries) {
      if (!entry.key.startsWith('${fuel.name}:')) {
        continue;
      }
      final observation = entry.value;
      if (onOrBefore != null && observation.day.isAfter(dateOnly(onOrBefore))) {
        continue;
      }
      if (latest == null || observation.day.isAfter(latest.day)) {
        latest = observation;
      }
    }
    return latest;
  }
}

/// Stations favorites figees.
class StaticFavorites implements IGasStations {
  StaticFavorites(this.stations);

  final List<SavedGasStation> stations;

  @override
  Future<List<SavedGasStation>> getAll() async => [...stations];

  @override
  Future<void> add(SavedGasStation station) async {}

  @override
  Future<void> delete(int id) async {}

  @override
  Future<void> rename(int id, String? name) async {}

  @override
  Future<FuelType> readFuel() async => FuelType.gazole;

  @override
  Future<void> saveFuel(FuelType fuel) async {}
}

/// Renvoie les stations donnees, ou leve comme une API injoignable.
class FakeGasService extends GasService {
  FakeGasService({this.stations = const [], this.fails = false});

  List<GasStationDao> stations;
  bool fails;
  int calls = 0;

  @override
  Future<List<GasStationDao>> fetchByIds(List<int> ids) async {
    calls++;
    if (fails) {
      throw const GasServiceException('injoignable');
    }
    return [for (final station in stations) if (ids.contains(station.id)) station];
  }
}

GasStationDao station(int id, Map<FuelType, double> prices, {String address = 'Rue'}) =>
    GasStationDao(id: id, address: address, city: 'Saumur', postalCode: '49400', prices: prices);
