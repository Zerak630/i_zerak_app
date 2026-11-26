import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/game_dao.dart';
import 'package:i_zerak_app/pages/gaming/game_stats_page.dart';
import 'package:i_zerak_app/services/gaming/gaming_service.dart';

import '../../__mocks__/recap_fakes.dart';

void main() {
  // Jeudi 26 novembre 2026 : la semaine du lundi 23 est en cours.
  DateTime clock() => DateTime(2026, 11, 26, 18);

  final current = GameWeek(
    monday: DateTime(2026, 11, 23),
    minutes: 120,
    complete: false,
    steamMinutes: 60,
    lolMinutes: 60,
    lolGames: 2,
    lolWins: 1,
    games: const [GameTitle(name: 'Balatro', minutes: 60, lifetimeMinutes: 1380)],
  );
  final previous = GameWeek(
    monday: DateTime(2026, 11, 16),
    minutes: 460,
    complete: true,
    steamMinutes: 290,
    lolMinutes: 170,
    lolGames: 7,
    lolWins: 4,
    lpChange: 38,
    games: const [
      GameTitle(name: 'Hades II', minutes: 160, lifetimeMinutes: 3480),
      GameTitle(name: 'Factorio', minutes: 130, lifetimeMinutes: 24720),
    ],
    days: [
      for (var offset = 0; offset < 7; offset++)
        GameDay(
          day: DateTime(2026, 11, 16 + offset),
          steamMinutes: offset == 5 ? 110 : 0,
          measured: offset == 1 ? const [] : const ['steam', 'lol'],
        ),
    ],
    matches: const [
      LolMatch(minutes: 31, win: true, champion: 'Ahri', kills: 8, deaths: 2, assists: 9, queueId: 420),
      LolMatch(minutes: 29, win: false, champion: 'Jinx', queueId: 450),
      LolMatch(minutes: 27, win: true, champion: 'Lux', queueId: 400),
    ],
  );
  final report = GamingReport(
    sources: const ['steam', 'lol'],
    weeks: [current, previous],
    lolRank: const LolRank(tier: 'GOLD', division: 'II', lp: 54, wins: 30, losses: 25),
  );

  Future<void> show(WidgetTester tester, {GamingReport? with_, GameStatsTab tab = GameStatsTab.all, bool embedded = false}) async {
    // Un telephone haut : la liste entiere est construite.
    tester.view.physicalSize = const Size(400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final preferences = MemoryPreferences()..gaming = with_ ?? report;
    final service = GamingService(fetch: () async => with_ ?? report, preferences: preferences);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: GameStatsPage(service: service, clock: clock, initialTab: tab, embedded: embedded)),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> previousWeek(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Semaine précédente'));
    await tester.pumpAndSettle();
  }

  testWidgets('la synthese part de la semaine en cours, provisoire', (tester) async {
    await show(tester);

    expect(find.text('Cette semaine'), findsOneWidget);
    expect(find.text('2 h 00'), findsOneWidget);
    expect(find.text('5 h 40 de moins que la précédente'), findsOneWidget);
    expect(find.text('2 DERNIÈRES SEMAINES'), findsOneWidget);
    expect(find.textContaining('provisoire'), findsOneWidget);
  });

  testWidgets('les chevrons changent de semaine', (tester) async {
    await show(tester);
    await previousWeek(tester);

    expect(find.text('Semaine du 16 novembre'), findsOneWidget);
    expect(find.text('7 h 40'), findsOneWidget);
    expect(find.text('LoL · 2 h 50 · 7 parties'), findsOneWidget);
    expect(find.textContaining('provisoire'), findsNothing);
  });

  testWidgets('Steam : les jeux, les jours et le cumul', (tester) async {
    await show(tester, tab: GameStatsTab.steam);
    await previousWeek(tester);

    expect(find.text('Hades II'), findsNWidgets(2));
    expect(find.text('2 h 40 · 55 %'), findsOneWidget);
    expect(find.text('2 jeux lancés'), findsOneWidget);
    // Le mardi n'a pas ete releve : un tiret, pas un zero.
    expect(find.text('—'), findsOneWidget);
    expect(find.text('1 h 50'), findsOneWidget);
    expect(find.text('412 h'), findsOneWidget);
    expect(find.text('58 h'), findsOneWidget);
  });

  testWidgets('LoL : les parties, la file, le rang', (tester) async {
    await show(tester, tab: GameStatsTab.lol);
    await previousWeek(tester);

    expect(find.text('57 %'), findsNothing);
    expect(find.text('Ahri'), findsOneWidget);
    expect(find.text('Classé solo'), findsOneWidget);
    expect(find.textContaining('8 / 2 / 9'), findsOneWidget);
    expect(find.text('ARAM'), findsOneWidget);
    expect(find.text('Or II · 54 LP'), findsOneWidget);
    expect(find.text('+38 LP cette semaine'), findsOneWidget);
    expect(find.text('4 parties comptées sans détail, avant que l’agent le garde.'), findsOneWidget);

    await tester.tap(find.text('ARAM · 1'));
    await tester.pumpAndSettle();
    expect(find.text('Ahri'), findsNothing);
    expect(find.text('Jinx'), findsOneWidget);
  });

  testWidgets('avec la seule source LoL, pas d\'onglets', (tester) async {
    await show(
      tester,
      with_: GamingReport(sources: const ['lol'], weeks: [current, previous]),
    );
    expect(find.byType(SegmentedButton<GameStatsTab>), findsNothing);
    expect(find.text('Parties'), findsOneWidget);
    // Sans rang lu, pas de carte de rang.
    expect(find.text('CLASSÉ SOLO'), findsNothing);
  });

  testWidgets('sans releve, l\'ecran le dit', (tester) async {
    await show(tester, with_: const GamingReport(sources: ['steam']));
    expect(find.text('Pas encore de relevé'), findsWidgets);
  });

  testWidgets('comme onglet, ni AppBar ni retour, mais le titre et l\'actualisation', (tester) async {
    await show(tester, embedded: true);
    expect(find.byType(AppBar), findsNothing);
    expect(find.text('Temps de jeu'), findsOneWidget);
    expect(find.byTooltip('Actualiser'), findsOneWidget);
    expect(find.text('2 h 00'), findsOneWidget);
  });
}
