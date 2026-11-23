import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:i_zerak_app/models/commute_dao.dart';
import 'package:i_zerak_app/models/game_dao.dart';
import 'package:i_zerak_app/models/server_config_dao.dart';
import 'package:i_zerak_app/models/sport_dao.dart';
import 'package:i_zerak_app/services/gaming/gaming_service.dart';
import 'package:i_zerak_app/services/recap/recap_service.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_server_config.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../../__mocks__/commute_fakes.dart';
import '../../__mocks__/recap_fakes.dart';
import '../../__mocks__/sport_fakes.dart';
import '../../__mocks__/subscription_fakes.dart';

class _Server implements IServerConfig {
  _Server(this.config);

  final ServerConfig? config;

  @override
  Future<ServerConfig?> read() async => config;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  // Dimanche 29 novembre 2026, 18 h.
  final now = DateTime(2026, 11, 29, 18);
  late MemoryPreferences preferences;
  late FakeRecapBridge bridge;

  setUpAll(() => initializeDateFormatting('fr'));

  setUp(() {
    preferences = MemoryPreferences()
      ..gaming = GamingReport(
        sources: const ['steam', 'lol'],
        notifyToken: 'jeton-limite',
        weeks: [
          GameWeek(monday: DateTime(2026, 11, 16), minutes: 760, complete: true),
          GameWeek(
            monday: DateTime(2026, 11, 23),
            minutes: 630,
            complete: false,
            steamMinutes: 240,
            lolMinutes: 390,
            lolGames: 12,
          ),
        ],
      );
    bridge = FakeRecapBridge();
  });

  RecapService service({ServerConfig? server}) => RecapService(
        commute: MemoryCommute(
          settings: const CommuteSettings(distanceKm: 12.4),
          days: [
            for (final day in [23, 24, 25])
              CommuteDay(
                date: DateTime(2026, 11, day),
                mode: CommuteMode.bike,
                amount: 2,
                pricePerLitre: 1.7,
                priceSource: PriceSource.live,
              ),
          ],
        ),
        subscriptions: MemorySubscriptions(),
        sport: MemorySport(sessions: [
          SportSession(id: 'a', date: DateTime(2026, 11, 26), sportId: Sport.yoga, minutes: 45),
        ]),
        preferences: preferences,
        games: GamingService(fetch: () async => preferences.gaming, preferences: preferences),
        server: _Server(server),
        bridge: bridge,
        clock: () => now,
        locale: () => const Locale('fr', 'FR'),
      );

  Future<Map> weekEntry({ServerConfig? server}) async {
    await service(server: server).push();
    return (bridge.configs.single['entries']! as List).cast<Map>().first;
  }

  test('le bilan dit le jeu, et le contrat compte le velo', () async {
    final text = (await weekEntry())['text'] as String;

    expect(text, contains('10 h 30 de jeu au dernier relevé'));
    expect(text, contains('LoL 12 parties'));
    expect(text, contains('Steam 4 h 00'));
    // 760 min de jeu : 4 h 15 a faire. 3 jours a velo et 45 min de yoga.
    expect(text, contains('Contrat en cours : 3 h 45 sur 4 h 15'));
    expect(text, isNot(contains('La semaine prochaine')), reason: 'total encore partiel');
  });

  test('le natif recoit de quoi relever le total, en HTTPS epingle seulement', () async {
    final live = (await weekEntry(
      server: ServerConfig(host: 'pi.local', pinnedCertSha256: 'AB:CD'),
    ))['live'] as Map;

    expect(live['url'], 'https://pi.local:8081/api/v1/gaming/week?monday=2026-11-23');
    expect((live['token'], live['pin'], live['ratio'], live['cap']), ('jeton-limite', 'abcd', 3, 360));
    expect(live['template'], contains('{played} de jeu'));
    expect(live['template'], contains('Pour l’instant, la semaine prochaine : {next} de sport'));
  });

  test('un hote mal saisi ne prive pas le bilan de sa notification', () async {
    final entry = await weekEntry(
      server: ServerConfig(host: 'pi.local:8081', pinnedCertSha256: 'AB:CD'),
    );
    expect(entry['text'], contains('de sport'));
    expect(entry.containsKey('live'), isFalse);
  });

  test('une semaine sans releve ne se dit pas a 0 h', () async {
    preferences.gaming = GamingReport(
      sources: const ['steam'],
      weeks: [GameWeek(monday: DateTime(2026, 11, 23), minutes: 0, complete: false)],
    );
    final text = (await weekEntry())['text'] as String;
    expect(text, isNot(contains('de jeu')));
    expect(text, isNot(contains('Pas de jeu')));
  });

  test('un releve recu est transmis aussitot au natif', () async {
    expect(await service().refreshGames(), isTrue);
    expect(bridge.configs, hasLength(1));
  });

  test('une copie venue d un autre serveur ne vaut plus', () async {
    preferences.gaming = preferences.gaming.withOrigin('https://ancien:8081');
    final games = GamingService(
      fetch: () async => const GamingReport(),
      preferences: preferences,
      origin: () async => 'https://nouveau:8081',
    );
    expect((await games.read()).isConfigured, isFalse);
  });

  test('un echec de lecture garde la copie locale', () async {
    final games = GamingService(
      fetch: () async => throw const FormatException('reponse illisible'),
      preferences: preferences,
    );
    expect(await games.refresh(), isFalse);
    expect((await games.read()).isConfigured, isTrue);
  });

  test('sans certificat epingle, le jeton ne part pas', () async {
    final entry = await weekEntry(server: ServerConfig(host: 'pi.local', useHttps: false));
    expect(entry.containsKey('live'), isFalse);
  });
}
