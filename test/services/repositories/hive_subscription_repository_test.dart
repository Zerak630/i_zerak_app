/// Les abonnements doivent survivre a la fermeture de l'application, et les
/// enregistrements ecrits avant les categories et les dates doivent continuer
/// de se relire.
///
/// Meme precaution que pour les stations favorites : une boite Hive sert ses
/// valeurs depuis un cache en memoire. Ces tests rouvrent donc la boite depuis
/// le disque plutot que de relire celle qu'ils viennent d'ecrire.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:i_zerak_app/models/subscription_dao.dart';
import 'package:i_zerak_app/services/repositories/hive/hive_subscription_repository.dart';
import 'package:i_zerak_app/services/repositories/hive/type_adapters.dart';

/// L'ancien format : six champs, dont le point de code d'une icone en 5.
///
/// Il n'existe que dans ce test, pour produire des octets d'avant la mise a
/// jour et verifier que l'adaptateur courant sait encore les lire.
class _LegacySubscriptionAdapter extends TypeAdapter<Subscription> {
  @override
  final int typeId = 0;

  @override
  Subscription read(BinaryReader reader) => throw UnimplementedError();

  @override
  void write(BinaryWriter writer, Subscription obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.price)
      ..writeByte(3)
      ..write(obj.isActive)
      ..writeByte(4)
      ..write(obj.subscriptionType)
      ..writeByte(5)
      ..write(983915);
  }
}

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('izerak_sub_test');
    Hive.init(directory.path);
    Hive.registerAdapter(SubscriptionTypeAdapter(), override: true);
    Hive.registerAdapter(SubscriptionFrequencyTypeAdapter(), override: true);
  });

  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  Future<HiveSubscriptionRepository> open() async => HiveSubscriptionRepository(
        await Hive.openBox<Subscription>('subscriptions'),
        await Hive.openBox<String>('subscription_prefs'),
      );

  Future<void> closeBoxes() async {
    await Hive.box<Subscription>('subscriptions').close();
    await Hive.box<String>('subscription_prefs').close();
  }

  test('un abonnement se relit entier apres reouverture', () async {
    await (await open()).updateSubscription(Subscription(
      name: 'Netflix',
      price: 13.49,
      subscriptionType: SubscriptionFrequency.monthly,
      categoryId: SubscriptionCategory.video,
      nextPayment: DateTime(2026, 9, 28),
      iconId: 'film',
    ));
    await closeBoxes();

    final read = (await (await open()).getAll()).single;

    expect(read.id, isNotNull);
    expect(read.name, 'Netflix');
    expect(read.price, 13.49);
    expect(read.subscriptionType, SubscriptionFrequency.monthly);
    expect(read.categoryId, SubscriptionCategory.video);
    expect(read.nextPayment, DateTime(2026, 9, 28));
    expect(read.iconId, 'film');
  });

  test('un abonnement enregistre avant les categories garde son nom et son prix', () async {
    Hive.registerAdapter(_LegacySubscriptionAdapter(), override: true);
    final box = await Hive.openBox<Subscription>('subscriptions');
    await box.put(
      'ancien',
      Subscription(
        id: 'ancien',
        name: 'Spotify',
        price: 11.99,
        subscriptionType: SubscriptionFrequency.monthly,
      ),
    );
    await box.flush();
    await box.close();

    Hive.registerAdapter(SubscriptionTypeAdapter(), override: true);
    final read = (await (await open()).getAll()).single;

    expect(read.name, 'Spotify');
    expect(read.price, 11.99);
    expect(read.subscriptionType, SubscriptionFrequency.monthly);
    expect(read.isActive, isTrue);
    // Les champs qui n'existaient pas se relisent vides, sans faire echouer la
    // lecture de la boite entiere.
    expect(read.categoryId, isNull);
    expect(read.nextPayment, isNull);
    expect(read.iconId, isNull);
  });

  test('le fichier est reellement ecrit, pas seulement le cache', () async {
    await (await open()).updateSubscription(Subscription(name: 'A', price: 1));

    expect(await File('${directory.path}/subscriptions.hive').length(), greaterThan(0));
  });

  test('un abonnement supprime ne revient pas', () async {
    final store = await open();
    await store.updateSubscription(Subscription(name: 'A', price: 1));
    final id = (await store.getAll()).single.id!;

    await store.delete(id);
    await closeBoxes();

    expect(await (await open()).getAll(), isEmpty);
  });

  group('categories', () {
    test('les categories livrees sont toujours la', () async {
      final categories = await (await open()).getCategories();

      expect(categories.map((category) => category.id),
          containsAll([SubscriptionCategory.home, SubscriptionCategory.software]));
    });

    test('une categorie ajoutee se relit apres reouverture', () async {
      await (await open()).saveCategory(const SubscriptionCategory(
        id: 'custom-1',
        label: 'Impots',
        color: CategoryColor.gold,
      ));
      await closeBoxes();

      final read = (await (await open()).getCategories()).last;

      expect(read.id, 'custom-1');
      expect(read.label, 'Impots');
      expect(read.color, CategoryColor.gold);
      expect(read.isBuiltIn, isFalse);
    });

    test('enregistrer deux fois le meme identifiant remplace, sans doublon', () async {
      final store = await open();
      await store.saveCategory(
          const SubscriptionCategory(id: 'custom-1', label: 'Impots', color: CategoryColor.gold));
      await store.saveCategory(
          const SubscriptionCategory(id: 'custom-1', label: 'Taxes', color: CategoryColor.mint));

      final custom = (await store.getCategories())
          .where((category) => !category.isBuiltIn)
          .toList();

      expect(custom, hasLength(1));
      expect(custom.single.label, 'Taxes');
    });

    test('une categorie livree n est pas dupliquee dans le stockage', () async {
      final store = await open();
      await store.saveCategory(SubscriptionCategory.builtIn.first);

      expect((await store.getCategories()).where((c) => c.id == SubscriptionCategory.home),
          hasLength(1));
    });

    test('un stockage abime laisse les categories livrees', () async {
      final prefs = await Hive.openBox<String>('subscription_prefs');
      await prefs.put('categories', 'pas du json');

      final categories = await (await open()).getCategories();

      expect(categories, hasLength(SubscriptionCategory.builtIn.length));
    });
  });
}
