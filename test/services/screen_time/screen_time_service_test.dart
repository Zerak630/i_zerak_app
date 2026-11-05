import 'package:flutter_test/flutter_test.dart';
import 'package:i_zerak_app/models/screen_time_dao.dart';
import 'package:i_zerak_app/services/screen_time/screen_time_service.dart';
import 'package:i_zerak_app/services/screen_time/usage_source.dart';

import '../../__mocks__/screen_time_fakes.dart';

const insta = 'com.instagram.android';

UsageSession minutesOn(DateTime start, int minutes) =>
    UsageSession(insta, start, start.add(Duration(minutes: minutes)));

void main() {
  final now = DateTime(2026, 11, 10, 20, 0);
  final configured = ScreenTimeSettings(
    apps: const [TrackedApp(package: insta, label: 'Instagram')],
    baselineMinutes: 120,
    startDate: DateTime(2026, 11, 2),
  );

  late MemoryScreenTime store;
  late FakeUsageSource source;

  ScreenTimeService service() => ScreenTimeService(store: store, source: source, clock: () => now);

  setUp(() {
    store = MemoryScreenTime(settings: configured);
    source = FakeUsageSource();
  });

  test('fige les journees terminees qu\'Android garde encore, et mesure aujourd\'hui', () async {
    source.recordedDays.addAll([DateTime(2026, 11, 8), DateTime(2026, 11, 9), DateTime(2026, 11, 10)]);
    source.recorded.addAll([
      minutesOn(DateTime(2026, 11, 9, 21), 60),
      minutesOn(DateTime(2026, 11, 8, 12), 150),
      minutesOn(DateTime(2026, 11, 10, 8), 20),
    ]);

    final ledger = await service().sync();

    expect(store.days.keys, unorderedEquals(['2026-11-08', '2026-11-09']));
    expect(ledger.dayOn(DateTime(2026, 11, 9))!.amount, 2.0);
    expect(ledger.dayOn(DateTime(2026, 11, 8))!.amount, 0);
    expect(ledger.dayOn(DateTime(2026, 11, 8))!.missed, 0.4,
        reason: '150 min au-dessus du quota de 108 : le gain du quota est loupe');
    expect(ledger.live.minutes, 20);
    // Les jours sans trace ne sont pas comptes comme des journees parfaites.
    expect(ledger.dayOn(DateTime(2026, 11, 7)), isNull);
    expect(ledger.totalSaved, 2.0);
  });

  test('une journee deja figee n\'est plus relue', () async {
    source.recordedDays.addAll([DateTime(2026, 11, 9), DateTime(2026, 11, 10)]);
    await service().sync();
    source.queried.clear();

    await service().sync();

    expect(source.queried, isNot(contains(DateTime(2026, 11, 9))));
    expect(source.queried, contains(DateTime(2026, 11, 10)));
    // Un jour sans trace est retente : Android l'a peut-etre rattrape depuis.
    expect(source.queried, contains(DateTime(2026, 11, 8)));
  });

  test('ne remonte pas avant la mise en route', () async {
    store.settings = ScreenTimeSettings.fromJson({...configured.toJson(), 'start': '2026-11-09'});
    source.recordedDays.addAll([DateTime(2026, 11, 8), DateTime(2026, 11, 9)]);

    await service().sync();

    expect(store.days.keys, ['2026-11-09']);
  });

  test('sans acces, rien n\'est mesure ni fige', () async {
    source
      ..access = false
      ..recordedDays.add(DateTime(2026, 11, 9));

    final ledger = await service().sync();

    expect(store.days, isEmpty);
    expect(ledger.live.seconds, 0);
  });

  test('transmet au bilan du soir la serie arretee a hier', () async {
    source.recordedDays.addAll([DateTime(2026, 11, 8), DateTime(2026, 11, 9)]);

    await service().sync();

    final report = source.reports.last!;
    expect(report['enabled'], isTrue);
    expect(report['hour'], 21);
    expect(report['minute'], 30);
    expect(report['packages'], [insta]);
    expect(report['streak'], 2);
    expect(report['streakThroughEpochDay'], ScreenTimeService.epochDay(DateTime(2026, 11, 9)));
    expect(report['startEpochDay'], ScreenTimeService.epochDay(DateTime(2026, 11, 2)));
  });

  test('bilan desactive : les reglages partent quand meme, pour le widget', () async {
    store.settings = configured.copyWith(reportEnabled: false);
    await service().sync();
    expect(source.reports.last!['enabled'], isFalse);
    expect(source.reports.last!['packages'], [insta]);
  });

  test('non configure : rien n est transmis', () async {
    store.settings = const ScreenTimeSettings();
    await service().sync();
    expect(source.reports.last, isNull);
  });

  test('la moyenne de depart ignore les jours sans trace', () async {
    source.recordedDays.addAll([DateTime(2026, 11, 8), DateTime(2026, 11, 9)]);
    source.recorded.addAll([
      minutesOn(DateTime(2026, 11, 8, 12), 100),
      minutesOn(DateTime(2026, 11, 9, 12), 50),
    ]);

    final baseline = await service().measureBaseline({insta});

    expect(baseline!.minutes, 75);
    expect(baseline.days, 2);
    expect(await service().measureBaseline({'com.autre'}), isNotNull,
        reason: 'des jours enregistres sans usage valent zero minute');
    source.recordedDays.clear();
    expect(await service().measureBaseline({insta}), isNull);
  });

  test('la mise en route fige la moyenne et le premier jour', () async {
    store.settings = const ScreenTimeSettings(ratePerHour: 3);
    final settings = await service().start(
        const [TrackedApp(package: insta, label: 'Instagram')], (minutes: 95.5, days: 7));

    expect(settings.isConfigured, isTrue);
    expect(settings.baselineMinutes, 95.5);
    expect(settings.startDate, DateTime(2026, 11, 10));
    expect(settings.ratePerHour, 3, reason: 'les reglages deja choisis sont gardes');
    expect(store.settings.isConfigured, isTrue);
  });

  test('relit la reponse du canal Android', () {
    final window = parseUsageWindow({
      'hasData': true,
      'sessions': [
        {'p': insta, 's': 1000, 'e': 61000},
        {'p': 42, 's': 0, 'e': 1},
      ],
    });
    expect(window.hasData, isTrue);
    expect(window.sessions.single.duration, const Duration(minutes: 1));
    expect(parseUsageWindow(null).hasData, isFalse);
  });
}
