import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/commute_dao.dart';
import 'package:i_zerak_app/models/companion_dao.dart';
import 'package:i_zerak_app/pages/dashboard/challenge_page.dart';

import '../../__mocks__/commute_fakes.dart';

Widget wrap(Widget child) => MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );

void main() {
  final now = DateTime(2026, 9, 18, 8, 30);
  late MemoryCommute store;

  CommuteDay bike(DateTime date) => CommuteDay(
        date: date,
        mode: CommuteMode.bike,
        amount: 1.09,
        pricePerLitre: 1.689,
        priceSource: PriceSource.live,
      );

  CommuteDay car(DateTime date) => CommuteDay(
        date: date,
        mode: CommuteMode.car,
        amount: 1.09,
        pricePerLitre: 1.689,
        priceSource: PriceSource.live,
        reasonId: 'sport',
        bucket: CarBucket.essential,
      );

  /// Les [count] premiers jours ouvres du mois, a velo.
  List<CommuteDay> bikeMonth(int year, int month, int count) {
    final days = <CommuteDay>[];
    for (var day = 1; day <= daysOfMonth(DateTime(year, month)) && days.length < count; day++) {
      final date = DateTime(year, month, day);
      if (isWorkday(date)) {
        days.add(bike(date));
      }
    }
    return days;
  }

  /// Dix journees a velo et trois en voiture en septembre, rien apres le 17.
  final september = [
    car(DateTime(2026, 9, 1)),
    car(DateTime(2026, 9, 2)),
    car(DateTime(2026, 9, 7)),
    bike(DateTime(2026, 9, 3)),
    bike(DateTime(2026, 9, 4)),
    for (final day in [8, 9, 10, 11, 14, 15, 16, 17]) bike(DateTime(2026, 9, day)),
  ];

  setUp(() => store = MemoryCommute());

  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(wrap(ChallengePage(store: store, clock: () => now)));
    await tester.pumpAndSettle();
  }

  testWidgets('sans cible, la page explique et en propose une', (tester) async {
    store = MemoryCommute(days: [
      ...bikeMonth(2026, 6, 14),
      ...bikeMonth(2026, 7, 7),
      ...bikeMonth(2026, 8, 3),
    ]);
    await open(tester);

    expect(find.text('Aucune cible ce mois-ci'), findsOneWidget);
    expect(find.text('proposé d’après vos 3 derniers mois : 8'), findsOneWidget);

    await tester.tap(find.text('Se fixer une cible'));
    await tester.pumpAndSettle();

    expect(store.challenges['2026-09']?.target, 8);
    expect(find.text('Cible du mois'), findsOneWidget);
  });

  testWidgets('sans historique, la page le dit plutot que d inventer', (tester) async {
    await open(tester);

    expect(find.text('pas encore d’historique pour proposer une cible'), findsOneWidget);

    await tester.tap(find.text('Se fixer une cible'));
    await tester.pumpAndSettle();

    // La moitie des vingt-deux jours ouvres de septembre, a corriger au pas.
    expect(store.challenges['2026-09']?.target, 11);
  });

  testWidgets('une cible en cours dit ce qu il reste et le temps qu il reste', (tester) async {
    store = MemoryCommute(
      days: september,
      challenges: [ChallengeTarget(month: DateTime(2026, 9), target: 14)],
    );
    await open(tester);

    expect(find.text('10'), findsOneWidget);
    expect(find.text('sur 14'), findsOneWidget);
    expect(find.text('jours de vélo en septembre'), findsOneWidget);
    expect(
      find.text('Il en reste 4 à faire, et 9 jours ouvrés pour les faire.'),
      findsOneWidget,
    );
    expect(find.text('22 jours ouvrés'), findsOneWidget);
  });

  testWidgets('une cible hors d atteinte ne fait pas semblant', (tester) async {
    store = MemoryCommute(
      days: september,
      challenges: [ChallengeTarget(month: DateTime(2026, 9), target: 20)],
    );
    await open(tester);

    expect(
      find.text('Hors d’atteinte ce mois-ci : 10 à faire, 9 jours ouvrés restants.'),
      findsOneWidget,
    );
  });

  testWidgets('une cible atteinte est annoncee comme telle', (tester) async {
    store = MemoryCommute(
      days: september,
      challenges: [ChallengeTarget(month: DateTime(2026, 9), target: 8)],
    );
    await open(tester);

    expect(find.text('Défi atteint — 10 jours sur 8.'), findsOneWidget);
  });

  testWidgets('le pas-a-pas enregistre la nouvelle cible', (tester) async {
    store = MemoryCommute(
      days: september,
      challenges: [ChallengeTarget(month: DateTime(2026, 9), target: 14)],
    );
    await open(tester);

    await tester.tap(find.byTooltip('Plus'));
    await tester.pumpAndSettle();

    expect(store.challenges['2026-09']?.target, 15);
    expect(find.text('sur 15'), findsOneWidget);

    await tester.tap(find.byTooltip('Moins'));
    await tester.pumpAndSettle();

    expect(store.challenges['2026-09']?.target, 14);
  });

  testWidgets('la cible ne depasse pas les jours ouvres du mois', (tester) async {
    store = MemoryCommute(
      days: september,
      challenges: [ChallengeTarget(month: DateTime(2026, 9), target: 22)],
    );
    await open(tester);

    final plus = tester.widget<IconButton>(find.ancestor(
      of: find.byIcon(Icons.add),
      matching: find.byType(IconButton),
    ));

    expect(plus.onPressed, isNull);
  });

  testWidgets('les mois d avant portent leur verdict', (tester) async {
    store = MemoryCommute(
      days: [...september, ...bikeMonth(2026, 8, 3), ...bikeMonth(2026, 7, 12)],
      challenges: [
        ChallengeTarget(month: DateTime(2026, 9), target: 14),
        ChallengeTarget(month: DateTime(2026, 8), target: 8),
        ChallengeTarget(month: DateTime(2026, 7), target: 10),
      ],
    );
    await open(tester);

    expect(find.text('LES MOIS D’AVANT'), findsOneWidget);
    expect(find.text('Août'), findsOneWidget);
    expect(find.text('3 sur 8'), findsOneWidget);
    expect(find.text('Juillet'), findsOneWidget);
    expect(find.text('réussi — 12 sur 10'), findsOneWidget);
  });

  testWidgets('un mois sans cible n a rien a juger', (tester) async {
    store = MemoryCommute(
      days: [...september, ...bikeMonth(2026, 8, 3)],
      challenges: [ChallengeTarget(month: DateTime(2026, 9), target: 14)],
    );
    await open(tester);

    expect(find.text('Août'), findsNothing);
  });
}
