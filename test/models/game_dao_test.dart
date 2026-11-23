import 'package:i_zerak_app/models/commute_dao.dart';
import 'package:i_zerak_app/models/game_dao.dart';
import 'package:i_zerak_app/models/sport_dao.dart';
import 'package:test/test.dart';

void main() {
  // Mercredi 2 decembre 2026 : la semaine du lundi 30 novembre.
  final today = DateTime(2026, 12, 2);
  final monday = DateTime(2026, 11, 30);

  GameWeek week(DateTime monday, int minutes, {bool complete = true}) =>
      GameWeek(monday: monday, minutes: minutes, complete: complete);

  CommuteDay bike(DateTime date) => CommuteDay(
        date: date,
        mode: CommuteMode.bike,
        amount: 2,
        pricePerLitre: 1.7,
        priceSource: PriceSource.live,
      );

  GameContractLedger ledger(
    List<GameWeek> weeks, {
    List<SportSession> sessions = const [],
    List<CommuteDay> commute = const [],
    GameContractSettings settings = const GameContractSettings(),
    DateTime? now,
  }) =>
      GameContractLedger(
        report: GamingReport(sources: const ['steam'], weeks: weeks),
        settings: settings,
        sport: SportLedger(
          sports: Sport.defaults,
          plan: const [],
          sessions: sessions,
          today: now ?? today,
        ),
        commute: commute,
      );

  group('la cible', () {
    test('1 h de sport pour 3 h de jeu, arrondie aux cinq minutes', () {
      expect(const GameContractSettings().targetFor(760), 255);
      expect(const GameContractSettings().targetFor(180), 60);
    });

    test('plafonnee apres une semaine de vacances', () {
      expect(const GameContractSettings().targetFor(40 * 60), 360);
    });

    test('rien a compenser sans jeu', () {
      expect(const GameContractSettings().targetFor(0), 0);
    });
  });

  group('le contrat', () {
    test('le jeu de la semaine passee fixe le sport de celle-ci', () {
      final contract = ledger([week(DateTime(2026, 11, 23), 760), week(monday, 999)])
          .contractOf(today)!;
      expect((contract.playedBefore, contract.targetMinutes), (760, 255));
    });

    test('une journee a velo compte pour une heure, en plus des seances', () {
      final contract = ledger(
        [week(DateTime(2026, 11, 23), 760)],
        sessions: [SportSession(id: 'a', date: monday, sportId: Sport.yoga, minutes: 45)],
        commute: [bike(monday), bike(DateTime(2026, 12, 1)), bike(DateTime(2026, 11, 27))],
      ).contractOf(today)!;

      expect((contract.bikeDays, contract.bikeMinutes), (2, 120));
      expect((contract.doneMinutes, contract.remaining, contract.kept), (165, 90, false));
    });

    test('la duree du trajet a velo se regle', () {
      final contract = ledger(
        [week(DateTime(2026, 11, 23), 180)],
        commute: [bike(monday)],
        settings: const GameContractSettings(bikeMinutesPerDay: 40),
      ).contractOf(today)!;
      expect((contract.doneMinutes, contract.kept), (40, false));
    });

    test('une semaine incomplete ne fixe aucun contrat', () {
      expect(
        ledger([week(DateTime(2026, 11, 23), 760, complete: false)]).contractOf(today),
        isNull,
      );
    });

    test('desactive, il n apparait plus', () {
      expect(
        ledger(
          [week(DateTime(2026, 11, 23), 760)],
          settings: const GameContractSettings(enabled: false),
        ).contractOf(today),
        isNull,
      );
    });
  });

  group('la serie', () {
    final weeks = [
      week(DateTime(2026, 11, 2), 180),
      week(DateTime(2026, 11, 9), 180),
      week(DateTime(2026, 11, 16), 180),
      week(DateTime(2026, 11, 23), 180),
      week(monday, 0),
    ];

    SportSession hour(DateTime date) =>
        SportSession(id: '$date', date: date, sportId: Sport.running, minutes: 60);

    test('la semaine en cours pas encore tenue ne rompt rien', () {
      final games = ledger(weeks, sessions: [
        hour(DateTime(2026, 11, 10)),
        hour(DateTime(2026, 11, 17)),
        hour(DateTime(2026, 11, 24)),
      ]);
      expect(games.streakAt(today), 3);
    });

    test('une semaine finie et manquee la rompt', () {
      final games = ledger(weeks, sessions: [
        hour(DateTime(2026, 11, 10)),
        hour(DateTime(2026, 11, 24)),
      ]);
      expect(games.streakAt(today), 1);
    });

    test('une semaine sans releve ne compte pas et ne rompt rien', () {
      final games = ledger([
        week(DateTime(2026, 11, 9), 180),
        week(DateTime(2026, 11, 16), 180, complete: false),
        week(DateTime(2026, 11, 23), 180),
        week(monday, 0),
      ], sessions: [
        hour(DateTime(2026, 11, 17)),
        hour(DateTime(2026, 11, 24)),
      ]);
      expect(games.streakAt(today), 1 + 0);
    });
  });

  group('un changement de regles', () {
    final weeks = [week(DateTime(2026, 11, 23), 540), week(monday, 540)];

    test('ne vaut qu a partir du lundi suivant', () {
      final rules = const GameContractSettings()
          .edited(const GameContractSettings(gameHoursPerSportHour: 2), today);
      final games = ledger(weeks, settings: rules);

      expect(games.contractOf(today)!.targetMinutes, 180);
      expect(games.contractOf(DateTime(2026, 12, 7))!.targetMinutes, 270);
    });

    test('garde la regle en cours quand on modifie deux fois la meme semaine', () {
      final rules = const GameContractSettings()
          .edited(const GameContractSettings(gameHoursPerSportHour: 2), today)
          .edited(const GameContractSettings(gameHoursPerSportHour: 1), today);

      expect(rules.rulesFor(today).gameHoursPerSportHour, 3);
      expect(rules.rulesFor(DateTime(2026, 12, 7)).gameHoursPerSportHour, 1);
    });

    test('se relit avec son historique', () {
      final rules = const GameContractSettings()
          .edited(const GameContractSettings(bikeMinutesPerDay: 40), today);
      final copy = GameContractSettings.fromJson(rules.toJson());

      expect(copy.rulesFor(today).bikeMinutesPerDay, 60);
      expect(copy.rulesFor(DateTime(2026, 12, 7)).bikeMinutesPerDay, 40);
    });

    test('desactiver ne touche pas aux regles', () {
      final rules = const GameContractSettings()
          .edited(const GameContractSettings(enabled: false), today);
      expect(rules.enabled, isFalse);
      expect(rules.history, isEmpty);
    });
  });

  test('une page restee ouverte de dimanche a lundi garde sa serie', () {
    final games = ledger(
      [
        week(DateTime(2026, 11, 16), 180),
        week(DateTime(2026, 11, 23), 180),
        week(monday, 0),
      ],
      sessions: [
        SportSession(
          id: 'a',
          date: DateTime(2026, 11, 24),
          sportId: Sport.running,
          minutes: 60,
        ),
      ],
      now: DateTime(2026, 11, 29),
    );
    expect(games.streakAt(monday), 1);
  });

  test('une reponse sans structure de rapport est rejetee', () {
    expect(GamingReport.tryDecode('<html></html>'), isNull);
    expect(GamingReport.tryDecode('{}'), isNull);
    expect(GamingReport.tryDecode('{"sources": [], "weeks": []}'), isNotNull);
  });

  test('le releve se relit tel quel, et une reponse abimee vaut rien', () {
    final report = GamingReport(
      sources: const ['steam', 'lol'],
      errors: const {'lol': 'unauthorized'},
      notifyToken: 'jeton',
      weeks: [
        GameWeek(
          monday: monday,
          minutes: 90,
          complete: true,
          steamMinutes: 60,
          lolMinutes: 30,
          lolGames: 1,
          lolWins: 1,
          games: const [GameTitle(name: 'Un jeu', minutes: 60)],
        ),
      ],
    );
    final copy = GamingReport.decode(report.encode());

    expect(copy.sources, ['steam', 'lol']);
    expect(copy.errors, {'lol': 'unauthorized'});
    expect(copy.notifyToken, 'jeton');
    expect(copy.weekOf(today)?.games.single.name, 'Un jeu');
    expect(GamingReport.decode('pas du json').isConfigured, isFalse);
  });
}
