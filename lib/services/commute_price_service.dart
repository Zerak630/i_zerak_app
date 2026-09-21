import 'package:i_zerak_app/models/commute_dao.dart';
import 'package:i_zerak_app/models/gas_station_dao.dart';
import 'package:i_zerak_app/services/gas_service.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_commute.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_gas_stations.dart';

/// Choisit le prix du litre qui valorise un trajet.
///
/// Dans l'ordre :
///   1. pour aujourd'hui, le plus bas parmi les stations suivies, lu a
///      l'instant — et retenu comme releve du jour ;
///   2. sinon — stations injoignables, aucune ne vendant ce carburant, ou jour
///      passe que l'API ne sait pas dater — le dernier prix releve au plus
///      tard ce jour-la, a defaut le plus recent tout court ;
///   3. sinon `kFallbackFuelPrice`.
///
/// Le service ne leve jamais : un trajet doit toujours pouvoir s'enregistrer,
/// la source du prix dit a l'ecran ce qu'il vaut.
class CommutePriceService {
  CommutePriceService({
    required this.gas,
    required this.favorites,
    required this.store,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final GasService gas;
  final IGasStations favorites;
  final ICommute store;
  final DateTime Function() _clock;

  Future<ResolvedPrice> resolve(FuelType fuel, {DateTime? day}) async {
    final today = dateOnly(_clock());
    final target = day == null ? today : dateOnly(day);

    if (target == today) {
      final live = await _cheapestNow(fuel);
      if (live != null) {
        await store.recordPrice(fuel, today, live.pricePerLitre, live.stationLabel);
        return live;
      }
    }

    final observed =
        await store.latestPrice(fuel, onOrBefore: target) ?? await store.latestPrice(fuel);
    if (observed != null) {
      return ResolvedPrice(
        pricePerLitre: observed.price,
        source: PriceSource.lastKnown,
        stationLabel: observed.station,
        observedOn: observed.day,
      );
    }
    return const ResolvedPrice.fallback();
  }

  Future<ResolvedPrice?> _cheapestNow(FuelType fuel) async {
    final saved = await favorites.getAll();
    if (saved.isEmpty) {
      return null;
    }

    final List<GasStationDao> stations;
    try {
      stations = await gas.fetchByIds([for (final station in saved) station.id]);
    } on GasServiceException {
      return null;
    }

    GasStationDao? cheapest;
    for (final station in stations) {
      final price = station.priceOf(fuel);
      if (price != null && (cheapest == null || price < cheapest.priceOf(fuel)!)) {
        cheapest = station;
      }
    }
    if (cheapest == null) {
      return null;
    }

    // Le nom choisi dans l'onglet Carburants, s'il y en a un : c'est ainsi que
    // l'utilisateur reconnait la station.
    final match = saved.where((station) => station.id == cheapest!.id);
    final label = match.isEmpty
        ? cheapest.location
        : displayNameOf(match.first, fresh: cheapest.location);

    return ResolvedPrice(
      pricePerLitre: cheapest.priceOf(fuel)!,
      source: PriceSource.live,
      stationLabel: label,
      observedOn: dateOnly(_clock()),
    );
  }
}
