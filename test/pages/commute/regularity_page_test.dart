import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/commute_dao.dart';
import 'package:i_zerak_app/pages/commute/regularity_page.dart';

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

  CommuteDay car(DateTime date, {CarBucket bucket = CarBucket.essential}) => CommuteDay(
        date: date,
        mode: CommuteMode.car,
        amount: 1.09,
        pricePerLitre: 1.689,
        priceSource: PriceSource.live,
        reasonId: bucket == CarBucket.missed ? 'lazy' : 'sport',
        bucket: bucket,
      );

  setUp(() => store = MemoryCommute());

  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(wrap(RegularityPage(store: store, clock: () => now)));
    await tester.pumpAndSettle();
  }

  testWidgets('sans journee, la page le dit sans afficher de grille', (tester) async {
    await open(tester);

    expect(find.text('Enregistrez quelques journées pour voir vos séries.'), findsOneWidget);
    expect(find.text('PAR JOUR DE LA SEMAINE'), findsNothing);
  });

  testWidgets('la serie en cours et le record se lisent ensemble', (tester) async {
    store = MemoryCommute(days: [
      // Un record de quatre en juin, casse par une journee en voiture.
      for (final day in [1, 2, 3, 4]) bike(DateTime(2026, 6, day)),
      car(DateTime(2026, 6, 5)),
      // Puis trois journees de suite en septembre.
      for (final day in [15, 16, 17]) bike(DateTime(2026, 9, day)),
    ]);
    await open(tester);

    expect(find.text('3 jours de vélo d’affilée'), findsOneWidget);
    expect(find.text('Record : 4 jours, en juin'), findsOneWidget);
    expect(find.text('encore 2 pour le battre'), findsOneWidget);
  });

  testWidgets('la serie en cours peut porter le record', (tester) async {
    store = MemoryCommute(days: [
      for (final day in [14, 15, 16, 17]) bike(DateTime(2026, 9, day)),
    ]);
    await open(tester);

    expect(find.text('C’est votre record'), findsOneWidget);
    expect(find.textContaining('pour le battre'), findsNothing);
  });

  testWidgets('la grille date son debut quand tout l historique y tient', (tester) async {
    store = MemoryCommute(days: [bike(DateTime(2026, 9, 14)), bike(DateTime(2026, 9, 15))]);
    await open(tester);

    expect(find.text('DEPUIS LE 14 SEPTEMBRE'), findsOneWidget);
    expect(find.text('2 jours enregistrés'), findsOneWidget);
  });

  testWidgets('un historique trop long se reduit aux dernieres semaines', (tester) async {
    store = MemoryCommute(days: [
      bike(DateTime(2025, 1, 6)),
      bike(DateTime(2026, 9, 14)),
    ]);
    await open(tester);

    // Quatre-vingt-huit semaines ne tiennent pas dans 420 pixels : la carte
    // annonce ce qu'elle montre au lieu de pretendre tout montrer.
    expect(find.textContaining('DERNIÈRES SEMAINES'), findsOneWidget);
    expect(find.textContaining('DEPUIS LE'), findsNothing);
  });

  testWidgets('le jour de la semaine qui coince est nomme, flemme comprise', (tester) async {
    store = MemoryCommute(days: [
      // Trois mardis : un a velo, un indispensable, un par flemme.
      bike(DateTime(2026, 9, 1)),
      car(DateTime(2026, 9, 8)),
      car(DateTime(2026, 9, 15), bucket: CarBucket.missed),
    ]);
    await open(tester);

    expect(
      find.text('Le mardi est votre point faible : 2 journées en voiture sur 3, dont 1 par flemme.'),
      findsOneWidget,
    );
  });

  testWidgets('un point faible sans flemme ne parle pas de flemme', (tester) async {
    store = MemoryCommute(days: [
      bike(DateTime(2026, 9, 1)),
      car(DateTime(2026, 9, 8)),
      car(DateTime(2026, 9, 15)),
    ]);
    await open(tester);

    expect(
      find.text('Le mardi est votre point faible : 2 journées en voiture sur 3.'),
      findsOneWidget,
    );
  });

  testWidgets('un jour sans voiture et le meilleur mois se detachent', (tester) async {
    store = MemoryCommute(days: [
      // Trois jeudis a velo, et rien d'autre ce jour-la.
      for (final day in [3, 10, 17]) bike(DateTime(2026, 9, day)),
      car(DateTime(2026, 9, 1)),
      car(DateTime(2026, 9, 8)),
      car(DateTime(2026, 9, 15)),
    ]);
    await open(tester);

    expect(find.text('Jamais de voiture'), findsOneWidget);
    expect(find.text('jeudi'), findsOneWidget);
    expect(find.text('Meilleur mois'), findsOneWidget);
    expect(find.text('septembre'), findsOneWidget);
    expect(find.text('3 jours sur 6'), findsOneWidget);
  });

  testWidgets('les barres par jour de la semaine sont bien peintes', (tester) async {
    // Regression : un `ColoredBox` sans enfant, dans un `Expanded` d'une `Row`
    // alignee au centre, se replie a zero. La barre gardait sa place et sa
    // couleur de fond, mais ne peignait aucun segment.
    store = MemoryCommute(days: [
      bike(DateTime(2026, 9, 1)),
      car(DateTime(2026, 9, 8)),
      car(DateTime(2026, 9, 15), bucket: CarBucket.missed),
    ]);
    await open(tester);

    final scheme = Theme.of(tester.element(find.text('PAR JOUR DE LA SEMAINE'))).colorScheme;
    final segments = tester
        .widgetList<ColoredBox>(find.byType(ColoredBox))
        .where((box) => box.color == scheme.primary || box.color == scheme.tertiary);

    expect(segments, isNotEmpty);
    for (final segment in segments) {
      final size = tester.getSize(find.byWidget(segment));
      expect(size.height, 9);
      expect(size.width, greaterThan(0));
    }
  });

  testWidgets('la regle de la serie est dite sur la page', (tester) async {
    store = MemoryCommute(days: [bike(DateTime(2026, 9, 17))]);
    await open(tester);

    expect(find.textContaining('ne casse pas la série'), findsOneWidget);
    expect(find.text('rien d’enregistré'), findsOneWidget);
  });
}
