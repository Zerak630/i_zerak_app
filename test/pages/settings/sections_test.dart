import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/app_tab.dart';
import 'package:i_zerak_app/models/commute_dao.dart';
import 'package:i_zerak_app/models/game_dao.dart';
import 'package:i_zerak_app/models/gas_station_dao.dart';
import 'package:i_zerak_app/models/screen_time_dao.dart';
import 'package:i_zerak_app/pages/settings/sections/commute_section.dart';
import 'package:i_zerak_app/pages/settings/sections/display_section.dart';
import 'package:i_zerak_app/pages/settings/sections/free_time_section.dart';
import 'package:i_zerak_app/pages/settings/sections/games_section.dart';
import 'package:i_zerak_app/pages/settings/sections/notifications_section.dart';
import 'package:i_zerak_app/services/commute_price_service.dart';
import 'package:i_zerak_app/services/gaming/gaming_service.dart';
import 'package:i_zerak_app/services/recap/recap_service.dart';
import 'package:i_zerak_app/services/reminders/reminder_service.dart';
import 'package:i_zerak_app/services/screen_time/screen_time_service.dart';

import '../../__mocks__/commute_fakes.dart';
import '../../__mocks__/recap_fakes.dart';
import '../../__mocks__/reminder_fakes.dart';
import '../../__mocks__/screen_time_fakes.dart';
import '../../__mocks__/sport_fakes.dart';
import '../../__mocks__/subscription_fakes.dart';

/// Chaque categorie, seule dans une page : c'est son contenu qui est eprouve,
/// le repli est l'affaire de settings_page_test.
Future<void> show(WidgetTester tester, Widget section) async {
  await tester.binding.setSurfaceSize(const Size(420, 2000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('fr'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: SingleChildScrollView(child: section)),
  ));
  await tester.pumpAndSettle();
}

