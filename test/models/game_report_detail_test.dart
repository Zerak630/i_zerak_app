import 'dart:convert';

import 'package:i_zerak_app/models/game_dao.dart';
import 'package:test/test.dart';

/// Ce que l'agent publie depuis l'ecran de statistiques.
const _agentReport = {
  'sources': ['steam', 'lol'],
  'updated_at': 1795600000,
  'errors': {},
  'lol_rank': {'tier': 'GOLD', 'division': 'II', 'lp': 54, 'wins': 30, 'losses': 25, 'at': 1},
  'weeks': [
    {
      'monday': '2026-11-23',
      'minutes': 460,
      'complete': false,
      'steam_minutes': 290,
      'lol_minutes': 170,
      'lol_games': 7,
      'lol_wins': 4,
      'lp_change': 38,
      'games': [
        {
          'appid': '1145350',
          'name': 'Hades II',
          'minutes': 160,
          'lifetime_minutes': 3480,
          'icon': 'https://media.steampowered.com/steamcommunity/public/images/apps/1145350/abc.jpg',
        },
        {'name': 'Factorio', 'minutes': 90, 'icon': 'https://evil.example.com/x.jpg'},
      ],
      'days': [
        {'day': '2026-11-23', 'steam_minutes': 0, 'lol_minutes': 27, 'measured': ['steam', 'lol']},
        {'day': '2026-11-24', 'steam_minutes': 20, 'lol_minutes': 0, 'measured': []},
      ],
      'matches': [
        {
          'start': 1795500000,
          'minutes': 31,
          'win': true,
          'champion': 'Ahri',
          'kills': 8,
          'deaths': 2,
          'assists': 9,
          'queue': 420,
          'portrait': 'https://ddragon.leagueoflegends.com/cdn/15.23.1/img/champion/Ahri.png',
        },
        {'minutes': 29, 'win': false, 'champion': 'Jinx', 'queue': 450, 'portrait': 'http://ddragon.leagueoflegends.com/x.png'},
      ],
    },
  ],
};

void main() {
  test('le detail de la semaine se decode', () {
    final report = GamingReport.tryDecode(json.encode(_agentReport))!;
    final week = report.weeks.single;

    expect(week.games.first.appId, '1145350');
    expect(week.games.first.lifetimeMinutes, 3480);
    expect(week.days.map((day) => day.minutes), [27, 20]);
    expect(week.days.last.measured, isEmpty);
    expect(week.lpChange, 38);

    final ahri = week.matches.first;
    expect(ahri.queue, LolQueue.ranked);
    expect(ahri.isSoloRanked, isTrue);
    expect(ahri.hasKda, isTrue);
    expect(ahri.start, DateTime.fromMillisecondsSinceEpoch(1795500000 * 1000));
    expect(week.matches.last.queue, LolQueue.aram);
    expect(week.matches.last.hasKda, isFalse);

    // Sept parties comptees, deux en detail : l'ecran le dit.
    expect(week.matchesWithoutDetail, 5);

    expect(report.lolRank!.tier, 'GOLD');
    expect(report.lolRank!.isRanked, isTrue);
    expect(report.lolRank!.hasDivision, isTrue);
  });

  test('une image hors des CDN attendus, ou en clair, est ignoree', () {
    final week = GamingReport.tryDecode(json.encode(_agentReport))!.weeks.single;
    expect(week.games.first.icon, startsWith('https://media.steampowered.com/'));
    expect(week.games.last.icon, isNull);
    expect(week.matches.first.portrait, startsWith('https://ddragon.leagueoflegends.com/'));
    expect(week.matches.last.portrait, isNull);
  });

  test('la copie locale garde tout le detail', () {
    final report = GamingReport.tryDecode(json.encode(_agentReport))!.withOrigin('https://pi:8081');
    final copy = GamingReport.decode(report.encode());
    final week = copy.weeks.single;

    expect(copy.origin, 'https://pi:8081');
    expect(copy.lolRank!.lp, 54);
    expect(week.games.first.icon, report.weeks.single.games.first.icon);
    expect(week.days.length, 2);
    expect(week.matches.first.champion, 'Ahri');
    expect(week.matches.first.kills, 8);
    expect(week.lpChange, 38);
  });

  test('un rapport d\'un agent plus ancien reste lisible', () {
    final report = GamingReport.tryDecode(json.encode({
      'sources': ['steam'],
      'weeks': [
        {
          'monday': '2026-11-23',
          'minutes': 60,
          'complete': true,
          'games': [
            {'name': 'Balatro', 'minutes': 60},
          ],
        },
      ],
    }))!;
    final week = report.weeks.single;
    expect(week.days, isEmpty);
    expect(week.matches, isEmpty);
    expect(week.lpChange, isNull);
    expect(week.games.single.icon, isNull);
    expect(report.lolRank, isNull);
  });

  test('un joueur non classe se distingue d\'un rang inconnu', () {
    final report = GamingReport.tryDecode(json.encode({
      'sources': ['lol'],
      'weeks': [],
      'lol_rank': {'tier': null},
    }))!;
    expect(report.lolRank, isNotNull);
    expect(report.lolRank!.isRanked, isFalse);
  });

  test('les files se regroupent comme sur l\'ecran', () {
    expect(LolQueue.of(440), LolQueue.ranked);
    expect(LolQueue.of(490), LolQueue.normal);
    expect(LolQueue.of(1700), LolQueue.arena);
    expect(LolQueue.of(null), LolQueue.other);
    expect(LolQueue.of(9999), LolQueue.other);
    expect(const LolRank(tier: 'MASTER').hasDivision, isFalse);
  });
}
