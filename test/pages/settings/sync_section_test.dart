import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/pages/settings/sync_section.dart';
import 'package:i_zerak_app/services/sync/storage_access.dart';
import 'package:i_zerak_app/services/sync/sync_service.dart';

Widget wrap(Widget child) => MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

/// Un service de synchro en memoire : les reglages ne voient que son contrat.
class FakeSync implements SyncService {
  FakeSync({this.supported = true, this.folder, SyncStatus initial = SyncStatus.disabled})
      : _status = ValueNotifier(initial);

  final ValueNotifier<SyncStatus> _status;

  @override
  final bool supported;

  @override
  String? folder;

  @override
  String deviceName = 'Téléphone';

  @override
  String get deviceId => 'abc123';

  int syncCalls = 0;

  @override
  ValueListenable<SyncStatus> get status => _status;

  set current(SyncStatus value) => _status.value = value;

  @override
  Future<void> configure({String? folder, String? deviceName}) async {
    this.folder = (folder == null || folder.isEmpty) ? null : folder;
    if (deviceName != null && deviceName.isNotEmpty) {
      this.deviceName = deviceName;
    }
  }

  @override
  Future<void> syncNow() async => syncCalls++;

  @override
  Future<void> start() async {}

  @override
  Future<void> dispose() async {}
}

class FakeStorage implements StorageAccess {
  FakeStorage({required this.isRequired, this.granted = false});

  @override
  final bool isRequired;

  bool granted;
  int requests = 0;

  @override
  Future<bool> isGranted() async => !isRequired || granted;

  @override
  Future<void> request() async {
    requests++;
    granted = true;
  }
}

void main() {
  final now = DateTime(2026, 10, 30, 20, 0);

  Future<void> open(WidgetTester tester, FakeSync sync, {FakeStorage? storage}) async {
    await tester.binding.setSurfaceSize(const Size(420, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(wrap(SyncSection(
      sync: sync,
      storage: storage ?? FakeStorage(isRequired: false),
      clock: () => now,
    )));
    await tester.pumpAndSettle();
  }

  testWidgets('dans le navigateur, la section le dit et ne propose rien', (tester) async {
    await open(tester, FakeSync(supported: false));

    expect(find.text('Non disponible dans le navigateur'), findsOneWidget);
    expect(find.text('Dossier partagé'), findsNothing);
    expect(find.text('Synchroniser maintenant'), findsNothing);
  });

  testWidgets('sans dossier, la synchro attend qu on en choisisse un', (tester) async {
    final sync = FakeSync();
    await open(tester, sync);

    expect(find.text('Choisissez un dossier pour activer la synchro.'), findsOneWidget);
    final button = tester.widget<OutlinedButton>(find.ancestor(
        of: find.text('Synchroniser maintenant'), matching: find.byType(OutlinedButton)));
    expect(button.onPressed, isNull);
  });

  testWidgets('appliquer enregistre le dossier et le nom de l appareil', (tester) async {
    final sync = FakeSync();
    await open(tester, sync);

    await tester.enterText(find.widgetWithText(TextField, 'Dossier partagé'), '/sdcard/iZerak');
    await tester.enterText(find.widgetWithText(TextField, 'Nom de cet appareil'), 'Pixel');
    await tester.tap(find.text('Appliquer'));
    await tester.pumpAndSettle();

    expect(sync.folder, '/sdcard/iZerak');
    expect(sync.deviceName, 'Pixel');
  });

  testWidgets('l etat montre la derniere synchro et les autres appareils', (tester) async {
    final sync = FakeSync(
      folder: '/sdcard/iZerak',
      initial: SyncStatus(
        phase: SyncPhase.idle,
        lastSync: now.subtract(const Duration(minutes: 3)),
        peers: [
          SyncPeer(deviceId: 'pc1', name: 'PC', writtenAt: now.subtract(const Duration(hours: 2))),
        ],
      ),
    );
    await open(tester, sync);

    expect(find.text('Dernière synchro il y a 3 min'), findsOneWidget);
    expect(find.text('PC · écrit il y a 2 h'), findsOneWidget);

    await tester.tap(find.text('Synchroniser maintenant'));
    await tester.pumpAndSettle();
    expect(sync.syncCalls, 1);
  });

  testWidgets('une erreur est affichee telle quelle', (tester) async {
    final sync = FakeSync(
      folder: '/sdcard/iZerak',
      initial: const SyncStatus(phase: SyncPhase.error, error: 'dossier introuvable'),
    );
    await open(tester, sync);

    expect(find.text('Échec : dossier introuvable'), findsOneWidget);
  });

  testWidgets('sur Android sans permission, la section propose de l accorder', (tester) async {
    final storage = FakeStorage(isRequired: true);
    await open(tester, FakeSync(), storage: storage);

    expect(find.text('Autoriser l’accès aux fichiers'), findsOneWidget);

    await tester.tap(find.text('Autoriser l’accès aux fichiers'));
    await tester.pumpAndSettle();

    expect(storage.requests, 1);
    expect(find.text('Autoriser l’accès aux fichiers'), findsNothing);
  });
}
