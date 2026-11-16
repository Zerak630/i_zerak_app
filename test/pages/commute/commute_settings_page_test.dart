import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/commute_dao.dart';
import 'package:i_zerak_app/models/gas_station_dao.dart';
import 'package:i_zerak_app/pages/commute/commute_settings_page.dart';
import 'package:i_zerak_app/services/commute_price_service.dart';

import '../../__mocks__/commute_fakes.dart';

void main() {
  late MemoryCommute store;

  setUp(() {
    store = MemoryCommute(
      settings: const CommuteSettings(distanceKm: 12.4),
      days: [
        CommuteDay(
          date: DateTime(2026, 9, 15),
          mode: CommuteMode.car,
          amount: 1.09,
          pricePerLitre: 1.689,
          priceSource: PriceSource.live,
          reasonId: CarReason.lazy,
          bucket: CarBucket.missed,
        ),
      ],
    );
  });

  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: CommuteSettingsPage(
        store: store,
        prices: CommutePriceService(
          gas: FakeGasService(stations: [station(1, {FuelType.gazole: 1.689})]),
          favorites: StaticFavorites([(id: 1, label: 'Rue A', customName: null)]),
          store: store,
          clock: () => DateTime(2026, 9, 18),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Enregistrer'));
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
  }

  testWidgets('les raisons ne se reglent plus : la question se pose a chaque trajet',
      (tester) async {
    await open(tester);

    expect(find.text('RAISONS DE PRENDRE LA VOITURE'), findsNothing);
    expect(find.text('Flemme'), findsNothing);
  });

  testWidgets('enregistrer garde les journees deja saisies telles quelles', (tester) async {
    await open(tester);

    await tester.enterText(find.byType(TextFormField).first, '20');
    await save(tester);

    expect(store.settings.distanceKm, 20);
    final day = store.days.values.single;
    expect(day.bucket, CarBucket.missed);
    expect(day.amount, 1.09);
  });
}
