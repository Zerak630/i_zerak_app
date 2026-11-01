import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/screen_time_dao.dart';
import 'package:i_zerak_app/pages/free_time/free_time_settings_page.dart';
import 'package:i_zerak_app/services/screen_time/screen_time_service.dart';

import '../../__mocks__/screen_time_fakes.dart';

void main() {
  late MemoryScreenTime store;
  late FakeUsageSource source;

  setUp(() {
    store = MemoryScreenTime(
      settings: ScreenTimeSettings(
        apps: const [TrackedApp(package: 'com.instagram.android', label: 'Instagram')],
        baselineMinutes: 120,
        startDate: DateTime(2026, 11, 2),
      ),
    );
    source = FakeUsageSource(apps: const [
      TrackedApp(package: 'com.instagram.android', label: 'Instagram'),
      TrackedApp(package: 'com.reddit.frontpage', label: 'Reddit'),
    ]);
  });

  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: FreeTimeSettingsPage(service: ScreenTimeService(store: store, source: source)),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('la baisse hebdomadaire et le bilan s enregistrent tout de suite', (tester) async {
    await open(tester);

    await tester.tap(find.text('−20 %'));
    await tester.pumpAndSettle();
    expect(store.settings.weeklyDecrease, 0.20);

    await tester.tap(find.text('Bilan quotidien'));
    await tester.pumpAndSettle();
    expect(store.settings.reportEnabled, isFalse);

    await tester.tap(find.text('Bilan quotidien'));
    await tester.pumpAndSettle();
    expect(store.settings.reportEnabled, isTrue);
    expect(source.notificationRequests, 1, reason: 'reactiver le bilan redemande la permission');
  });

  testWidgets('changer d applications invite a recalculer la moyenne', (tester) async {
    await open(tester);

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
}
