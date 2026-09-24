import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/subscription_dao.dart';
import 'package:i_zerak_app/pages/subscriptions/subscription_payments_page.dart';

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

  setUp(() {
    store = MemorySubscriptions([
      sub('Panier de legumes', 18,
          frequency: SubscriptionFrequency.weekly,
          category: SubscriptionCategory.home,
          next: DateTime(2026, 9, 22)),
      sub('Netflix', 13.49,
          category: SubscriptionCategory.video, next: DateTime(2026, 9, 28)),
      sub('Disney+', 5.99,
          category: SubscriptionCategory.video, next: DateTime(2026, 9, 19)),
      sub('Sans date', 9.99),
    ]);
  });

  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(wrap(SubscriptionPaymentsPage(
      subscriptionService: store,
      clock: () => now,
    )));
    await tester.pumpAndSettle();
  }

  testWidgets('le mois se partage entre ce qui est passe et ce qui reste', (tester) async {
    await open(tester);

    expect(find.text('Septembre 2026'), findsOneWidget);
    expect(find.text('Déjà prélevé'), findsOneWidget);
    // Les 1er, 8 et 15 septembre, a 18 € le panier.
    expect(find.textContaining('54,00'), findsOneWidget);
    expect(find.text('Reste à payer'), findsOneWidget);
    // 19 septembre, puis 22, 28 et 29.
    expect(find.textContaining('55,48'), findsOneWidget);
    expect(find.textContaining('4 prélèvements'), findsOneWidget);
  });

  testWidgets('un abonnement sans date ne tombe nulle part', (tester) async {
    await open(tester);

    expect(find.text('Sans date'), findsNothing);
  });

  testWidgets('le mois se compare a la moyenne mensuelle', (tester) async {
    await open(tester);

    // 109,48 preleves en septembre, pour une moyenne de 97,48 par mois.
    expect(find.textContaining('pour une moyenne de'), findsOneWidget);
  });

  testWidgets('le mois precedent se consulte', (tester) async {
    await open(tester);

    await tester.tap(find.byTooltip('Mois précédent'));
    await tester.pumpAndSettle();

    expect(find.text('Août 2026'), findsOneWidget);
    // La serie remonte avant la date saisie : le panier tombait deja.
    expect(find.text('Panier de legumes'), findsWidgets);
  });

  testWidgets('un mois sans echeance le dit', (tester) async {
    store = MemorySubscriptions([sub('Sans date', 9.99)]);
    await open(tester);

    expect(find.text('Aucun prélèvement ce mois-ci'), findsOneWidget);
  });
}
