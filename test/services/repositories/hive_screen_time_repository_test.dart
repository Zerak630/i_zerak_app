/// Le temps libre doit survivre a la fermeture de l'application.
///
/// Comme pour les trajets, la boite est rouverte depuis le disque.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:i_zerak_app/models/commute_dao.dart' show Goal, GoalIcon, GoalKind;
import 'package:i_zerak_app/models/screen_time_dao.dart';
import 'package:i_zerak_app/services/repositories/hive/hive_screen_time_repository.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('izerak_screen_time_test');
    Hive.init(directory.path);
  });

  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  Future<HiveScreenTimeRepository> open() async =>
      HiveScreenTimeRepository(await Hive.openBox<String>('screen_time'));

  Future<HiveScreenTimeRepository> reopen() async {
    await Hive.box<String>('screen_time').close();
    return open();
  }

  test('reglages, journees et objectifs se relisent apres reouverture', () async {
    final settings = ScreenTimeSettings(
      apps: const [TrackedApp(package: 'com.instagram.android', label: 'Instagram')],
      baselineMinutes: 110,
      startDate: DateTime(2026, 11, 2),
    );
    final usage = DailyUsage.fromSessions(DateTime(2026, 11, 3), [
      UsageSession('com.instagram.android', DateTime(2026, 11, 3, 22), DateTime(2026, 11, 3, 22, 40)),
    ], settings.packages);

    var repository = await open();
    await repository.saveSettings(settings);
    await repository.saveDay(settings.close(usage));
    await repository.saveGoal(Goal(
      id: 'g1',
      name: 'Concert',
      target: 40,
      kind: GoalKind.purchase,
      icon: GoalIcon.gift,
      createdAt: DateTime(2026, 11, 3),
    ));

    repository = await reopen();
    final read = await repository.readSettings();
    final days = await repository.getDays();
    expect(read.isConfigured, isTrue);
    expect(read.apps.single.label, 'Instagram');
    expect(days.single.minutes, 40);
    expect(days.single.usage.hourly[22], 40 * 60);
    expect(days.single.amount, 2.33);
    expect((await repository.getGoals()).single.name, 'Concert');

    await repository.deleteGoal('g1');
    repository = await reopen();
    expect(await repository.getGoals(), isEmpty);
  });

  test('une entree illisible est ignoree', () async {
    final box = await Hive.openBox<String>('screen_time');
    await box.put('day:2026-11-03', '{pas du json');
    await box.put('settings', '[]');
    final repository = HiveScreenTimeRepository(box);

    expect(await repository.getDays(), isEmpty);
    expect((await repository.readSettings()).isConfigured, isFalse);
  });
}
