import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/subscription_dao.dart';
import 'package:i_zerak_app/pages/subscriptions/subscriptions.dart';

import '../../__mocks__/subscription_fakes.dart';

Widget wrap(Widget child) => MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );

void main() {
  final now = DateTime(2026, 9, 18, 8, 30);
  late MemorySubscriptions store;

  SubscriptionsPage page() =>
      SubscriptionsPage(subscriptionService: store, clock: () => now);

  setUp(() {
    store = MemorySubscriptions([
      sub('Panier de legumes', 18,
          frequency: SubscriptionFrequency.weekly,
          category: SubscriptionCategory.home,
          next: DateTime(2026, 9, 22)),
      sub('Assurance auto', 720,
          frequency: SubscriptionFrequency.yearly,
          category: SubscriptionCategory.insurance,
          next: DateTime(2027, 3, 12)),
      sub('Netflix', 13.49,
          category: SubscriptionCategory.video, next: DateTime(2026, 9, 28)),
      sub('Disney+', 5.99,
          category: SubscriptionCategory.video, next: DateTime(2026, 9, 19)),
      sub('Presse en ligne', 11.99, active: false),
    ]);
  });

  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(wrap(page()));
    await tester.pumpAndSettle();
  }

  testWidgets('le total mensuel additionne toutes les frequences', (tester) async {
    await open(tester);

    // 78 (18 par semaine) + 60 (720 par an) + 13,49 + 5,99
    expect(find.textContaining('157,48'), findsOneWidget);
    expect(find.text('COÛT MENSUEL'), findsOneWidget);
    expect(find.textContaining('4 abonnements actifs'), findsOneWidget);
    expect(find.textContaining('1 suspendu'), findsOneWidget);
  });

  testWidgets('changer d unite recalcule le total et chaque ligne', (tester) async {
    await open(tester);
    expect(find.textContaining('78,00'), findsOneWidget);

    await tester.tap(find.text('an'));
    await tester.pumpAndSettle();

    expect(find.text('COÛT ANNUEL'), findsOneWidget);
    // 157,48 × 12, avec l espace insecable des milliers que pose `intl`.
    expect(find.textContaining('889,76'), findsOneWidget);
    // Le panier passe de 78 € par mois a 936 € par an.
    expect(find.textContaining('936,00'), findsOneWidget);
  });

  testWidgets('la barre de repartition est reellement dessinee', (tester) async {
    await open(tester);

    final bar = find.byKey(const Key('subscription-category-bar'));
    final segments = find.descendant(of: bar, matching: find.byType(DecoratedBox));

    // Un bloc par categorie, et surtout une hauteur non nulle : sans
    // `stretch`, les blocs occupaient leur largeur mais aucune hauteur.
    expect(segments, findsNWidgets(3));
    expect(tester.getSize(segments.first).height, 10);
    expect(tester.getSize(segments.first).width, greaterThan(0));
  });

  testWidgets('la barre se deplie sur le detail par categorie', (tester) async {
    await open(tester);
    expect(find.textContaining('Le plus lourd'), findsNothing);

    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();

    // Chaque categorie et son montant, sous la barre.
    expect(find.text('Vidéo'), findsNWidgets(2));
    expect(find.textContaining('19,48'), findsOneWidget);
    expect(find.textContaining('Le plus lourd : Panier de legumes'), findsOneWidget);
  });

  testWidgets('un filtre ne garde que les abonnements de sa categorie', (tester) async {
    await open(tester);
    expect(find.text('Netflix'), findsOneWidget);
    expect(find.text('Assurance auto'), findsOneWidget);

    final chip = find.widgetWithText(ChoiceChip, 'Vidéo');
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();

    expect(find.text('Netflix'), findsOneWidget);
    expect(find.text('Disney+'), findsOneWidget);
    expect(find.text('Assurance auto'), findsNothing);
    expect(find.textContaining('2 abonnements actifs'), findsOneWidget);
  });

  testWidgets('les suspendus sont a part et hors du total', (tester) async {
    await open(tester);

    expect(find.textContaining('Suspendus · 1'), findsOneWidget);
    expect(find.text('Presse en ligne'), findsOneWidget);
    expect(find.text('Si tout reprenait'), findsOneWidget);
    // 157,48 + 11,99
    expect(find.textContaining('169,47'), findsOneWidget);
  });

  testWidgets('le prochain prelevement annonce le jour et le montant', (tester) async {
    await open(tester);

    expect(find.textContaining('Demain'), findsOneWidget);
    expect(find.textContaining('Disney+'), findsWidgets);
    expect(find.textContaining('3 autres d’ici la fin du mois'), findsOneWidget);
  });

  testWidgets('sans abonnement, la page invite a en ajouter un', (tester) async {
    store = MemorySubscriptions();
    await open(tester);

    expect(find.text('Aucun abonnement'), findsOneWidget);
    expect(find.text('Ajoutez-en un avec le bouton +'), findsOneWidget);
  });

  testWidgets('un abonnement cree apparait dans la liste et dans le total', (tester) async {
    store = MemorySubscriptions();
    await open(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Nom'), 'Spotify');
    await tester.enterText(find.widgetWithText(TextFormField, 'Prix'), '11,99');
    await tester.tap(find.widgetWithText(FilledButton, 'Ajouter'));
    await tester.pumpAndSettle();

    expect(find.text('Spotify'), findsOneWidget);
    expect(find.textContaining('11,99'), findsWidgets);
    expect(find.text('Abonnement enregistré'), findsOneWidget);
    expect(store.items.values.single.name, 'Spotify');
  });

  testWidgets('la confirmation s efface seule, sans qu on la touche', (tester) async {
    store = MemorySubscriptions();
    await open(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Nom'), 'Spotify');
    await tester.enterText(find.widgetWithText(TextFormField, 'Prix'), '11,99');
    await tester.tap(find.widgetWithText(FilledButton, 'Ajouter'));
    await tester.pumpAndSettle();
    expect(find.text('Abonnement enregistré'), findsOneWidget);

    // Une action rend le bandeau persistant par defaut : sans `persist: false`,
    // il attendrait indefiniment qu'on appuie sur OK.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    expect(find.text('Abonnement enregistré'), findsNothing);
  });

  testWidgets('un prix vide ou nul est refuse', (tester) async {
    store = MemorySubscriptions();
    await open(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Nom'), 'Gratuit');
    await tester.enterText(find.widgetWithText(TextFormField, 'Prix'), '0');
    await tester.tap(find.widgetWithText(FilledButton, 'Ajouter'));
    await tester.pumpAndSettle();

    expect(find.text('Veuillez entrer un prix valide'), findsOneWidget);
    expect(store.items, isEmpty);
  });

  testWidgets('la feuille suspend un abonnement sans le supprimer', (tester) async {
    await open(tester);

    await tester.tap(find.text('Netflix'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer'));
    await tester.pumpAndSettle();

    expect(store.items['Netflix']!.isActive, isFalse);
    expect(find.textContaining('Suspendus · 2'), findsOneWidget);
  });

  testWidgets('la feuille supprime apres confirmation', (tester) async {
    await open(tester);

    await tester.tap(find.text('Netflix'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Supprimer').last);
    await tester.pumpAndSettle();

    expect(store.items.containsKey('Netflix'), isFalse);
    expect(find.text('Abonnement supprimé'), findsOneWidget);
  });
}
