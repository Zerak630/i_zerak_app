/// Les trajets doivent survivre a la fermeture de l'application.
///
/// Comme pour les stations, les tests rouvrent la boite depuis le disque
/// plutot que de relire le cache en memoire de celle qu'ils viennent d'ecrire.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:i_zerak_app/models/commute_dao.dart';
import 'package:i_zerak_app/models/gas_station_dao.dart';
import 'package:i_zerak_app/services/repositories/hive/hive_commute_repository.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('izerak_commute_test');
    Hive.init(directory.path);
  });

  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  Future<HiveCommuteRepository> open() async =>
      HiveCommuteRepository(await Hive.openBox<String>('commute'));

  Future<HiveCommuteRepository> reopen() async {
    await Hive.box<String>('commute').close();
    return open();
  }

  const settings = CommuteSettings(distanceKm: 12.4, consumption: 5.2);
  const price = ResolvedPrice(pricePerLitre: 1.689, source: PriceSource.live);

  test('reglages, jours et objectifs se relisent apres reouverture', () async {
    final repository = await open();
    await repository.saveSettings(settings.copyWith(fuel: FuelType.e10));
    await repository.saveDay(CommuteDay.bike(DateTime(2026, 9, 18), settings, price));
    await repository.saveGoal(Goal(
      id: 'velo',
      name: 'Rentabiliser le vélo',
      target: 450,
      kind: GoalKind.milestone,
      icon: GoalIcon.bike,
      createdAt: DateTime(2026, 9, 1),
    ));

    final read = await reopen();

    expect((await read.readSettings()).distanceKm, 12.4);
    expect((await read.readSettings()).fuel, FuelType.e10);
    expect((await read.getDays()).single.amount, 1.09);
    expect((await read.getGoals()).single.name, 'Rentabiliser le vélo');
  });

  test('sans reglages enregistres, les valeurs par defaut', () async {
    final read = await (await open()).readSettings();

    expect(read.isConfigured, isFalse);
    expect(read.consumption, 5.2);
    expect(read.fuel, FuelType.gazole);
  });

  test('une seule journee par date : la seconde remplace la premiere', () async {
    final repository = await open();
    await repository.saveDay(CommuteDay.bike(DateTime(2026, 9, 18, 8), settings, price));
    await repository.saveDay(
        CommuteDay.car(DateTime(2026, 9, 18, 18), settings, price, CarReason.defaults.last));

    final days = await (await reopen()).getDays();
    expect(days.single.mode, CommuteMode.car);
  });

  test('effacer une journee et supprimer un objectif', () async {
    final repository = await open();
    await repository.saveDay(CommuteDay.bike(DateTime(2026, 9, 18), settings, price));
    await repository.saveGoal(Goal(
      id: 'g',
      name: 'G',
      target: 1,
      kind: GoalKind.purchase,
      icon: GoalIcon.star,
      createdAt: DateTime(2026, 9, 1),
    ));
    await repository.deleteDay(DateTime(2026, 9, 18));
    await repository.deleteGoal('g');

    final read = await reopen();
    expect(await read.getDays(), isEmpty);
    expect(await read.getGoals(), isEmpty);
  });

  test('le dernier releve au plus tard a une date, par carburant', () async {
    final repository = await open();
    await repository.recordPrice(FuelType.gazole, DateTime(2026, 9, 1), 1.65, 'A');
    await repository.recordPrice(FuelType.gazole, DateTime(2026, 9, 10), 1.70, 'B');
    await repository.recordPrice(FuelType.sp95, DateTime(2026, 9, 15), 1.85, null);

    final read = await reopen();
    final before = await read.latestPrice(FuelType.gazole, onOrBefore: DateTime(2026, 9, 5));
    final latest = await read.latestPrice(FuelType.gazole);

    expect(before?.price, 1.65);
    expect(before?.station, 'A');
    expect(latest?.day, DateTime(2026, 9, 10));
    expect(await read.latestPrice(FuelType.e85), isNull);
  });

  test('une entree corrompue est ignoree sans vider le reste', () async {
    final repository = await open();
    await repository.saveDay(CommuteDay.bike(DateTime(2026, 9, 18), settings, price));
    await Hive.box<String>('commute').put('day:2026-09-19', '{pas du json');

    final days = await (await reopen()).getDays();
    expect(days.single.date, DateTime(2026, 9, 18));
  });
}
