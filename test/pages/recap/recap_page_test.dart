import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/commute_dao.dart';
import 'package:i_zerak_app/models/screen_time_dao.dart';
import 'package:i_zerak_app/models/sport_dao.dart';
import 'package:i_zerak_app/pages/recap/recap_page.dart';
import 'package:i_zerak_app/services/recap/recap_service.dart';

import '../../__mocks__/commute_fakes.dart';
import '../../__mocks__/recap_fakes.dart';
import '../../__mocks__/screen_time_fakes.dart';
import '../../__mocks__/sport_fakes.dart';
import '../../__mocks__/subscription_fakes.dart';

Widget wrap(Widget child) => MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );

void main() {
  // Mercredi 18 novembre 2026.
  final now = DateTime(2026, 11, 18, 12);
  late MemorySport sport;
  late MemoryPreferences preferences;
  late FakeRecapBridge bridge;
  late MemoryScreenTime screenTime;

  CommuteDay bike(DateTime date, double amount) => CommuteDay(
        date: date,
        mode: CommuteMode.bike,
        amount: amount,
        pricePerLitre: 1.7,
        priceSource: PriceSource.live,
      );

  setUp(() {
    sport = MemorySport(sessions: [
      SportSession(id: 'a', date: DateTime(2026, 11, 16), sportId: Sport.yoga, minutes: 30),
      SportSession(id: 'b', date: DateTime(2026, 11, 10), sportId: Sport.running, minutes: 50),
    ]);
    preferences = MemoryPreferences();
    bridge = FakeRecapBridge();
    final settings = ScreenTimeSettings(
      apps: const [TrackedApp(package: 'insta', label: 'Instagram')],
      baselineMinutes: 120,
      startDate: DateTime(2026, 11, 1),
    );
    screenTime = MemoryScreenTime(settings: settings, days: [
      settings.close(DailyUsage(
        date: DateTime(2026, 11, 16),
        apps: const {'insta': AppUsage(seconds: 60 * 60)},
        hourly: List.filled(24, 0),
      )),
    ]);
  });

  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = RecapService(
      commute: MemoryCommute(
        settings: const CommuteSettings(distanceKm: 12.4),
        days: [bike(DateTime(2026, 11, 17), 3.2), bike(DateTime(2026, 11, 2), 3.2)],
      ),
      subscriptions: MemorySubscriptions([sub('Spotify', 10.99)]),
      sport: sport,
      preferences: preferences,
      bridge: bridge,
      screenTime: screenTime,
      clock: () => now,
    );
    await tester.pumpWidget(wrap(RecapPage(service: service, sport: sport, clock: () => now)));
    await tester.pumpAndSettle();
  }

  testWidgets('la semaine met cote a cote velo, reseaux et sport', (tester) async {
    await open(tester);

    expect(find.text('Du 16 nov. au 22 nov.'), findsOneWidget);
    expect(find.textContaining('3,20'), findsOneWidget);
    expect(find.text('1 h 00'), findsOneWidget, reason: '60 minutes reprises le 16');
    expect(find.text('30 min'), findsWidgets);
    expect(find.text('Sur les 1 h 00 reprises aux réseaux, 30 min sont allées au sport.'),
        findsOneWidget);
    // La semaine d'avant, pour comparer.
    expect(find.text('avant : 50 min'), findsOneWidget);
    expect(bridge.notificationRequests, 1, reason: 'les bilans sont actifs par defaut');
  });

  testWidgets('le mois ajoute les abonnements, et les periodes se parcourent', (tester) async {
    await open(tester);

    await tester.tap(find.text('Mois'));
    await tester.pumpAndSettle();
    expect(find.text('Novembre 2026'), findsOneWidget);
    expect(find.textContaining('6,40'), findsNWidgets(2), reason: 'le total, et la part remboursee');
    expect(find.text('0 abonnement remboursé sur 1'), findsNothing);
    expect(find.text('Aucun abonnement remboursé sur 1'), findsOneWidget);
    expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.chevron_right)).onPressed,
        isNull);

    await tester.tap(find.byTooltip('Période précédente'));
    await tester.pumpAndSettle();
    expect(find.text('Octobre 2026'), findsOneWidget);
    expect(find.text('Aucune séance'), findsOneWidget);
  });

  testWidgets('les notifications se reglent depuis le bilan', (tester) async {
    await open(tester);

    await tester.tap(find.text('Bilan du mois'));
    await tester.pumpAndSettle();

    expect(preferences.recap.monthly, isFalse);
    expect(preferences.recap.weekly, isTrue);
    expect(bridge.configs.last['monthly'], isFalse);
  });
}