void main() {
  final now = DateTime(2026, 11, 18, 20);

  group('Trajet et velo', () {
    late MemoryCommute store;
    late MemorySubscriptions subscriptions;

    setUp(() {
      store = MemoryCommute(
        settings: const CommuteSettings(distanceKm: 12.4),
        days: [
          CommuteDay(
            date: DateTime(2026, 9, 15),
            mode: CommuteMode.car,
            amount: 1.09,
            pricePerLitre: 1.689,
            priceSource: PriceSource.live,
            reasonId: 'lazy',
            bucket: CarBucket.missed,
          ),
        ],
      );
      subscriptions = MemorySubscriptions([sub('Spotify', 10.99), sub('Loyer', 700)]);
    });

    Widget section() => CommuteSection(
          store: store,
          subscriptions: subscriptions,
          prices: CommutePriceService(
            gas: FakeGasService(stations: [station(1, {FuelType.gazole: 1.689})]),
            favorites: StaticFavorites([(id: 1, label: 'Rue A', customName: null)]),
            store: store,
            clock: () => now,
          ),
        );

    testWidgets('enregistrer garde les journees deja saisies telles quelles', (tester) async {
      await show(tester, section());

      await tester.enterText(find.byType(TextFormField).first, '20');
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();

      expect(store.settings.distanceKm, 20);
      final day = store.days.values.single;
      expect(day.bucket, CarBucket.missed);
      expect(day.amount, 1.09);
    });

    testWidgets('un abonnement decoche s enregistre tout de suite, sans la saisie en cours',
        (tester) async {
      await show(tester, section());

      await tester.enterText(find.byType(TextFormField).first, '99');
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Loyer'));
      await tester.pumpAndSettle();

      expect(store.settings.paybackExcluded, {'Loyer'});
      expect(store.settings.distanceKm, 12.4, reason: 'la distance attend son bouton');

      // Et le bouton, ensuite, ne remet pas le loyer dans le remboursement.
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(store.settings.distanceKm, 99);
      expect(store.settings.paybackExcluded, {'Loyer'});
    });

    testWidgets('les raisons de prendre la voiture ne se reglent plus', (tester) async {
      await show(tester, section());

      expect(find.textContaining('RAISONS'), findsNothing);
      expect(find.text('Flemme'), findsNothing);
    });
  });

  group('Temps libre', () {
    late MemoryScreenTime store;
    late FakeUsageSource source;

    setUp(() {
      store = MemoryScreenTime(
        settings: ScreenTimeSettings(
          apps: const [TrackedApp(package: 'com.instagram.android', label: 'Instagram')],
          baselineMinutes: 120,
          startDate: DateTime(2026, 11, 2),
          reportEnabled: false,
        ),
      );
      source = FakeUsageSource(apps: const [
        TrackedApp(package: 'com.instagram.android', label: 'Instagram'),
        TrackedApp(package: 'com.reddit.frontpage', label: 'Reddit'),
      ]);
    });

    ScreenTimeService service() => ScreenTimeService(store: store, source: source, clock: () => now);

    testWidgets('la baisse s enregistre et le bilan du soir est reprogramme', (tester) async {
      await show(tester, FreeTimeSection(service: service()));

      await tester.tap(find.text('−20 %'));
      await tester.pumpAndSettle();

      expect(store.settings.weeklyDecrease, 0.20);
      expect(store.settings.reportEnabled, isFalse, reason: 'le bilan n est pas touche ici');
      expect(source.reports.last?['decrease'], 0.20);
    });

    testWidgets('changer d applications invite a recalculer la moyenne', (tester) async {
      await show(tester, FreeTimeSection(service: service()));

      await tester.tap(find.text('Applications suivies'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reddit'));
      await tester.pump();
      await tester.tap(find.text('Valider (2)'));
      await tester.pumpAndSettle();

      expect(store.settings.packages, {'com.instagram.android', 'com.reddit.frontpage'});
      expect(find.textContaining('pensez à la recalculer'), findsOneWidget);
      // La moyenne, elle, n'a pas bouge.
      expect(store.settings.baselineMinutes, 120);
    });

    testWidgets('pas encore en route : un seul bouton, la mise en route', (tester) async {
      store.settings = const ScreenTimeSettings();
      await show(tester, FreeTimeSection(service: service()));

      expect(find.text('Mettre en route'), findsOneWidget);
      expect(find.text('−20 %'), findsNothing);
    });
  });

  group('Jeux', () {
    late MemoryPreferences preferences;

    setUp(() => preferences = MemoryPreferences());

    GamingService service() => GamingService(
          fetch: () async => const GamingReport(),
          preferences: preferences,
        );

    testWidgets('les nouvelles regles valent a partir du lundi suivant', (tester) async {
      await show(tester, GamesSection(service: service(), clock: () => now));

      // Ratio de 3 a 6 : tout au bout du premier curseur.
      await tester.drag(find.byType(Slider).first, const Offset(400, 0));
      await tester.pumpAndSettle();

      final saved = preferences.contract;
      expect(saved.gameHoursPerSportHour, 6);
      // Mercredi 18 novembre : la semaine en cours garde l'ancien ratio.
      expect(saved.rulesFor(DateTime(2026, 11, 18)).gameHoursPerSportHour, 3);
      expect(saved.rulesFor(DateTime(2026, 11, 23)).gameHoursPerSportHour, 6);
    });

    testWidgets('desactiver le contrat grise les curseurs', (tester) async {
      await show(tester, GamesSection(service: service(), clock: () => now));

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(preferences.contract.enabled, isFalse);
      final slider = tester.widget<Slider>(find.byType(Slider).first);
      expect(slider.onChanged, isNull);
    });
  });

  group('Notifications et rappels', () {
    late MemoryPreferences preferences;
    late FakeRecapBridge bridge;
    late MemoryScreenTime screenStore;
    late FakeUsageSource source;

    setUp(() {
      preferences = MemoryPreferences();
      bridge = FakeRecapBridge();
      screenStore = MemoryScreenTime(
        settings: ScreenTimeSettings(
          apps: const [TrackedApp(package: 'com.instagram.android', label: 'Instagram')],
          baselineMinutes: 120,
          startDate: DateTime(2026, 11, 2),
          weeklyDecrease: 0.15,
        ),
      );
      source = FakeUsageSource();
    });

    Widget section() {
      final screenTime = ScreenTimeService(store: screenStore, source: source, clock: () => now);
      return NotificationsSection(
        screenTime: screenTime,
        recap: RecapService(
          commute: MemoryCommute(settings: const CommuteSettings(distanceKm: 12.4)),
          subscriptions: MemorySubscriptions(),
          sport: MemorySport(),
          preferences: preferences,
          bridge: bridge,
          screenTime: screenStore,
          clock: () => now,
        ),
      );
    }

    testWidgets('le bilan du soir se coupe et se rallume, avec la permission', (tester) async {
      await show(tester, section());

      await tester.tap(find.text('Bilan quotidien'));
      await tester.pumpAndSettle();
      expect(screenStore.settings.reportEnabled, isFalse);
      expect(screenStore.settings.weeklyDecrease, 0.15, reason: 'le quota n est pas touche');
      expect(source.reports.last?['enabled'], isFalse);

      await tester.tap(find.text('Bilan quotidien'));
      await tester.pumpAndSettle();
      expect(screenStore.settings.reportEnabled, isTrue);
      expect(source.notificationRequests, 1);
    });

    testWidgets('les bilans de la semaine et du mois s y reglent', (tester) async {
      await show(tester, section());

      await tester.tap(find.text('Bilan du mois'));
      await tester.pumpAndSettle();

      expect(preferences.recap.monthly, isFalse);
      expect(preferences.recap.weekly, isTrue);
      expect(bridge.configs.last['monthly'], isFalse);
    });

    testWidgets('Temps libre pas en route : pas de bilan du soir a regler', (tester) async {
      screenStore.settings = const ScreenTimeSettings();
      await show(tester, section());

      expect(find.text('Bilan quotidien'), findsNothing);
      expect(find.text('Bilan de la semaine'), findsOneWidget);
    });

    ReminderService reminders(FakeReminderBridge reminderBridge) => ReminderService(
          commute: MemoryCommute(settings: const CommuteSettings(distanceKm: 12.4)),
          sport: MemorySport(),
          preferences: preferences,
          bridge: reminderBridge,
          clock: () => now,
          locale: () => const Locale('fr'),
        );

    testWidgets('les rappels du soir se reglent en tete, sur Android', (tester) async {
      final reminderBridge = FakeReminderBridge();
      await show(tester, NotificationsSection(reminders: reminders(reminderBridge)));

      expect(find.text('Trajet'), findsOneWidget);
      await tester.tap(find.text('Programme de sport'));
      await tester.pumpAndSettle();
      expect(preferences.reminders.sport, isFalse);
      expect(preferences.reminders.commute, isTrue);
      expect((reminderBridge.configs.last['sport']! as Map)['enabled'], isFalse);
    });

    testWidgets('hors Android, pas de rappels a regler', (tester) async {
      await show(
          tester, NotificationsSection(reminders: reminders(FakeReminderBridge(supported: false))));

      expect(find.text('Trajet'), findsNothing);
      expect(find.text('Aucune notification à régler sur cet appareil.'), findsOneWidget);
    });

    testWidgets('sans aucun service, la categorie le dit', (tester) async {
      await show(tester, NotificationsSection());

      expect(find.text('Aucune notification à régler sur cet appareil.'), findsOneWidget);
    });
  });

  group('Affichage', () {
    testWidgets('epingler et desepingler, trois au plus', (tester) async {
      final preferences = MemoryPreferences();
      await show(tester, DisplaySection(preferences: preferences));

      // La barre d'origine est pleine : un quatrieme ne s'ajoute pas.
      final sport = find.widgetWithText(CheckboxListTile, 'Sport');
      expect(tester.widget<CheckboxListTile>(sport).onChanged, isNull);

      await tester.tap(find.widgetWithText(CheckboxListTile, 'Abonnements'));
      await tester.pumpAndSettle();
      expect(preferences.tabs.pinned, [AppTab.home, AppTab.commute]);

      await tester.tap(sport);
      await tester.pumpAndSettle();
      expect(preferences.tabs.pinned, [AppTab.home, AppTab.commute, AppTab.sport]);
    });
  });
}
