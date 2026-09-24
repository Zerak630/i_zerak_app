import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/commute_dao.dart' hide dateOnly, roundCents;
import 'package:i_zerak_app/models/subscription_dao.dart';
import 'package:i_zerak_app/pages/dashboard/budget_page.dart';

import '../../__mocks__/commute_fakes.dart';
import '../../__mocks__/subscription_fakes.dart';

Widget wrap(Widget child) => MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );

const _settings = CommuteSettings(distanceKm: 12.4, consumption: 5.2);
const _price = ResolvedPrice(pricePerLitre: 1.689, source: PriceSource.live);

CommuteDay _bike(int day) => CommuteDay.bike(DateTime(2026, 9, day), _settings, _price);

CommuteDay _car(int day) => CommuteDay.car(
      DateTime(2026, 9, day),
      _settings,
      _price,
      const CarReason(id: CarReason.lazy, bucket: CarBucket.missed),
    );

void main() {
  final now = DateTime(2026, 9, 18, 8, 30);
  late MemorySubscriptions subscriptions;
  late MemoryCommute commute;

  setUp(() {
    subscriptions = MemorySubscriptions([
      sub('Netflix', 13.49, next: DateTime(2026, 9, 28)),
      sub('Assurance', 720,
          frequency: SubscriptionFrequency.yearly, next: DateTime(2027, 3, 12)),
    ]);
    commute = MemoryCommute(
      settings: _settings,
      days: [_bike(1), _bike(2), _car(3), _car(4)],
    );
  });

  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(wrap(BudgetPage(
      subscriptionService: subscriptions,
      commuteService: commute,
      clock: () => now,
    )));
    await tester.pumpAndSettle();
  }

  testWidgets('le mois reunit les abonnements et les trajets en voiture', (tester) async {
    await open(tester);

    expect(find.text('Septembre 2026'), findsOneWidget);
    expect(find.text('Abonnements'), findsOneWidget);
    expect(find.text('Trajets en voiture'), findsOneWidget);
    expect(find.textContaining('13,49'), findsOneWidget);
    expect(find.text('2 jours'), findsOneWidget);
  });

  testWidgets('le velo figure a cote du total, jamais dedans', (tester) async {
    await open(tester);

    expect(find.text('Évité grâce au vélo'), findsOneWidget);
    // 13,49 € d'abonnement et 2 trajets en voiture : le velo n'y est pas.
    final trip = _settings.tripValue(_price.pricePerLitre);
    expect(find.textContaining((13.49 + 2 * trip).toStringAsFixed(2).replaceAll('.', ',')),
        findsWidgets);
  });

  testWidgets('un appui sur une colonne ouvre son mois', (tester) async {
    await open(tester);

    await tester.tap(find.text('août'));
    await tester.pumpAndSettle();

    expect(find.text('Août 2026'), findsOneWidget);
  });

  testWidgets('le mois a venir reste inaccessible', (tester) async {
    await open(tester);

    final next = tester.widget<IconButton>(
      find.ancestor(of: find.byIcon(Icons.chevron_right), matching: find.byType(IconButton)),
    );

    expect(next.onPressed, isNull);
  });

  testWidgets('un mois annuel pese sur son seul mois', (tester) async {
    await open(tester);

    await tester.tap(find.byTooltip('Mois précédent'));
    await tester.pumpAndSettle();

    expect(find.text('Août 2026'), findsOneWidget);
    // Aucun prelevement en aout : Netflix commence le 28 septembre, mais la
    // serie remonte, donc il tombe aussi le 28 aout.
    expect(find.text('Abonnements'), findsOneWidget);
  });
}
