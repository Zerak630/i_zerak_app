import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/commute_dao.dart';
import 'package:i_zerak_app/models/gas_station_dao.dart';
import 'package:i_zerak_app/pages/commute/commute_import_page.dart';
import 'package:i_zerak_app/services/commute_price_service.dart';
import 'package:i_zerak_app/services/timeline_import.dart';

import '../../__mocks__/commute_fakes.dart';

final _d14 = DateTime(2026, 9, 14);
final _d15 = DateTime(2026, 9, 15);
final _d16 = DateTime(2026, 9, 16);
final _d19 = DateTime(2026, 9, 19);

void main() {
  final now = DateTime(2026, 9, 21, 20);
  late MemoryCommute store;

  final found = [
    // Lundi 14 : domicile-travail.
    TimelineBikeDay(date: _d14, km: 14, legs: 2, commute: true),
    // Mardi 15 : domicile-travail, mais deja enregistre.
    TimelineBikeDay(date: _d15, km: 7, legs: 1, commute: true),
    // Mercredi 16 : autre sortie en semaine.
    TimelineBikeDay(date: _d16, km: 3, legs: 1, commute: false),
    // Samedi 19 : sortie du week-end, ecartee.
    TimelineBikeDay(date: _d19, km: 42, legs: 1, commute: false),
  ];

  setUp(() {
    store = MemoryCommute(
      settings: const CommuteSettings(distanceKm: 14, consumption: 5.2),
      days: [
        CommuteDay(
          date: _d15,
          mode: CommuteMode.car,
          amount: 1.2,
          pricePerLitre: 1.7,
          priceSource: PriceSource.live,
          reasonId: CarReason.lazy,
          bucket: CarBucket.missed,
        ),
      ],
    );
  });

  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: CommuteImportPage(
        found: found,
        store: store,
        prices: CommutePriceService(
          gas: FakeGasService(stations: [station(1, {FuelType.gazole: 1.689})]),
          favorites: StaticFavorites([(id: 1, label: 'Rue A', customName: null)]),
          store: store,
          clock: () => now,
        ),
        clock: () => now,
      ),
    ));
    await tester.pumpAndSettle();
  }

  bool? checked(WidgetTester tester, String day) => tester
      .widget<CheckboxListTile>(find.ancestor(of: find.textContaining(day), matching: find.byType(CheckboxListTile)))
      .value;

  testWidgets('domicile-travail coche, autres sorties decochees, week-end ecarte', (tester) async {
    await open(tester);

    expect(checked(tester, 'lun. 14'), isTrue);
    expect(checked(tester, 'mer. 16'), isFalse);
    expect(find.textContaining('sam. 19'), findsNothing);
    expect(find.text('Importer 1 jour'), findsOneWidget);
  });

  testWidgets('un jour deja enregistre est grise et jamais remplace', (tester) async {
    await open(tester);

    expect(find.text('déjà enregistré'), findsOneWidget);
    final tile = tester.widget<CheckboxListTile>(
        find.ancestor(of: find.textContaining('mar. 15'), matching: find.byType(CheckboxListTile)));
    expect(tile.onChanged, isNull);
  });

  testWidgets('l import ecrit les jours coches, au prix d aujourd hui', (tester) async {
    await open(tester);

    await tester.tap(find.textContaining('mer. 16'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Importer 2 jours'));
    await tester.pumpAndSettle();

    final imported = store.days.values.where((d) => d.imported).toList();
    expect(imported.map((d) => d.date).toSet(), {_d14, _d16});
    for (final day in imported) {
      expect(day.isBike, isTrue);
      expect(day.pricePerLitre, 1.689);
      // 14 km x 5,2 L/100 km x 1,689 €/L = 1,2296 €.
      expect(day.amount, 1.23);
    }
    expect(store.days[dayKey(_d15)]!.mode, CommuteMode.car);
  });
}


