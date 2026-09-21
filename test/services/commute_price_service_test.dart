import 'package:i_zerak_app/models/commute_dao.dart';
import 'package:i_zerak_app/models/gas_station_dao.dart';
import 'package:i_zerak_app/services/commute_price_service.dart';
import 'package:test/test.dart';

import '../__mocks__/commute_fakes.dart';

void main() {
  final now = DateTime(2026, 9, 18, 8, 30);
  late MemoryCommute store;
  late FakeGasService gas;

  CommutePriceService service({List<SavedGasStation>? favorites}) => CommutePriceService(
        gas: gas,
        favorites: StaticFavorites(favorites ??
            [
              (id: 1, label: 'Rue A, Saumur', customName: null),
              (id: 2, label: 'Rue B, Saumur', customName: 'Leclerc'),
            ]),
        store: store,
        clock: () => now,
      );

  setUp(() {
    store = MemoryCommute();
    gas = FakeGasService(stations: [
      station(1, {FuelType.gazole: 1.749}),
      station(2, {FuelType.gazole: 1.689, FuelType.sp98: 1.899}),
    ]);
  });

  test('le plus bas parmi les stations suivies, avec le nom choisi', () async {
    final price = await service().resolve(FuelType.gazole);

    expect(price.pricePerLitre, 1.689);
    expect(price.source, PriceSource.live);
    expect(price.stationLabel, 'Leclerc');
  });

  test('le prix lu est retenu comme releve du jour', () async {
    await service().resolve(FuelType.gazole);

    final observed = await store.latestPrice(FuelType.gazole);
    expect(observed?.day, DateTime(2026, 9, 18));
    expect(observed?.price, 1.689);
  });

  test('une station qui ne vend pas le carburant est ignoree', () async {
    final price = await service().resolve(FuelType.sp98);
    expect(price.pricePerLitre, 1.899);
  });

  test('stations injoignables : le dernier prix releve', () async {
    await store.recordPrice(FuelType.gazole, DateTime(2026, 9, 17), 1.702, 'Leclerc');
    gas.fails = true;

    final price = await service().resolve(FuelType.gazole);

    expect(price.pricePerLitre, 1.702);
    expect(price.source, PriceSource.lastKnown);
    expect(price.observedOn, DateTime(2026, 9, 17));
  });

  test('aucune station ne vend ce carburant : le dernier prix releve', () async {
    await store.recordPrice(FuelType.e85, DateTime(2026, 9, 10), 0.859, null);

    final price = await service().resolve(FuelType.e85);

    expect(price.pricePerLitre, 0.859);
    expect(price.source, PriceSource.lastKnown);
  });

  test('aucun prix jamais releve : 2 €/L', () async {
    gas.fails = true;

    final price = await service().resolve(FuelType.gazole);

    expect(price.pricePerLitre, 2.0);
    expect(price.source, PriceSource.fallback);
  });

  test('un releve d un autre carburant ne sert pas', () async {
    await store.recordPrice(FuelType.sp95, DateTime(2026, 9, 17), 1.8, null);
    gas.fails = true;

    expect((await service().resolve(FuelType.gazole)).source, PriceSource.fallback);
  });

  test('sans station suivie, pas de requete', () async {
    final price = await service(favorites: const []).resolve(FuelType.gazole);

    expect(gas.calls, 0);
    expect(price.source, PriceSource.fallback);
  });

  group('jour rattrape', () {
    test('le releve du jour meme ou d avant, jamais le prix de l instant', () async {
      await store.recordPrice(FuelType.gazole, DateTime(2026, 9, 1), 1.650, null);
      await store.recordPrice(FuelType.gazole, DateTime(2026, 9, 5), 1.670, null);
      await store.recordPrice(FuelType.gazole, DateTime(2026, 9, 12), 1.720, null);

      final price = await service().resolve(FuelType.gazole, day: DateTime(2026, 9, 8));

      expect(gas.calls, 0);
      expect(price.pricePerLitre, 1.670);
    });

    test('avant tout releve, le releve le plus recent plutot que 2 €/L', () async {
      await store.recordPrice(FuelType.gazole, DateTime(2026, 9, 12), 1.720, null);

      final price = await service().resolve(FuelType.gazole, day: DateTime(2026, 8, 30));

      expect(price.pricePerLitre, 1.720);
      expect(price.source, PriceSource.lastKnown);
    });
  });
}
