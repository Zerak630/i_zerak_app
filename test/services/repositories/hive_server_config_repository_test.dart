/// La configuration doit survivre a la fermeture de l'application.
///
/// Une boite Hive sert ses valeurs depuis un cache en memoire : tant que le
/// fichier n'est pas ecrit, l'application se comporte normalement et ne
/// decouvre la perte qu'au demarrage suivant. Ces tests fermeraient les yeux
/// s'ils se contentaient de relire la meme boite : ils verifient le fichier,
/// puis rouvrent depuis le disque.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:i_zerak_app/models/server_config_dao.dart';
import 'package:i_zerak_app/services/repositories/hive/hive_server_config_repository.dart';
import 'package:i_zerak_app/services/repositories/hive/type_adapters.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('izerak_hive_test');
    Hive.init(directory.path);
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(ServerConfigTypeAdapter());
    }
  });

  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  ServerConfig sample() => ServerConfig(
        host: '192.168.1.110',
        port: 8085,
        agentPort: 8081,
        username: 'admin',
        pollIntervalSeconds: 5,
        defaultSavePath: '/srv/nas1/Emby',
        pinnedCertSha256: '6ada632361e66fcb6014144bf0a3951124495b5d44f439ace69e5977f6d8e29f',
      );

  test('l enregistrement atteint le fichier, pas seulement le cache', () async {
    final box = await Hive.openBox<ServerConfig>('server_config');
    await HiveServerConfigRepository(box).save(sample());

    final file = File('${directory.path}/server_config.hive');
    expect(file.existsSync(), isTrue);
    // Le defaut d'origine : le fichier restait a zero octet et toute la
    // configuration disparaissait au redemarrage.
    expect(await file.length(), greaterThan(0));
  });

  test('la configuration est relue a l identique apres reouverture', () async {
    final box = await Hive.openBox<ServerConfig>('server_config');
    await HiveServerConfigRepository(box).save(sample());
    await box.close();

    final reopened = await Hive.openBox<ServerConfig>('server_config');
    final read = await HiveServerConfigRepository(reopened).read();

    expect(read, isNotNull);
    expect(read!.host, '192.168.1.110');
    expect(read.port, 8085);
    expect(read.agentPort, 8081);
    expect(read.username, 'admin');
    expect(read.pollIntervalSeconds, 5);
    // Les champs 5, 7 et 8 entourent le champ 6, retire avec `defaultCategory`.
    // C'est exactement la que se verrait un compteur `writeByte` mal ajuste :
    // l'adaptateur est ecrit a la main, et l'erreur ne leve aucune exception,
    // elle decale silencieusement la relecture.
    expect(read.defaultSavePath, '/srv/nas1/Emby');
    // L'empreinte epinglee compte autant que le reste : sans elle, la
    // connexion HTTPS redemande une approbation a chaque lancement.
    expect(read.pinnedCertSha256,
        '6ada632361e66fcb6014144bf0a3951124495b5d44f439ace69e5977f6d8e29f');
    expect(read.agentPort, 8081);
  });

  test('un enregistrement remplace le precedent', () async {
    final box = await Hive.openBox<ServerConfig>('server_config');
    final repository = HiveServerConfigRepository(box);
    await repository.save(sample());
    await repository.save(sample().copyWith(host: 'raspberrypi.local', port: 9090));
    await box.close();

    final reopened = await Hive.openBox<ServerConfig>('server_config');
    final read = await HiveServerConfigRepository(reopened).read();

    expect(read!.host, 'raspberrypi.local');
    expect(read.port, 9090);
    expect(reopened.length, 1);
  });
}
