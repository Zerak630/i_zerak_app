/// Les stations favorites doivent survivre a la fermeture de l'application.
///
/// Meme precaution que pour la configuration : une boite Hive sert ses valeurs
/// depuis un cache en memoire. Ces tests rouvrent donc la boite depuis le
/// disque plutot que de relire celle qu'ils viennent d'ecrire.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:i_zerak_app/models/gas_station_dao.dart';
import 'package:i_zerak_app/services/repositories/hive/hive_gas_station_repository.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('izerak_gas_test');
    Hive.init(directory.path);
  });

  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  Future<Box<String>> open() => Hive.openBox<String>('gas_stations');

  test('une station enregistree se relit apres reouverture', () async {
    await HiveGasStationRepository(await open())
        .add((id: 49400004, label: 'ZI Ecoparc, Saumur', customName: null));
    await Hive.box<String>('gas_stations').close();

    final read = await HiveGasStationRepository(await open()).getAll();

    expect(read.single.id, 49400004);
    expect(read.single.label, 'ZI Ecoparc, Saumur');
  });

  test('le fichier est reellement ecrit, pas seulement le cache', () async {
    await HiveGasStationRepository(await open()).add((id: 1, label: 'A', customName: null));

    expect(await File('${directory.path}/gas_stations.hive').length(), greaterThan(0));
  });

  test('ajouter deux fois la meme station ne la duplique pas', () async {
    // La cle est l'identifiant, pas un compteur : c'est ce qui garantit
    // l'unicite meme si l'interface laissait passer un doublon.
    final repository = HiveGasStationRepository(await open());
    await repository.add((id: 7, label: 'Ancien libelle', customName: null));
    await repository.add((id: 7, label: 'Nouveau libelle', customName: null));

    final read = await repository.getAll();
    expect(read.length, 1);
    expect(read.single.label, 'Nouveau libelle');
  });

  test('la suppression porte sur l identifiant', () async {
    final repository = HiveGasStationRepository(await open());
    await repository.add((id: 1, label: 'A', customName: null));
    await repository.add((id: 2, label: 'B', customName: null));
    await repository.delete(1);

    expect((await repository.getAll()).single.id, 2);
  });

  test('une boite vierge, avant amorcage, renvoie une liste vide', () async {
    expect(await HiveGasStationRepository(await open()).getAll(), isEmpty);
  });

  group('amorcage des stations historiques', () {
    test('une boite vierge recoit les sept stations codees en dur', () async {
      // Sans cet amorcage, la mise a jour qui rend la liste modifiable la
      // ferait commencer vide, et effacerait ce que l'utilisateur suivait.
      final repository = HiveGasStationRepository(await open());
      await repository.seedLegacyStationsIfEmpty();

      final read = await repository.getAll();
      expect(read.length, 7);
      expect(read.map((s) => s.id), contains(49400004));
    });

    test('le drapeau ne compte pas pour une station', () async {
      // Il partage la boite avec elles : une cle non numerique doit rester
      // invisible pour getAll, sinon une huitieme ligne fantome apparait.
      final repository = HiveGasStationRepository(await open());
      await repository.seedLegacyStationsIfEmpty();

      expect((await repository.getAll()).map((s) => s.label), isNot(contains('1')));
    });

    test('une liste videe a la main ne se repeuple pas au lancement suivant',
        () async {
      final repository = HiveGasStationRepository(await open());
      await repository.seedLegacyStationsIfEmpty();
      for (final station in await repository.getAll()) {
        await repository.delete(station.id);
      }
      await repository.seedLegacyStationsIfEmpty();

      expect(await repository.getAll(), isEmpty);
    });

    test('un amorcage ne s applique pas a une boite deja peuplee', () async {
      final repository = HiveGasStationRepository(await open());
      await repository.add((id: 1, label: 'A', customName: null));
      await repository.seedLegacyStationsIfEmpty();

      expect((await repository.getAll()).single.id, 1);
    });
  });
  group('carburant suivi', () {
    test('le gazole par defaut, avant tout choix', () async {
      expect(await HiveGasStationRepository(await open()).readFuel(), FuelType.gazole);
    });

    test('le choix survit a la fermeture de l application', () async {
      await HiveGasStationRepository(await open()).saveFuel(FuelType.sp98);
      await Hive.box<String>('gas_stations').close();

      expect(await HiveGasStationRepository(await open()).readFuel(), FuelType.sp98);
    });

    test('il partage la boite des stations sans s y melanger', () async {
      // Sa cle n'est pas numerique : getAll doit l'ignorer, sinon une station
      // fantome apparait dans la liste.
      final repository = HiveGasStationRepository(await open());
      await repository.add((id: 1, label: 'A', customName: null));
      await repository.saveFuel(FuelType.e85);

      expect((await repository.getAll()).single.id, 1);
    });

    test('un carburant enregistre n empeche pas l amorcage', () async {
      // L'amorcage comptait les entrees de la boite : le carburant en etait
      // une, et sa presence suffisait a faire croire la liste non vide.
      final repository = HiveGasStationRepository(await open());
      await repository.saveFuel(FuelType.e10);
      await repository.seedLegacyStationsIfEmpty();

      expect((await repository.getAll()).length, 7);
    });
  });
}
