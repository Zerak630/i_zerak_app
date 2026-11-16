import 'package:flutter_test/flutter_test.dart';
import 'package:i_zerak_app/models/commute_dao.dart';
import 'package:i_zerak_app/models/gas_station_dao.dart';
import 'package:i_zerak_app/models/payback_dao.dart';
import 'package:i_zerak_app/services/commute_price_service.dart';
import 'package:i_zerak_app/services/home_widgets/home_widgets_service.dart';

import '../../__mocks__/commute_fakes.dart';
import '../../__mocks__/subscription_fakes.dart';

/// Des widgets imaginaires : ce qu'on leur envoie, et ce qu'ils ont note.
class FakeBridge implements IHomeWidgetBridge {
  bool supported = true;
  final List<Map<String, Object?>> snapshots = [];
  List<String> pending = [];
  String? action;

  @override
  bool get isSupported => supported;

  @override
  Future<void> update(Map<String, Object?> snapshot) async => snapshots.add(snapshot);

  @override
  Future<List<String>> takePendingBikeDays() async {
    final days = pending;
    pending = [];
    return days;
  }

  @override
  Future<String?> takeLaunchAction() async {
    final taken = action;
    action = null;
    return taken;
  }
}

Goal goal(String id, double target, {GoalKind kind = GoalKind.purchase}) => Goal(
      id: id,
      name: id,
      target: target,
      kind: kind,
      icon: GoalIcon.gift,
      createdAt: DateTime(2026, 9, 1),
    );

void main() {
  final now = DateTime(2026, 9, 18, 18);
  const settings = CommuteSettings(distanceKm: 12.4, consumption: 5.2);
  late MemoryCommute commute;
  late MemorySubscriptions subscriptions;
  late FakeGasService gas;
  late FakeBridge bridge;

  HomeWidgetsService service() {
    final favorites = StaticFavorites([(id: 1, label: 'Rue A', customName: null)]);
    return HomeWidgetsService(
      commute: commute,
      subscriptions: subscriptions,
      prices: CommutePriceService(gas: gas, favorites: favorites, store: commute, clock: () => now),
      bridge: bridge,
      clock: () => now,
    );
  }

  setUp(() {
    commute = MemoryCommute(settings: settings);
    subscriptions = MemorySubscriptions();
    gas = FakeGasService(stations: [station(1, {FuelType.gazole: 1.689})]);
    bridge = FakeBridge();
  });

  test('les journees a velo notees par le widget sont enregistrees une fois', () async {
    bridge.pending = ['2026-09-18', '2026-09-17', 'n importe quoi'];
    commute.days['2026-09-17'] = CommuteDay.car(
      DateTime(2026, 9, 17),
      settings,
      const ResolvedPrice.fallback(),
      CarBucket.essential,
    );

    expect(await service().importPendingBikeDays(), 1);

    expect(commute.days['2026-09-18']!.isBike, isTrue);
    expect(commute.days['2026-09-18']!.amount, settings.tripValue(1.689));
    // La journee deja saisie dans l'application n'est pas ecrasee.
    expect(commute.days['2026-09-17']!.isBike, isFalse);
    expect(await service().importPendingBikeDays(), 0, reason: 'relire les efface');
  });

  test('sans trajet regle, rien n est invente', () async {
    commute.settings = const CommuteSettings();
    bridge.pending = ['2026-09-18'];

    expect(await service().importPendingBikeDays(), 0);
    expect(commute.days, isEmpty);
  });

  test('l instantane reunit la journee, les abonnements rembourses et les paliers', () async {
    commute.days['2026-09-18'] =
        CommuteDay.bike(DateTime(2026, 9, 18), settings, const ResolvedPrice.fallback());
    commute.goals['velo'] = goal('velo', 40);
    commute.goals['fait'] = goal('fait', 1).validated(DateTime(2026, 9, 10));
    subscriptions.items['Spotify'] = sub('Spotify', 10.99);
    subscriptions.items['Loyer'] = sub('Loyer', 700);
    commute.settings = settings.copyWith(paybackExcluded: {'Loyer'});
    await commute.recordPrice(FuelType.gazole, DateTime(2026, 9, 17), 1.7, null);

    await service().refresh();

    final snapshot = bridge.snapshots.single;
    expect(snapshot['today'], '2026-09-18');
    final day = snapshot['commute']! as Map;
    expect(day['configured'], isTrue);
    expect(day['recorded'], 'bike');
    expect(day['tripValue'], settings.tripValue(1.7));

    final goals = (snapshot['goals']! as List).cast<Map>();
    expect(goals.map((g) => g['id']), ['payback', 'velo'],
        reason: 'un objectif valide ne s affiche plus');
    expect(goals.first['pot'], 'payback');
    expect(goals.first['count'], 1, reason: 'le loyer est exclu');
    expect(goals.first['paid'], 0);
    expect(goals.first['target'], 10.99);
    expect(goals.first['current'], settings.tripValue(kFallbackFuelPrice));
    expect(goals.last['pot'], 'commute');
    expect(goals.last['milestone'], isTrue);
  });

  test('en voiture, l instantane dit dans quelle case le trajet est parti', () async {
    final day = CommuteDay.car(
        DateTime(2026, 9, 18), settings, const ResolvedPrice.fallback(), CarBucket.missed);
    commute.days['2026-09-18'] = day;

    await service().refresh();

    final today = bridge.snapshots.single['commute']! as Map;
    expect(today['recorded'], 'car');
    expect(today['bucket'], 'missed');
    expect(today['amount'], day.amount);
  });

  test('a velo, pas de case de voiture', () async {
    commute.days['2026-09-18'] =
        CommuteDay.bike(DateTime(2026, 9, 18), settings, const ResolvedPrice.fallback());
    await service().refresh();
    expect((bridge.snapshots.single['commute']! as Map).containsKey('bucket'), isFalse);
  });

  test('hors Android, rien n est envoye', () async {
    bridge.supported = false;
    await service().refresh();
    expect(bridge.snapshots, isEmpty);
  });

  test('l action du widget n est rendue qu une fois', () async {
    bridge.action = 'car';
    expect(await service().takeLaunchAction(), 'car');
    expect(await service().takeLaunchAction(), isNull);
  });

  test('l instantane se construit sans stockage', () {
    final snapshot = HomeWidgetsService.buildSnapshot(
      today: DateTime(2026, 9, 18),
      commuteConfigured: false,
      tripValue: 0,
      recorded: null,
      payback: MonthPayback(month: DateTime(2026, 9), saved: 0, bikeDays: 0, lines: const []),
      book: GoalBook([goal('g', 10)], savings: [(date: DateTime(2026, 9, 2), amount: 4)]),
    );
    final day = snapshot['commute']! as Map;
    expect(day.containsKey('recorded'), isFalse);
    expect(((snapshot['goals']! as List).single as Map)['current'], 4);
  });

}
