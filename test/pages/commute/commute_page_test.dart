import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/commute_dao.dart';
import 'package:i_zerak_app/models/gas_station_dao.dart';
import 'package:i_zerak_app/pages/commute/commute_page.dart';
import 'package:i_zerak_app/services/commute_price_service.dart';

import '../../__mocks__/commute_fakes.dart';

Widget wrap(Widget child) => MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

void main() {
  final now = DateTime(2026, 9, 18, 8, 30);
  late MemoryCommute store;
  late FakeGasService gas;

  CommutePage page() => CommutePage(
        store: store,
        prices: CommutePriceService(
          gas: gas,
          favorites: StaticFavorites([(id: 1, label: 'Rue A, Saumur', customName: 'Leclerc')]),
          store: store,
          clock: () => now,
        ),
        clock: () => now,
      );

  setUp(() {
    store = MemoryCommute(settings: const CommuteSettings(distanceKm: 12.4, consumption: 5.2));
    gas = FakeGasService(stations: [station(1, {FuelType.gazole: 1.689})]);
  });

  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(wrap(page()));
    await tester.pumpAndSettle();
  }

  testWidgets('ouvert depuis le bouton Voiture du widget, la question est posee',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(wrap(CommutePage(
      store: store,
      prices: CommutePriceService(
        gas: gas,
        favorites: StaticFavorites([(id: 1, label: 'Rue A, Saumur', customName: 'Leclerc')]),
        store: store,
        clock: () => now,
      ),
      clock: () => now,
      askCarOnOpen: true,
    )));
    await tester.pumpAndSettle();

    expect(find.text('Est-ce que tu aurais pu prendre le vélo à la place ?'), findsOneWidget);
    expect(find.text('Oui'), findsOneWidget);
    expect(find.text('Non'), findsOneWidget);
  });

  testWidgets('sans distance, l onglet demande de regler le trajet', (tester) async {
    store.settings = const CommuteSettings();
    await open(tester);

    expect(find.text('Réglez votre trajet'), findsOneWidget);
    expect(find.text('À vélo'), findsNothing);
  });

  testWidgets('un appui sur « À vélo » alimente la cagnotte, et s annule', (tester) async {
    await open(tester);
    expect(find.textContaining('Gazole au plus bas'), findsOneWidget);

    await tester.tap(find.text('À vélo'));
    await tester.pumpAndSettle();

    expect(store.days.values.single.amount, 1.09);
    expect(find.text('Vélo, aujourd’hui'), findsOneWidget);
    expect(find.textContaining('Vélo enregistré'), findsOneWidget);
    expect(find.widgetWithText(SnackBarAction, 'OK'), findsOneWidget);
    expect(find.text('À vélo'), findsNothing, reason: 'une seule journee par jour');

    // Un accuse de reception, pas une question : il part seul.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.textContaining('Vélo enregistré'), findsNothing);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Annuler'));
    await tester.pumpAndSettle();

    expect(store.days, isEmpty);
    expect(find.text('À vélo'), findsOneWidget);
  });

  testWidgets('« oui, le velo etait possible » range la voiture en economie loupee',
      (tester) async {
    await open(tester);

    await tester.tap(find.text('En voiture'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Oui'));
    await tester.pumpAndSettle();

    final day = store.days.values.single;
    expect(day.mode, CommuteMode.car);
    expect(day.bucket, CarBucket.missed);
    expect(find.text('Voiture, aujourd’hui · Économie loupée'), findsOneWidget);
  });

  testWidgets('« non » range la voiture en depense obligatoire', (tester) async {
    await open(tester);

    await tester.tap(find.text('En voiture'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Non'));
    await tester.pumpAndSettle();

    final day = store.days.values.single;
    expect(day.bucket, CarBucket.essential);
    expect(find.text('Voiture, aujourd’hui · Dépense obligatoire'), findsOneWidget);
  });

  testWidgets('le teletravail s enregistre sans rien rapporter, et s annule', (tester) async {
    await open(tester);

    await tester.tap(find.text('Télétravail'));
    await tester.pumpAndSettle();

    final day = store.days.values.single;
    expect(day.isRemote, isTrue);
    expect(day.amount, 0);
    expect(find.text('Télétravail, aujourd’hui'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Annuler'));
    await tester.pumpAndSettle();
    expect(store.days, isEmpty);
  });

  testWidgets('la carte de cagnotte mene aux objectifs quand on peut y aller', (tester) async {
    store = MemoryCommute(
      settings: const CommuteSettings(distanceKm: 12.4, consumption: 5.2),
      goals: [
        Goal(
          id: 'sacoche',
          name: 'Sacoche',
          target: 35,
          kind: GoalKind.purchase,
          icon: GoalIcon.bag,
          createdAt: DateTime(2026, 9, 1),
        ),
      ],
    );
    var opened = 0;
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(wrap(CommutePage(
      store: store,
      prices: CommutePriceService(
        gas: gas,
        favorites: StaticFavorites([(id: 1, label: 'Rue A, Saumur', customName: 'Leclerc')]),
        store: store,
        clock: () => now,
      ),
      clock: () => now,
      onOpenGoals: () => opened++,
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('1 objectif en cours'));
    await tester.pumpAndSettle();

    expect(opened, 1);
  });

  testWidgets('sans moyen d y aller, la ligne des objectifs disparait', (tester) async {
    await open(tester);

    expect(find.textContaining('objectif'), findsNothing);
  });

  testWidgets('la serie en cours mene a la regularite', (tester) async {
    store = MemoryCommute(
      settings: const CommuteSettings(distanceKm: 12.4, consumption: 5.2),
      days: [
        for (var d = 14; d <= 17; d++)
          CommuteDay(
            date: DateTime(2026, 9, d),
            mode: CommuteMode.bike,
            amount: 1.09,
            pricePerLitre: 1.689,
            priceSource: PriceSource.live,
          ),
      ],
    );
    await open(tester);

    expect(find.text('série de 4 jours'), findsOneWidget);

    await tester.tap(find.text('Régularité'));
    await tester.pumpAndSettle();

    expect(find.text('PAR JOUR DE LA SEMAINE'), findsOneWidget);
  });
}
