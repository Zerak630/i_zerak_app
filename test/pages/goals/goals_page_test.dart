import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/commute_dao.dart';
import 'package:i_zerak_app/models/gas_station_dao.dart';
import 'package:i_zerak_app/pages/goals/goals_page.dart';
import 'package:i_zerak_app/services/commute_price_service.dart';

import '../../__mocks__/commute_fakes.dart';
import '../../__mocks__/subscription_fakes.dart';

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
  late MemorySubscriptions subscriptions;

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

  Goal milestone(String id, String name, double target, {DateTime? since}) => Goal(
        id: id,
        name: name,
        target: target,
        kind: GoalKind.milestone,
        icon: GoalIcon.bike,
        createdAt: DateTime(2026, 9, 1),
        since: since,
      );

  GoalsPage page() => GoalsPage(
        store: store,
        subscriptions: subscriptions,
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
    subscriptions = MemorySubscriptions();
  });

  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(wrap(page()));
    await tester.pumpAndSettle();
  }

  testWidgets('sans palier ni abonnement, la page dit a quoi ils servent', (tester) async {
    await open(tester);

    expect(find.text('Aucun palier pour l’instant'), findsOneWidget);
    expect(find.textContaining('donne une date à vos économies'), findsOneWidget);
    expect(find.textContaining('Ajoutez vos abonnements'), findsOneWidget);
  });

  testWidgets('le mois en cours rembourse les abonnements, du moins cher au plus cher',
      (tester) async {
    subscriptions = MemorySubscriptions([sub('Netflix', 13.49), sub('Spotify', 10.99), sub('Forfait', 20)]);
    store = MemoryCommute(
      settings: const CommuteSettings(distanceKm: 12.4, consumption: 5.2),
      // 1er au 18 septembre : 18 trajets a 1,50 €, 27 €. Aout ne compte pas.
      days: [
        for (var d = 1; d <= 18; d++) bike(DateTime(2026, 9, d), 1.5),
        bike(DateTime(2026, 8, 30), 40),
      ],
    );
    await open(tester);

    expect(find.textContaining('CE QUE LE VÉLO REMBOURSE · SEPTEMBRE 2026'), findsOneWidget);
    expect(find.textContaining('27,00'), findsWidgets);
    expect(find.text('2 abonnements remboursés sur 3'), findsOneWidget);
    // 27 - 10,99 - 13,49 = 2,52 sur le forfait : encore 17,48 €, soit 17
    // trajets a 1,09 €.
    expect(find.text('Encore 17 trajets à vélo pour rembourser Forfait'), findsOneWidget);
    // Aout a son propre resume, plus bas.
    expect(find.text('LES MOIS PRÉCÉDENTS'), findsOneWidget);
  });

  testWidgets('un abonnement decoche n est plus rembourse', (tester) async {
    subscriptions = MemorySubscriptions([sub('Spotify', 10.99), sub('Loyer', 700)]);
    store = MemoryCommute(
      settings: const CommuteSettings(distanceKm: 12.4, consumption: 5.2),
      days: history(3, amount: 5),
    );
    await open(tester);
    expect(find.text('1 abonnement remboursé sur 2'), findsOneWidget);

    await tester.tap(find.text('Choisir les abonnements'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Loyer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();

    expect(store.settings.paybackExcluded, {'Loyer'});
    expect(find.text('1 abonnement remboursé sur 1'), findsOneWidget);
  });

  testWidgets('le rythme se mesure et s affiche par mois', (tester) async {
    store = MemoryCommute(
      settings: const CommuteSettings(distanceKm: 12.4, consumption: 5.2),
      days: history(30),
      goals: [milestone('velo', 'Vélo', 450)],
    );
    await open(tester);

    // Un euro par jour pendant trente jours : un mois moyen.
    // `intl` colle un espace insecable fin avant l'euro : les comparaisons
    // portent sur le nombre, pas sur la ponctuation.
    expect(find.textContaining('30,44'), findsOneWidget);
    expect(find.text('7 trajets à vélo par semaine'), findsOneWidget);
  });

  testWidgets('sous deux trajets par semaine, le singulier', (tester) async {
    store = MemoryCommute(
      settings: const CommuteSettings(distanceKm: 12.4, consumption: 5.2),
      // Un trajet tous les sept jours sur huit semaines : 1 par semaine.
      days: [
        for (var back = 56; back >= 0; back -= 7)
          bike(DateTime(2026, 9, 18).subtract(Duration(days: back)), 1),
      ],
      goals: [milestone('velo', 'Vélo', 450)],
    );
    await open(tester);

    // Un peu plus d'un trajet par semaine : le nom reste au singulier, comme
    // le veut le francais en dessous de deux.
    expect(find.textContaining('trajet à vélo par semaine'), findsOneWidget);
    expect(find.textContaining('trajets à vélo par semaine'), findsNothing);
  });

  testWidgets('un objectif en cours annonce une date', (tester) async {
    store = MemoryCommute(
      settings: const CommuteSettings(distanceKm: 12.4, consumption: 5.2),
      days: history(30),
      goals: [milestone('casque', 'Casque', 89)],
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
      goals: [milestone('casque', 'Casque', 89)],
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
      goals: [milestone('casque', 'Casque', 200)],
    );
    await open(tester);

    final recent = tester.widget<Text>(find.textContaining('pas avant').first).data;

    await tester.tap(find.text('Depuis le début'));
    await tester.pumpAndSettle();

    final all = tester.widget<Text>(find.textContaining(RegExp('vers le|pas avant')).first).data;

    expect(recent, isNot(all));
  });

  testWidgets('un palier compte depuis sa date d achat', (tester) async {
    store = MemoryCommute(
      settings: const CommuteSettings(distanceKm: 12.4, consumption: 5.2),
      days: history(30),
      goals: [milestone('tel', 'Téléphone', 300, since: DateTime(2026, 9, 9))],
    );
    await open(tester);

    // Du 9 au 18 inclus : dix euros.
    expect(find.textContaining(RegExp('10,00.*sur.*300,00')), findsOneWidget);
    expect(find.textContaining('compté depuis le'), findsOneWidget);
  });

  testWidgets('un palier atteint se marque comme rentabilise, sans rien depenser', (tester) async {
    store = MemoryCommute(
      settings: const CommuteSettings(distanceKm: 12.4, consumption: 5.2),
      days: [for (var d = 1; d <= 5; d++) bike(DateTime(2026, 9, d), 10)],
      goals: [milestone('sacoche', 'Sacoche', 35)],
    );
    await open(tester);

    await tester.tap(find.text('Marquer comme rentabilisé'));
    await tester.pumpAndSettle();

    expect(find.text('« Sacoche » est rentabilisé'), findsOneWidget);
    await tester.tap(find
        .ancestor(
          of: find.text('Marquer comme rentabilisé'),
          matching: find.byType(FilledButton),
        )
        .last);
    await tester.pumpAndSettle();

    expect(store.goals['sacoche']!.isValidated, isTrue);
    expect(find.text('DÉJÀ RENTABILISÉS'), findsOneWidget);
  });

  testWidgets('un nouveau palier se cree depuis la page', (tester) async {
    store = MemoryCommute(
      settings: const CommuteSettings(distanceKm: 12.4, consumption: 5.2),
      days: history(10),
    );
    await open(tester);

    await tester.tap(find.text('Nouveau palier'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Nom'), 'Vélo');
    await tester.enterText(find.widgetWithText(TextFormField, 'Prix d’achat'), '450');
    await tester.pumpAndSettle();
    expect(find.textContaining('il manque'), findsOneWidget);
    await tester.tap(find.text('Créer l’objectif'));
    await tester.pumpAndSettle();

    final goal = store.goals.values.single;
    expect(goal.kind, GoalKind.milestone);
    expect(goal.target, 450);
    expect(goal.since, isNull);
    expect(find.text('Vélo'), findsOneWidget);
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

    expect(find.text('DÉJÀ RENTABILISÉS'), findsOneWidget);
    expect(find.text('Antivol pliant'), findsOneWidget);
    expect(find.text('Aucun palier pour l’instant'), findsOneWidget);
  });
}
