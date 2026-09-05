import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:i_zerak_app/models/server_config_dao.dart';
import 'package:i_zerak_app/models/subscription_dao.dart';
import 'package:i_zerak_app/services/qbittorrent/qb_service.dart';
import 'package:i_zerak_app/services/repositories/hive/hive_server_config_repository.dart';
import 'package:i_zerak_app/services/repositories/hive/hive_subscription_repository.dart';
import 'package:i_zerak_app/services/repositories/hive/type_adapters.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_credentials.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_server_config.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_subscriptions.dart';
import 'package:i_zerak_app/services/repositories/secure/secure_credentials_store.dart';

final getIt = GetIt.instance;

/// Prepare le stockage local puis enregistre les dependances applicatives.
///
/// A appeler une seule fois, avant `runApp`. Les `TypeAdapter` doivent etre
/// enregistres avant toute ouverture de boite, sinon Hive ne sait pas
/// deserialiser son contenu.
Future<void> setupServiceLocator() async {
  await Hive.initFlutter();

  Hive.registerAdapter(SubscriptionTypeAdapter());
  Hive.registerAdapter(SubscriptionFrequencyTypeAdapter());
  Hive.registerAdapter(ServerConfigTypeAdapter());

  // Client generique, sans epinglage : reserve aux API publiques en HTTPS
  // (donnees carburants, TMDB). Les services du serveur auto-heberge
  // construisent le leur, adosse au certificat epingle.
  getIt.registerLazySingleton<http.Client>(() => http.Client());

  getIt.registerSingleton<ISubscriptions>(
      HiveSubscriptionRepository(await Hive.openBox<Subscription>('subscriptions')));

  getIt.registerSingleton<IServerConfig>(
      HiveServerConfigRepository(await Hive.openBox<ServerConfig>('server_config')));

  getIt.registerLazySingleton<ICredentials>(() => const SecureCredentialsStore());

  getIt.registerLazySingleton<QbService>(() => QbService(
        config: getIt<IServerConfig>(),
        credentials: getIt<ICredentials>(),
      ));
}

/// Remet le conteneur a zero. Reserve aux tests.
Future<void> resetServiceLocator() => getIt.reset();
