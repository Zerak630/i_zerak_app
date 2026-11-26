/// Les categories depliees des reglages doivent survivre a la fermeture de
/// l'application : la boite est rouverte depuis le disque.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:i_zerak_app/models/settings_category.dart';
import 'package:i_zerak_app/services/repositories/hive/hive_app_preferences.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('izerak_preferences_test');
    Hive.init(directory.path);
  });

  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  Future<HiveAppPreferences> open() async =>
      HiveAppPreferences(await Hive.openBox<String>('preferences'));

  Future<HiveAppPreferences> reopen() async {
    await Hive.box<String>('preferences').close();
    return open();
  }

  test('rien de deplie tant que rien n a ete ouvert', () async {
    final preferences = await open();

    expect(await preferences.readExpandedSettings(), isEmpty);
  });

  test('les categories depliees se relisent apres redemarrage', () async {
    final preferences = await open();
    await preferences.saveExpandedSettings({SettingsCategory.games, SettingsCategory.server});

    final read = await (await reopen()).readExpandedSettings();

    expect(read, {SettingsCategory.games, SettingsCategory.server});
  });

  test('une valeur abimee replie tout plutot que de bloquer l ecran', () async {
    final box = await Hive.openBox<String>('preferences');
    await box.put('settings_expanded', '{pas du json');

    expect(await HiveAppPreferences(box).readExpandedSettings(), isEmpty);
  });
}
