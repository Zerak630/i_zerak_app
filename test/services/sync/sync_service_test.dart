/// Deux appareils, un dossier partage.
///
/// Chaque « appareil » a ses propres boites Hive (des noms distincts dans le
/// meme repertoire Hive) mais expose les memes noms de synchro, comme le
/// feraient le telephone et le PC. Le dossier partage remplace Syncthing : ce
/// que l'un y ecrit, l'autre le lit aussitot.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:i_zerak_app/models/subscription_dao.dart';
import 'package:i_zerak_app/services/repositories/hive/type_adapters.dart';
import 'package:i_zerak_app/services/sync/sync_service.dart';

class Device {
  Device._(this.service, this.commute, this.subscriptions, this.meta, this.now);

  final SyncService service;
  final Box<String> commute;
  final Box<Subscription> subscriptions;
  final Box<String> meta;
  DateTime now;

  static Future<Device> open(String prefix, {String? folder, DateTime? now}) async {
    final settings = await Hive.openBox<String>('${prefix}_settings');
    if (folder != null) {
      await settings.put('folder', folder);
    }
    final meta = await Hive.openBox<String>('${prefix}_meta');
    final commute = await Hive.openBox<String>('${prefix}_commute');
    final subscriptions = await Hive.openBox<Subscription>('${prefix}_subscriptions');
    late final Device device;
    final service = SyncService(
      settings: settings,
      meta: meta,
      boxes: [
        SyncedBox.strings('commute', commute),
        SyncedBox.subscriptions('subscriptions', subscriptions),
      ],
      clock: () => device.now,
    );
    device = Device._(service, commute, subscriptions, meta, now ?? DateTime(2026, 9, 18, 8));
    return device;
  }

  int stampOf(String id) => (json.decode(meta.get(id)!) as Map)['t'] as int;
}

