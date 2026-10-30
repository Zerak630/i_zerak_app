import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/agent_dao.dart';
import 'package:i_zerak_app/models/commute_dao.dart' hide dateOnly, roundCents;
import 'package:i_zerak_app/models/companion_dao.dart';
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

  testWidgets('sur grand ecran, les cartes se posent en trois colonnes', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(wrap(page()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final day = tester.getTopLeft(find.text('À vélo'));
    final money = tester.getTopLeft(find.text('Cagnotte vélo'));
    final pi = tester.getTopLeft(find.textContaining('47 °C'));
    // Cote a cote, de gauche a droite, dans l'ordre du telephone.
    expect(day.dx, lessThan(money.dx));
    expect(money.dx, lessThan(pi.dx));
    expect(pi.dy, lessThan(450));
  });

  testWidgets('entre les deux, l argent rejoint la journee', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(wrap(page()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final day = tester.getTopLeft(find.text('À vélo'));
    final money = tester.getTopLeft(find.text('Cagnotte vélo'));
    final pi = tester.getTopLeft(find.textContaining('47 °C'));
    // La journee et l'argent a gauche, l'un sous l'autre ; le Pi a droite.
    expect(day.dx, lessThan(450));
    expect(money.dx, lessThan(450));
    expect(money.dy, greaterThan(day.dy));
    expect(pi.dx, greaterThan(450));
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
testWidgets('le defi du mois tient sur une ligne et ouvre sa page', (tester) async {
    commute = MemoryCommute(
      settings: _settings,
      days: [
        for (final day in [14, 15, 16, 17])
          CommuteDay(
            date: DateTime(2026, 9, day),
            mode: CommuteMode.bike,
            amount: 1.09,
            pricePerLitre: 1.689,
            priceSource: PriceSource.live,
          ),
      ],
      challenges: [ChallengeTarget(month: DateTime(2026, 9), target: 10)],
    );
    await open(tester);

    expect(find.text('Défi du mois'), findsOneWidget);
    expect(
      find.text('Il en reste 6 à faire, et 9 jours ouvrés pour les faire.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Défi du mois'));
    await tester.pumpAndSettle();

    // La page poussee montre le pas-a-pas, que la carte n'a pas.
    expect(find.text('Cible du mois'), findsOneWidget);
  });

  testWidgets('sans cible, la carte invite a en fixer une', (tester) async {
    await open(tester);

    expect(find.text('Défi du mois'), findsOneWidget);
    expect(find.text('Se fixer une cible'), findsOneWidget);
  });

  testWidgets('sans trajet regle, le defi ne s affiche pas', (tester) async {
    commute = MemoryCommute();
    await open(tester);

    expect(find.text('Défi du mois'), findsNothing);
  });
}
