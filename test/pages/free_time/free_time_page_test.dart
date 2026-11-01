import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/screen_time_dao.dart';
import 'package:i_zerak_app/pages/free_time/free_time_page.dart';
import 'package:i_zerak_app/services/screen_time/screen_time_service.dart';

import '../../__mocks__/screen_time_fakes.dart';

const insta = 'com.instagram.android';

Widget wrap(Widget child) => MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

void main() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  DateTime daysAgo(int days) => DateTime(today.year, today.month, today.day - days);

  late MemoryScreenTime store;
  late FakeUsageSource source;

  setUp(() {
    store = MemoryScreenTime();
    source = FakeUsageSource(apps: const [
      TrackedApp(package: insta, label: 'Instagram'),
      TrackedApp(package: 'com.whatsapp', label: 'WhatsApp'),
    ]);
  });

  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(wrap(FreePage(store: store, source: source)));
    await tester.pumpAndSettle();
  }

  testWidgets('hors Android, l onglet le dit au lieu de mesurer', (tester) async {
    source.supported = false;
    await open(tester);
    expect(find.text('Disponible sur Android'), findsOneWidget);
  });

  testWidgets('non configure, l onglet propose de commencer', (tester) async {
    await open(tester);
    expect(find.text('Reprendre la main sur son temps'), findsOneWidget);
    expect(find.text('Commencer'), findsOneWidget);
  });

  testWidgets('la mise en route mesure la moyenne puis demarre', (tester) async {
    source.recordedDays.addAll([daysAgo(1), daysAgo(2)]);
    source.recorded.addAll([
      UsageSession(insta, daysAgo(1).add(const Duration(hours: 21)),
          daysAgo(1).add(const Duration(hours: 23))),
      UsageSession(insta, daysAgo(2).add(const Duration(hours: 21)),
          daysAgo(2).add(const Duration(hours: 22))),
    ]);
    await open(tester);

    await tester.tap(find.text('Commencer'));
    await tester.pumpAndSettle();
    // Instagram, installe et connu, est coche d'office ; WhatsApp non.
    expect(find.text('Instagram'), findsOneWidget);

    await tester.tap(find.text('Mesurer ma moyenne'));
    await tester.pumpAndSettle();
    expect(find.text('1 h 30'), findsOneWidget);
    expect(find.text('Votre quota cette semaine : 1 h 21 par jour.'), findsOneWidget);

    await tester.tap(find.text('C’est parti'));
    await tester.pumpAndSettle();

    expect(store.settings.isConfigured, isTrue);
    expect(store.settings.baselineMinutes, 90);
    expect(store.settings.packages, {insta});
    expect(source.notificationRequests, 1);
    expect(find.text('Cagnotte temps libre'.toUpperCase()), findsOneWidget);
  });

  testWidgets('configure, l onglet montre la journee, la serie et la cagnotte', (tester) async {
    store.settings = ScreenTimeSettings(
      apps: const [TrackedApp(package: insta, label: 'Instagram')],
      baselineMinutes: 120,
      startDate: daysAgo(3),
    );
    source.recordedDays.addAll([daysAgo(2), daysAgo(1), today]);
    source.recorded.addAll([
      UsageSession(insta, daysAgo(2).add(const Duration(hours: 12)),
          daysAgo(2).add(const Duration(hours: 13))),
      UsageSession(insta, daysAgo(1).add(const Duration(hours: 22)),
          daysAgo(1).add(const Duration(hours: 22, minutes: 30))),
      UsageSession(insta, today, today.add(const Duration(minutes: 1))),
    ]);
    await open(tester);

    // 60 puis 90 minutes gagnees, a 2 €/h.
    // La cagnotte, et la case des jours tenus.
    expect(find.text('5,00\u00a0€'), findsNWidgets(2));
    // La serie, et le nombre de jours tenus.
    expect(find.text('2 jours'), findsNWidgets(2));
    expect(find.text('sur 1 h 48'), findsOneWidget);
    expect(find.text('Instagram'), findsOneWidget);
  });

  testWidgets('les jours au-dessus du quota remplissent les economies loupees', (tester) async {
    store.settings = ScreenTimeSettings(
      apps: const [TrackedApp(package: insta, label: 'Instagram')],
      baselineMinutes: 120,
      startDate: daysAgo(3),
    );
    source.recordedDays.addAll([daysAgo(2), daysAgo(1)]);
    source.recorded.addAll([
      // 3 h : au-dessus du quota de 108 minutes.
      UsageSession(insta, daysAgo(2).add(const Duration(hours: 12)),
          daysAgo(2).add(const Duration(hours: 15))),
      UsageSession(insta, daysAgo(1).add(const Duration(hours: 22)),
          daysAgo(1).add(const Duration(hours: 22, minutes: 30))),
    ]);
    await open(tester);

    expect(find.text('Économies loupées'), findsOneWidget);
    // (120 - 108) minutes a 2 €/h, sur la case et sur la ligne du jour.
    expect(find.text('0,40\u00a0€'), findsNWidgets(2));
    // Seule la journee tenue alimente la cagnotte : 90 minutes gagnees.
    expect(find.text('3,00\u00a0€'), findsWidgets);
  });

  testWidgets('acces retire : la carte le signale et renvoie aux reglages', (tester) async {
    store.settings = ScreenTimeSettings(
      apps: const [TrackedApp(package: insta, label: 'Instagram')],
      baselineMinutes: 120,
      startDate: daysAgo(3),
    );
    source.access = false;
    await open(tester);

    expect(find.text('Accès aux données retiré'), findsOneWidget);
    await tester.tap(find.text('Ouvrir les réglages'));
    expect(source.accessSettingsOpened, 1);
  });
}

/// La page, branchee sur les faux plutot que sur le conteneur.
class FreePage extends StatelessWidget {
  const FreePage({super.key, required this.store, required this.source});

  final MemoryScreenTime store;
  final FakeUsageSource source;

  @override
  Widget build(BuildContext context) =>
      FreeTimePage(service: ScreenTimeService(store: store, source: source));
}
