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

  /// Ouvre le menu de la raison affichee sous ce libelle.
  Future<void> openMenu(WidgetTester tester, String label) async {
    final row = find.ancestor(of: find.text(label), matching: find.byType(Row)).first;
    await tester.tap(find.descendant(of: row, matching: find.byType(PopupMenuButton<String>)));
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Enregistrer'));
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
  }

  testWidgets('une raison deja utilisee ne peut pas etre supprimee', (tester) async {
    await open(tester);
    expect(find.text('Utilisée par 1 jour'), findsOneWidget);

    await openMenu(tester, 'Flemme');
    final item = tester.widget<PopupMenuItem<String>>(
        find.widgetWithText(PopupMenuItem<String>, 'Supprimer (déjà utilisée)'));

    expect(item.enabled, isFalse);
  });

  testWidgets('une raison inutilisee se supprime, meme livree', (tester) async {
    await open(tester);

    await openMenu(tester, 'Courses');
    await tester.tap(find.text('Supprimer'));
    await tester.pumpAndSettle();
    await save(tester);

    expect(store.settings.reasons.map((r) => r.id), [CarReason.sport, CarReason.lazy]);
  });

  testWidgets('une raison se renomme, meme utilisee', (tester) async {
    await open(tester);

    await openMenu(tester, 'Flemme');
    await tester.tap(find.text('Renommer'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Pas motivé');
    await tester.tap(find.widgetWithText(TextButton, 'Enregistrer'));
    await tester.pumpAndSettle();
    await save(tester);

    final lazy = store.settings.reasons.firstWhere((r) => r.id == CarReason.lazy);
    expect(lazy.label, 'Pas motivé');
    // La journee garde sa raison et sa cagnotte : seul le nom affiche change.
    expect(store.days.values.single.reasonId, CarReason.lazy);
  });

  testWidgets('vider le nom rend a une raison livree son nom d origine', (tester) async {
    store.settings = CommuteSettings(
      distanceKm: 12.4,
      reasons: [CarReason.defaults.first.withLabel('Escalade')],
    );
    await open(tester);

    await openMenu(tester, 'Escalade');
    await tester.tap(find.text('Renommer'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '');
    await tester.tap(find.widgetWithText(TextButton, 'Enregistrer'));
    await tester.pumpAndSettle();

    expect(find.text('Sport le soir'), findsOneWidget);
  });
}
