import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/app_tab.dart';
import 'package:i_zerak_app/pages/more_sheet.dart';

void main() {
  late TabLayout saved;
  AppTab? chosen;

  Widget host(TabLayout layout) => MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                chosen = await showMoreSheet(
                  context,
                  layout: layout,
                  current: AppTab.home,
                  onLayoutChanged: (next) => saved = next,
                );
              },
              child: const Text('ouvrir'),
            ),
          ),
        ),
      );

  setUp(() {
    saved = TabLayout.initial;
    chosen = null;
  });

  Future<void> open(WidgetTester tester, [TabLayout? layout]) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(host(layout ?? TabLayout.initial));
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
  }

  testWidgets('le menu liste tous les onglets', (tester) async {
    await open(tester);

    expect(find.text('Accueil'), findsOneWidget);
    expect(find.text('Système'), findsOneWidget);
    expect(find.text('Stations'), findsOneWidget);
  });

  testWidgets('choisir un onglet le renvoie et referme le menu', (tester) async {
    await open(tester);

    await tester.tap(find.text('Système'));
    await tester.pumpAndSettle();

    expect(chosen, AppTab.system);
    expect(find.text('Système'), findsNothing);
  });

  testWidgets('la barre pleine grise les epingles des autres', (tester) async {
    await open(tester);

    final pin = tester.widget<IconButton>(find.ancestor(
      of: find.byIcon(Icons.push_pin_outlined).first,
      matching: find.byType(IconButton),
    ));

    expect(pin.onPressed, isNull);
    expect(find.textContaining('La barre est pleine'), findsOneWidget);
  });

  testWidgets('retirer un onglet libere une place et enregistre', (tester) async {
    await open(tester);

    await tester.tap(find.byIcon(Icons.push_pin).first);
    await tester.pumpAndSettle();

    expect(saved.pinned, hasLength(2));
    expect(saved.isPinned(AppTab.home), isFalse);
    expect(find.textContaining('La barre est pleine'), findsNothing);

    await tester.tap(find.byIcon(Icons.push_pin_outlined).first);
    await tester.pumpAndSettle();

    expect(saved.pinned, hasLength(3));
    expect(saved.isPinned(AppTab.home), isTrue);
  });
}
