import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/commute_dao.dart';
import 'package:i_zerak_app/models/gas_station_dao.dart';
import 'package:i_zerak_app/pages/goals/goals_page.dart';
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

  CommuteDay bike(DateTime date, double amount) => CommuteDay(
        date: date,
        mode: CommuteMode.bike,
        amount: amount,
        pricePerLitre: 1.689,
        priceSource: PriceSource.live,
      );

  /// [count] journees a velo consecutives, la derniere aujourd'hui.
  List<CommuteDay> history(int count, {double amount = 1}) => [
        for (var back = count - 1; back >= 0; back--)
          bike(DateTime(2026, 9, 18).subtract(Duration(days: back)), amount),
      ];

  Goal purchase(String id, String name, double target) => Goal(
        id: id,
        name: name,
        target: target,
        kind: GoalKind.purchase,
        icon: GoalIcon.bag,
        createdAt: DateTime(2026, 9, 1),
      );

  GoalsPage page() => GoalsPage(
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
    await tester.binding.setSurfaceSize(const Size(420, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(wrap(page()));
    await tester.pumpAndSettle();
  }

  testWidgets('sans objectif, la page dit a quoi ils servent', (tester) async {
    await open(tester);

    expect(find.text('Aucun objectif en cours'), findsOneWidget);
    expect(find.textContaining('donne une date à la cagnotte'), findsOneWidget);
  });

  testWidgets('le rythme se mesure et s affiche par mois', (tester) async {
    store = MemoryCommute(
      settings: const CommuteSettings(distanceKm: 12.4, consumption: 5.2),
      days: history(30),
    );
    await open(tester);

    // Un euro par jour pendant trente jours : un mois moyen.
    // `intl` colle un espace insecable fin avant l'euro : les comparaisons
    // portent sur le nombre, pas sur la ponctuation.
    expect(find.textContaining('30,44'), findsOneWidget);
    expect(find.text('7 trajets à vélo par semaine'), findsOneWidget);
  });

  testWidgets('un objectif en cours annonce une date', (tester) async {
    store = MemoryCommute(
      settings: const CommuteSettings(distanceKm: 12.4, consumption: 5.2),
      days: history(30),
      goals: [purchase('casque', 'Casque', 89)],
    );
    await open(tester);

    expect(find.text('Casque'), findsOneWidget);
    expect(find.textContaining(RegExp('30,00.*sur.*89,00')), findsOneWidget);
    expect(find.textContaining('vers le'), findsOneWidget);
  });

  testWidgets('un palier hors de portee annonce une annee, pas un jour', (tester) async {
    store = MemoryCommute(
      settings: const CommuteSettings(distanceKm: 12.4, consumption: 5.2),
      days: history(30),
      goals: [
        Goal(
          id: 'rentabiliser',
          name: 'Rentabiliser le vélo',
          target: 2000,
          kind: GoalKind.milestone,
          icon: GoalIcon.star,
          createdAt: DateTime(2026, 9, 1),
        ),
      ],
    );
    await open(tester);

    expect(find.textContaining('pas avant'), findsOneWidget);
    expect(find.textContaining('vers le'), findsNothing);
  });

  testWidgets('sans assez de journees, aucune date n est promise', (tester) async {
    store = MemoryCommute(
      settings: const CommuteSettings(distanceKm: 12.4, consumption: 5.2),
      days: history(5, amount: 10),
      goals: [purchase('casque', 'Casque', 89)],
    );
    await open(tester);

    expect(find.textContaining('Pas encore assez de trajets'), findsOneWidget);
    expect(find.textContaining('vers le'), findsNothing);
    // Le reste a economiser prend la place de la date.
    expect(find.textContaining('39,00'), findsOneWidget);
  });

  testWidgets('changer de fenetre change la date annoncee', (tester) async {
    // Vingt-cinq euros gagnes il y a longtemps, puis un rythme bien plus lent :
    // les deux fenetres ne peuvent pas donner la meme date.
    store = MemoryCommute(
      settings: const CommuteSettings(distanceKm: 12.4, consumption: 5.2),
      days: [
        for (var back = 120; back >= 60; back--)
          bike(DateTime(2026, 9, 18).subtract(Duration(days: back)), 2),
        for (var back = 55; back >= 0; back -= 7)
          bike(DateTime(2026, 9, 18).subtract(Duration(days: back)), 1),
      ],
      goals: [purchase('casque', 'Casque', 200)],
    );
    await open(tester);

    final recent = tester.widget<Text>(find.textContaining('pas avant').first).data;

    await tester.tap(find.text('Depuis le début'));
    await tester.pumpAndSettle();

    final all = tester.widget<Text>(find.textContaining(RegExp('vers le|pas avant')).first).data;

    expect(recent, isNot(all));
  });

  testWidgets('un achat atteint se valide en depensant son montant', (tester) async {
    store = MemoryCommute(
      settings: const CommuteSettings(distanceKm: 12.4, consumption: 5.2),
      days: [for (var d = 1; d <= 5; d++) bike(DateTime(2026, 9, d), 10)],
      goals: [purchase('sacoche', 'Sacoche', 35)],
    );
    await open(tester);

    await tester.tap(find.textContaining('et valider'));
    await tester.pumpAndSettle();

    expect(find.text('Valider « Sacoche » ?'), findsOneWidget);
    // Deux boutons portent ce montant : celui de la carte, et celui de la
    // feuille ouverte par-dessus. Le dernier de l'arbre est le second.
    await tester.tap(find
        .ancestor(
          of: find.textContaining('Dépenser 35,00'),
          matching: find.byType(FilledButton),
        )
        .last);
    await tester.pumpAndSettle();

    expect(store.goals['sacoche']!.isValidated, isTrue);
  });

  testWidgets('deux achats se partagent la cagnotte, et la page le dit', (tester) async {
    store = MemoryCommute(
      settings: const CommuteSettings(distanceKm: 12.4, consumption: 5.2),
      days: history(30),
      goals: [purchase('casque', 'Casque', 89), purchase('sacoche', 'Sacoche', 35)],
    );
    await open(tester);

    expect(find.text('2 objectifs en cours'), findsOneWidget);
    expect(find.textContaining('la même cagnotte'), findsOneWidget);
  });

  testWidgets('un seul achat ne declenche pas l avertissement', (tester) async {
    store = MemoryCommute(
      settings: const CommuteSettings(distanceKm: 12.4, consumption: 5.2),
      days: history(30),
      goals: [purchase('casque', 'Casque', 89)],
    );
    await open(tester);

    expect(find.textContaining('la même cagnotte'), findsNothing);
  });

  testWidgets('les objectifs valides ont leur section', (tester) async {
    store = MemoryCommute(
      settings: const CommuteSettings(distanceKm: 12.4, consumption: 5.2),
      days: history(30),
      goals: [
        Goal(
          id: 'antivol',
          name: 'Antivol pliant',
          target: 40,
          kind: GoalKind.purchase,
          icon: GoalIcon.bag,
          createdAt: DateTime(2026, 7, 1),
          validatedAt: DateTime(2026, 8, 2),
        ),
      ],
    );
    await open(tester);

    expect(find.text('DÉJÀ FRANCHIS'), findsOneWidget);
    expect(find.text('Antivol pliant'), findsOneWidget);
    expect(find.text('Aucun objectif en cours'), findsOneWidget);
  });
}
