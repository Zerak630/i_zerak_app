import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/sport_dao.dart';
import 'package:i_zerak_app/pages/sport/sport_plan_page.dart';

import '../../__mocks__/sport_fakes.dart';

Widget wrap(Widget child) => MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );

void main() {
  const yoga = PlannedSlot(id: 'y', sportId: Sport.yoga, weekday: DateTime.monday, minutes: 30);
  late MemorySport store;

  setUp(() => store = MemorySport());

  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(wrap(SportPlanPage(store: store)));
    await tester.pumpAndSettle();
  }

  Finder deleteButton() => find.widgetWithText(TextButton, 'Supprimer ce sport');

  testWidgets('un sport ajoute change d icone sans changer d identifiant', (tester) async {
    store = MemorySport(sports: const [Sport(id: 'sport-1', label: 'Tennis', icon: SportIcon.other)]);
    await open(tester);

    await tester.tap(find.text('Tennis'));
    await tester.pumpAndSettle();
    expect(find.text('Modifier le sport'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('sport-icon-racket')));
    await tester.pump();
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();

    expect(store.sports.keys, ['sport-1']);
    expect(store.sports['sport-1']!.icon, SportIcon.racket);
    expect(store.sports['sport-1']!.label, 'Tennis');
  });

  testWidgets('un sport livre garde son nom traduit si on ne le renomme pas', (tester) async {
    await open(tester);

    await tester.tap(find.widgetWithText(ActionChip, 'Yoga'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sport-icon-gymnastics')));
    await tester.pump();
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();

    final saved = store.sports[Sport.yoga]!;
    expect(saved.label, isNull);
    expect(saved.icon, SportIcon.gymnastics);
  });

  testWidgets('un sport qui ne sert pas se supprime', (tester) async {
    store = MemorySport(sports: const [Sport(id: 'sport-1', label: 'Doublon', icon: SportIcon.other)]);
    await open(tester);

    await tester.tap(find.text('Doublon'));
    await tester.pumpAndSettle();
    await tester.tap(deleteButton());
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Supprimer'));
    await tester.pumpAndSettle();

    expect(store.sports, isEmpty);
    expect(find.text('Doublon'), findsNothing);
  });

  testWidgets('un sport livre supprime disparait de la liste', (tester) async {
    await open(tester);

    await tester.tap(find.widgetWithText(ActionChip, 'Course à pied'));
    await tester.pumpAndSettle();
    await tester.tap(deleteButton());
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Supprimer'));
    await tester.pumpAndSettle();

    expect(store.sports[Sport.running]!.hidden, isTrue);
    expect(find.widgetWithText(ActionChip, 'Course à pied'), findsNothing);
  });

  testWidgets('un sport utilise ne se supprime pas, et la feuille dit pourquoi', (tester) async {
    store = MemorySport(
      plan: [yoga],
      sessions: [SportSession.forSlot(yoga, DateTime(2026, 11, 9), minutes: 30)],
    );
    await open(tester);

    await tester.tap(find.widgetWithText(ActionChip, 'Yoga'));
    await tester.pumpAndSettle();

    expect(tester.widget<TextButton>(deleteButton()).onPressed, isNull);
    expect(find.textContaining('1 séance · 1 créneau du programme'), findsOneWidget);
  });
}
