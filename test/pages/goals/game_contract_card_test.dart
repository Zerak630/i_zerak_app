import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/game_dao.dart';
import 'package:i_zerak_app/pages/goals/widgets/game_contract_card.dart';

void main() {
  Future<void> show(WidgetTester tester, GameContract? contract, {GamingReport? report}) =>
      tester.pumpWidget(MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: GameContractCard(
            report: report ?? const GamingReport(sources: ['steam']),
            settings: const GameContractSettings(),
            contract: contract,
            streak: 3,
            onSettings: () {},
          ),
        ),
      ));

  GameContract contract({int sport = 45, int bikeDays = 2}) => GameContract(
        monday: DateTime(2026, 11, 30),
        playedBefore: 760,
        targetMinutes: 255,
        sportMinutes: sport,
        bikeDays: bikeDays,
        bikeMinutes: bikeDays * 60,
      );

  testWidgets('la carte dit le jeu, la cible et ce qui reste, velo compris', (tester) async {
    await show(tester, contract());

    expect(find.text('Semaine dernière : 12 h 40 de jeu'), findsOneWidget);
    expect(find.text('À compenser : 4 h 15 de sport'), findsOneWidget);
    expect(find.text('Encore 1 h 30 d’ici dimanche soir'), findsOneWidget);
    expect(find.text('Séances 45 min · vélo 2 h 00'), findsOneWidget);
    expect(find.text('Série : 3 semaines tenues'), findsOneWidget);
  });

  testWidgets('sans semaine complete, elle ne promet rien', (tester) async {
    await show(tester, null);
    expect(find.textContaining('Pas de contrat cette semaine'), findsOneWidget);
  });

  testWidgets('elle signale une source en panne', (tester) async {
    await show(
      tester,
      contract(),
      report: const GamingReport(sources: ['steam', 'lol'], errors: {'lol': 'unauthorized'}),
    );
    expect(find.text('Dernier relevé en échec : LoL'), findsOneWidget);
  });
}
