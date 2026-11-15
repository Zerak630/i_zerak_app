import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/sport_dao.dart';
import 'package:i_zerak_app/pages/sport/sport_page.dart';

import '../../__mocks__/sport_fakes.dart';

Widget wrap(Widget child) => MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

void main() {
  // Mercredi 18 novembre 2026.
  final now = DateTime(2026, 11, 18, 19);
  const yoga = PlannedSlot(id: 'y', sportId: Sport.yoga, weekday: DateTime.monday, minutes: 30);
  const strength = PlannedSlot(id: 'r', sportId: Sport.strength, weekday: DateTime.friday, minutes: 20);
  late MemorySport store;

  setUp(() => store = MemorySport());

  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(wrap(SportPage(store: store, clock: () => now)));
    await tester.pumpAndSettle();
  }

  testWidgets('sans programme, la page propose d en preparer un', (tester) async {
    await open(tester);

    expect(find.text('CETTE SEMAINE'), findsOneWidget);
    expect(find.text('Aucune séance'), findsOneWidget);
    expect(find.text('Pas encore de programme'), findsOneWidget);
    expect(find.text('Aucune séance sur cette période.'), findsOneWidget);
  });

  testWidgets('une seance en plus s ajoute en trois choix', (tester) async {
    await open(tester);

    await tester.tap(find.text('Ajouter une séance').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yoga'));
    await tester.tap(find.text('45 min'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer la séance'));
    await tester.pumpAndSettle();

    final session = store.sessions.values.single;
    expect(session.sportId, Sport.yoga);
    expect(session.minutes, 45);
    expect(session.date, DateTime(2026, 11, 18));
    expect(find.text('EN PLUS DU PROGRAMME'), findsOneWidget);
    expect(find.text('1 séance'), findsWidgets);
  });

  testWidgets('un creneau passe se saisit : fait, avec sa duree', (tester) async {
    store = MemorySport(plan: [yoga, strength]);
    await open(tester);

    expect(find.text('Aucune séance · programme 0 sur 2'), findsOneWidget);
    expect(find.text('À saisir'), findsNWidgets(2 + 1),
        reason: 'lundi, et les deux creneaux de la semaine derniere');
    expect(find.text('À venir'), findsOneWidget);
    expect(find.text('À SAISIR DE LA SEMAINE DERNIÈRE'), findsOneWidget);

    // Le lundi de cette semaine : le dernier « À saisir » de la page.
    await tester.tap(find.text('À saisir').last);
    await tester.pumpAndSettle();
    expect(find.text('Fait — 30 min'), findsOneWidget);
    await tester.tap(find.text('45 min'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fait — 45 min'));
    await tester.pumpAndSettle();

    final session = store.sessions.values.single;
    expect(session.slotId, 'y');
    expect(session.date, DateTime(2026, 11, 16));
    expect(session.minutes, 45);
    expect(find.text('1 séance · programme 1 sur 2'), findsOneWidget);
  });

  testWidgets('un creneau se dit fait un autre jour de la semaine', (tester) async {
    store = MemorySport(plan: [yoga]);
    await open(tester);

    await tester.tap(find.text('À saisir').last);
    await tester.pumpAndSettle();
    expect(find.text('Quel jour ?'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'jeu. 19'), findsNothing, reason: 'demain ne se propose pas');
    await tester.tap(find.widgetWithText(ChoiceChip, 'mer. 18'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fait — 30 min'));
    await tester.pumpAndSettle();

    final session = store.sessions.values.single;
    expect(session.date, DateTime(2026, 11, 18));
    expect(session.slotDay, DateTime(2026, 11, 16));
    expect(find.textContaining('décalé au mer. 18 nov.'), findsOneWidget);
    expect(find.text('1 séance · programme 1 sur 1'), findsOneWidget);
    expect(find.text('EN PLUS DU PROGRAMME'), findsNothing);
  });

  testWidgets('un creneau dit pas fait ne compte pas, et s efface', (tester) async {
    store = MemorySport(plan: [yoga]);
    await open(tester);

    await tester.tap(find.text('À saisir').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Pas fait'));
    await tester.pumpAndSettle();

    expect(store.sessions.values.single.skipped, isTrue);
    expect(find.text('Aucune séance · programme 0 sur 1'), findsOneWidget);

    await tester.tap(find.text('Pas fait').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Effacer la saisie'));
    await tester.pumpAndSettle();
    expect(store.sessions, isEmpty);
  });

  testWidgets('le temps par sport suit la periode choisie', (tester) async {
    store = MemorySport(sessions: [
      SportSession(id: 'a', date: DateTime(2026, 11, 17), sportId: Sport.yoga, minutes: 30),
      SportSession(id: 'b', date: DateTime(2026, 11, 3), sportId: Sport.running, minutes: 50),
      SportSession(id: 'c', date: DateTime(2026, 10, 3), sportId: Sport.running, minutes: 40),
    ]);
    await open(tester);

    // Ce mois : la course devant le yoga.
    expect(find.text('50 min · 1 séance'), findsOneWidget);
    expect(find.text('30 min · 1 séance'), findsOneWidget);

    await tester.tap(find.text('Tout'));
    await tester.pumpAndSettle();
    expect(find.text('1 h 30 · 2 séances'), findsOneWidget);

    await tester.tap(find.text('Semaine'));
    await tester.pumpAndSettle();
    expect(find.text('Course à pied'), findsNothing);
  });

  testWidgets('les semaines passees se remplissent apres coup', (tester) async {
    store = MemorySport(plan: [yoga]);
    await open(tester);

    expect(find.byTooltip('Semaine suivante'), findsOneWidget);
    expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.chevron_right)).onPressed,
        isNull, reason: 'pas de semaine a venir');

    await tester.tap(find.byTooltip('Semaine précédente'));
    await tester.pumpAndSettle();
    expect(find.text('SEMAINE DU 9 NOV.'), findsOneWidget);
    await tester.tap(find.text('À saisir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fait — 30 min'));
    await tester.pumpAndSettle();

    expect(store.sessions.values.single.date, DateTime(2026, 11, 9));
  });

  testWidgets('le programme s ecrit depuis sa page', (tester) async {
    await open(tester);

    await tester.tap(find.text('Programme'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ajouter un créneau'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Renforcement'));
    await tester.tap(find.text('jeu.'));
    await tester.tap(find.text('20 min'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();

    final slot = store.plan.values.single;
    expect((slot.sportId, slot.weekday, slot.minutes), (Sport.strength, DateTime.thursday, 20));
    expect(find.text('jeudi'), findsOneWidget);

    await tester.tap(find.text('Ajouter un sport'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Escalade');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(store.sports.values.single.label, 'Escalade');
    expect(find.text('Escalade'), findsOneWidget);
  });
}
