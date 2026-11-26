import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/settings_category.dart';
import 'package:i_zerak_app/pages/settings/settings_page.dart';

import '../../__mocks__/recap_fakes.dart';

void main() {
  late MemoryPreferences preferences;

  setUp(() => preferences = MemoryPreferences());

  /// Des contenus de categorie reduits a un champ : c'est la page qui est
  /// eprouvee ici, chaque categorie a ses propres tests.
  Map<SettingsCategory, WidgetBuilder> sections(Iterable<SettingsCategory> categories) => {
        for (final category in categories)
          category: (_) => TextField(key: ValueKey('field-${category.name}')),
      };

  Future<void> open(
    WidgetTester tester, {
    SettingsCategory? at,
    Iterable<SettingsCategory> categories = SettingsCategory.values,
  }) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SettingsPage(open: at, preferences: preferences, sections: sections(categories)),
    ));
    await tester.pumpAndSettle();
  }

  Finder field(SettingsCategory category) => find.byKey(ValueKey('field-${category.name}'));

  testWidgets('au premier passage, tout est replie : l ecran sert de sommaire', (tester) async {
    await open(tester);

    for (final title in [
      'Trajet et vélo',
      'Temps libre',
      'Jeux',
      'Notifications et rappels',
      'Serveur et Pi',
      'Synchronisation',
      'Affichage',
    ]) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    for (final category in SettingsCategory.values) {
      expect(field(category), findsNothing, reason: 'rien n est construit avant d etre ouvert');
    }
  });

  testWidgets('une categorie depliee le reste a la visite suivante', (tester) async {
    await open(tester);

    await tester.tap(find.text('Jeux'));
    await tester.pumpAndSettle();
    expect(field(SettingsCategory.games), findsOneWidget);
    expect(preferences.expanded, {SettingsCategory.games});

    // Page refermee puis rouverte : l'etat ne vient plus que des preferences.
    await tester.pumpWidget(const SizedBox());
    await open(tester);
    expect(field(SettingsCategory.games), findsOneWidget);
    expect(field(SettingsCategory.commute), findsNothing);

    await tester.tap(find.text('Jeux'));
    await tester.pumpAndSettle();
    expect(field(SettingsCategory.games), findsNothing);
    expect(preferences.expanded, isEmpty);
  });

  testWidgets('replier ne perd pas une saisie en cours', (tester) async {
    await open(tester);
    await tester.tap(find.text('Serveur et Pi'));
    await tester.pumpAndSettle();
    await tester.enterText(field(SettingsCategory.server), 'raspberrypi.local');

    await tester.tap(find.text('Serveur et Pi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Serveur et Pi'));
    await tester.pumpAndSettle();

    expect(find.text('raspberrypi.local'), findsOneWidget);
  });

  testWidgets('un raccourci deplie sa categorie sans changer ce qui est retenu', (tester) async {
    preferences.expanded = {SettingsCategory.commute};
    await open(tester, at: SettingsCategory.display);

    expect(field(SettingsCategory.display), findsOneWidget);
    expect(field(SettingsCategory.commute), findsOneWidget);
    expect(preferences.expanded, {SettingsCategory.commute});
  });

  testWidgets('un raccourci amene sa categorie a l ecran', (tester) async {
    // Toutes depliees : la derniere est bien en dessous de l'ecran.
    preferences.expanded = SettingsCategory.values.toSet();
    await open(tester, at: SettingsCategory.display);

    final top = tester.getTopLeft(find.text('Affichage')).dy;
    expect(top, lessThan(900));
    expect(top, greaterThanOrEqualTo(0));
  });

  testWidgets('une categorie sans service sur cet appareil n apparait pas', (tester) async {
    await open(tester, categories: [SettingsCategory.notifications, SettingsCategory.display]);

    expect(find.text('Notifications et rappels'), findsOneWidget);
    expect(find.text('Serveur et Pi'), findsNothing);
    expect(find.text('Synchronisation'), findsNothing);
  });

  test('les categories retenues se relisent, un nom inconnu est ignore', () {
    final names = SettingsCategory.toNames({SettingsCategory.sync, SettingsCategory.commute});

    expect(names, ['commute', 'sync'], reason: 'dans l ordre de l ecran');
    expect(SettingsCategory.fromNames([...names, 'disparue', 42]),
        {SettingsCategory.commute, SettingsCategory.sync});
  });
}