/// Laisse passer les evenements de `watch` et l'horodatage qui les suit.
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  late Directory hive;
  late Directory shared;
  final devices = <Device>[];

  setUpAll(() {
    Hive.registerAdapter(SubscriptionTypeAdapter());
    Hive.registerAdapter(SubscriptionFrequencyTypeAdapter());
  });

  setUp(() async {
    hive = await Directory.systemTemp.createTemp('izerak_sync_hive');
    shared = await Directory.systemTemp.createTemp('izerak_sync_shared');
    Hive.init(hive.path);
  });

  tearDown(() async {
    for (final device in devices) {
      await device.service.dispose();
    }
    devices.clear();
    await Hive.close();
    await hive.delete(recursive: true);
    await shared.delete(recursive: true);
  });

  Future<Device> device(String prefix, {bool withFolder = true}) async {
    final opened = await Device.open(prefix, folder: withFolder ? shared.path : null);
    devices.add(opened);
    return opened;
  }

  test('une journee saisie sur un appareil apparait sur l autre', () async {
    final phone = await device('phone');
    final pc = await device('pc');
    await phone.service.start();
    await pc.service.start();

    await phone.commute.put('day:2026-09-18', '{"mode":"bike"}');
    await settle();
    await phone.service.syncNow();
    await pc.service.syncNow();

    expect(pc.commute.get('day:2026-09-18'), '{"mode":"bike"}');
    expect(pc.service.status.value.phase, SyncPhase.idle);
    expect(pc.service.status.value.generation, 1);
    expect(pc.service.status.value.peers.single.name, isNotEmpty);
    expect(pc.service.status.value.peers.single.deviceId, phone.service.deviceId);
  });

  test('une suppression se propage', () async {
    final phone = await device('phone');
    final pc = await device('pc');
    await phone.service.start();
    await pc.service.start();
    await phone.commute.put('goal:velo', '{"name":"Casque"}');
    await settle();
    await phone.service.syncNow();
    await pc.service.syncNow();
    expect(pc.commute.get('goal:velo'), isNotNull);

    phone.now = phone.now.add(const Duration(minutes: 5));
    await phone.commute.delete('goal:velo');
    await settle();
    await phone.service.syncNow();
    await pc.service.syncNow();

    expect(pc.commute.containsKey('goal:velo'), isFalse);
  });

  test('la version la plus recente l emporte, dans les deux sens', () async {
    final phone = await device('phone');
    final pc = await device('pc');
    await phone.service.start();
    await pc.service.start();

    await phone.commute.put('settings', '{"distanceKm":12}');
    await settle();
    pc.now = phone.now.add(const Duration(hours: 1));
    await pc.commute.put('settings', '{"distanceKm":15}');
    await settle();

    await phone.service.syncNow();
    await pc.service.syncNow();
    await phone.service.syncNow();

    expect(phone.commute.get('settings'), '{"distanceKm":15}');
    expect(pc.commute.get('settings'), '{"distanceKm":15}');
  });

  test('une entree importee garde l heure de son appareil d origine', () async {
    final phone = await device('phone');
    final pc = await device('pc');
    pc.now = DateTime(2030);
    await phone.service.start();
    await pc.service.start();

    await phone.commute.put('day:2026-09-18', '{"mode":"bike"}');
    await settle();
    await phone.service.syncNow();
    await pc.service.syncNow();
    await settle();

    final origin = phone.stampOf('commute/day:2026-09-18');
    expect(pc.stampOf('commute/day:2026-09-18'), origin);
    expect(origin, isNot(DateTime(2030).millisecondsSinceEpoch));
  });

  test('un fichier corrompu est ignore sans bloquer les autres', () async {
    final phone = await device('phone');
    final pc = await device('pc');
    await phone.service.start();
    await pc.service.start();
    await File('${shared.path}/izerak-casse.json').writeAsString('{pas du json');

    await phone.commute.put('day:2026-09-18', '{"mode":"bike"}');
    await settle();
    await phone.service.syncNow();
    await pc.service.syncNow();

    expect(pc.service.status.value.phase, SyncPhase.idle);
    expect(pc.commute.get('day:2026-09-18'), '{"mode":"bike"}');
    expect(pc.service.status.value.peers, hasLength(1));
  });

  test('les donnees d avant la synchro ne s ecrasent pas l une l autre', () async {
    final phone = await device('phone');
    final pc = await device('pc');
    // Saisies avant tout demarrage du service : elles sont « anciennes ».
    await phone.commute.put('settings', '{"distanceKm":12}');
    await phone.commute.put('day:2026-09-17', '{"mode":"bike"}');
    await pc.commute.put('settings', '{"distanceKm":99}');
    await phone.service.start();
    await pc.service.start();

    await phone.service.syncNow();
    await pc.service.syncNow();
    await phone.service.syncNow();

    // Egalite : chacun garde la sienne. Ce qui manquait arrive.
    expect(phone.commute.get('settings'), '{"distanceKm":12}');
    expect(pc.commute.get('settings'), '{"distanceKm":99}');
    expect(pc.commute.get('day:2026-09-17'), '{"mode":"bike"}');
  });

  test('un abonnement fait l aller-retour', () async {
    final phone = await device('phone');
    final pc = await device('pc');
    await phone.service.start();
    await pc.service.start();

    await phone.subscriptions.put(
      'abc',
      Subscription(
        id: 'abc',
        name: 'Netflix',
        price: 13.49,
        nextPayment: DateTime(2026, 9, 28),
        categoryId: 'video',
      ),
    );
    await settle();
    await phone.service.syncNow();
    await pc.service.syncNow();

    final copy = pc.subscriptions.get('abc')!;
    expect(copy.id, 'abc');
    expect(copy.name, 'Netflix');
    expect(copy.price, 13.49);
    expect(copy.nextPayment, DateTime(2026, 9, 28));
    expect(copy.categoryId, 'video');
  });

  test('sans dossier, rien ne s ecrit et le statut le dit', () async {
    final phone = await device('phone', withFolder: false);
    await phone.service.start();
    await phone.commute.put('day:2026-09-18', '{"mode":"bike"}');
    await settle();
    await phone.service.syncNow();

    expect(phone.service.status.value.phase, SyncPhase.disabled);
    expect(shared.listSync(), isEmpty);
    // Le suivi a pourtant commence : la journee a deja sa vraie date.
    expect(phone.stampOf('commute/day:2026-09-18'), phone.now.millisecondsSinceEpoch);
  });

  test('choisir un dossier lance la synchro et ecrit le fichier de l appareil', () async {
    final phone = await device('phone', withFolder: false);
    await phone.service.start();
    await phone.commute.put('day:2026-09-18', '{"mode":"bike"}');
    await settle();

    await phone.service.configure(folder: shared.path, deviceName: 'Pixel');

    expect(phone.service.status.value.phase, SyncPhase.idle);
    final file = File('${shared.path}/izerak-${phone.service.deviceId}.json');
    final written = json.decode(await file.readAsString()) as Map;
    expect(written['name'], 'Pixel');
    expect((written['entries'] as Map).keys, contains('commute/day:2026-09-18'));
    // Aucun fichier temporaire ne traine.
    expect(shared.listSync().map((e) => e.uri.pathSegments.last), [
      'izerak-${phone.service.deviceId}.json',
    ]);
  });
}
