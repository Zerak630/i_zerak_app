import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/agent_dao.dart';
import 'package:i_zerak_app/models/commute_dao.dart' hide dateOnly, roundCents;
import 'package:i_zerak_app/services/agent/agent_service.dart';
import 'package:i_zerak_app/models/gas_station_dao.dart';
import 'package:i_zerak_app/models/torrent_dao.dart';
import 'package:i_zerak_app/models/torrent_state.dart';
import 'package:i_zerak_app/models/transfer_info_dao.dart';
import 'package:i_zerak_app/pages/dashboard/dashboard_page.dart';
import 'package:i_zerak_app/services/commute_price_service.dart';
import 'package:i_zerak_app/services/qbittorrent/qb_exceptions.dart';
import 'package:i_zerak_app/services/qbittorrent/qb_service.dart';

import '../../__mocks__/commute_fakes.dart';
import '../../__mocks__/subscription_fakes.dart';

Widget wrap(Widget child) => MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );

const _settings = CommuteSettings(distanceKm: 12.4, consumption: 5.2);

Future<SystemSnapshot> _system() async => (
      stats: const SystemStats(hostname: 'izerak', uptimeSeconds: 2937600, load1: 0.42, cpuTempC: 47.3),
      volumes: const [
        StorageVolume(
          path: '/mnt/media',
          label: 'Media',
          mounted: true,
          totalBytes: 1000,
          usedBytes: 610,
        ),
      ],
      services: const [
        ServiceStatus(name: 'qBittorrent', unit: 'qb.service', state: ServiceState.active),
        ServiceStatus(name: 'Emby', unit: 'emby.service', state: ServiceState.active),
      ],
    );

Future<TorrentsSnapshot> _torrents() async => (
      torrents: const [
        TorrentDao(
          hash: 'a',
          name: 'Le Comte de Monte-Cristo',
          progress: 0.78,
          dlspeed: 4200000,
          upspeed: 0,
          size: 12400000000,
          eta: 660,
          ratio: 1.4,
          state: TorrentState.downloading,
          category: 'Films',
          savePath: '/mnt/media/Films',
          tags: [],
          addedOn: 0,
        ),
      ],
      transfer: const TransferInfoDao(dlInfoSpeed: 4200000),
    );

void main() {
  final now = DateTime(2026, 9, 18, 19, 30);
  late MemoryCommute commute;
  late MemorySubscriptions subscriptions;
  late FakeGasService gas;

  DashboardPage page({
    Future<SystemSnapshot> Function()? system,
    Future<TorrentsSnapshot> Function()? torrents,
  }) {
    final favorites = StaticFavorites([(id: 1, label: 'Rue A, Saumur', customName: 'Leclerc')]);
    return DashboardPage(
      subscriptionService: subscriptions,
      commuteService: commute,
      stations: favorites,
      prices: CommutePriceService(
        gas: gas,
        favorites: favorites,
        store: commute,
        clock: () => now,
      ),
      systemLoader: system ?? _system,
      torrentsLoader: torrents ?? _torrents,
      clock: () => now,
    );
  }

  setUp(() {
    commute = MemoryCommute(settings: _settings);
    subscriptions = MemorySubscriptions([sub('Netflix', 13.49, next: DateTime(2026, 9, 28))]);
    gas = FakeGasService(stations: [station(1, {FuelType.gazole: 1.689})]);
  });

  Future<void> open(WidgetTester tester, {DashboardPage? given}) async {
    await tester.binding.setSurfaceSize(const Size(420, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(wrap(given ?? page()));
    await tester.pumpAndSettle();
  }

  testWidgets('l accueil rassemble la journee, l argent, le Pi et les transferts',
      (tester) async {
    await open(tester);

    expect(find.textContaining('vendredi 18 septembre'), findsOneWidget);
    expect(find.text('À vélo'), findsOneWidget);
    expect(find.text('En voiture'), findsOneWidget);
    expect(find.text('Cagnotte vélo'), findsOneWidget);
    expect(find.text('izerak'), findsOneWidget);
    expect(find.textContaining('47 °C'), findsOneWidget);
    expect(find.textContaining('61 %'), findsOneWidget);
    expect(find.text('Le Comte de Monte-Cristo'), findsOneWidget);
    expect(find.textContaining('1,689'), findsOneWidget);
  });

  testWidgets('un appui sur « À vélo » enregistre la journee', (tester) async {
    await open(tester);

    await tester.tap(find.text('À vélo'));
    await tester.pumpAndSettle();

    expect(commute.days, hasLength(1));
    expect(find.text('Vélo, aujourd’hui'), findsOneWidget);
    expect(find.text('À vélo'), findsNothing);
  });

  testWidgets('le Pi injoignable n efface pas le reste de la page', (tester) async {
    await open(tester, given: page(system: () async => throw const QbNetworkException('coupe')));

    expect(find.text('Raspberry Pi injoignable'), findsOneWidget);
    // Les sources locales et les transferts restent affiches.
    expect(find.text('Cagnotte vélo'), findsOneWidget);
    expect(find.text('Le Comte de Monte-Cristo'), findsOneWidget);
  });

  testWidgets('un serveur non configure le dit sans alarmer', (tester) async {
    await open(tester,
        given: page(torrents: () async => throw const QbNotConfiguredException()));

    expect(find.textContaining('Renseignez l’adresse du serveur'), findsOneWidget);
  });

  testWidgets('sans trajet regle, l accueil invite a le faire', (tester) async {
    commute = MemoryCommute(settings: const CommuteSettings());
    await open(tester);

    expect(find.text('Réglez votre trajet pour enregistrer vos journées'), findsOneWidget);
    expect(find.text('À vélo'), findsNothing);
  });

  testWidgets('la carte du mois ouvre le budget', (tester) async {
    await open(tester);

    await tester.tap(find.text('CE MOIS-CI'));
    await tester.pumpAndSettle();

    expect(find.text('Budget'), findsOneWidget);
    expect(find.text('Sorties du mois'.toUpperCase()), findsOneWidget);
  });
}
