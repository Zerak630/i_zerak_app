import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:i_zerak_app/services/agent/agent_service.dart';
import 'package:i_zerak_app/models/server_config_dao.dart';
import 'package:i_zerak_app/models/subscription_dao.dart';
import 'package:i_zerak_app/services/commute_price_service.dart';
import 'package:i_zerak_app/services/gas_service.dart';
import 'package:i_zerak_app/services/qbittorrent/qb_service.dart';
import 'package:i_zerak_app/services/repositories/hive/hive_commute_repository.dart';
import 'package:i_zerak_app/services/repositories/hive/hive_gas_station_repository.dart';
import 'package:i_zerak_app/services/repositories/hive/hive_server_config_repository.dart';
import 'package:i_zerak_app/services/repositories/hive/hive_subscription_repository.dart';
import 'package:i_zerak_app/services/repositories/hive/type_adapters.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_commute.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_credentials.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_gas_stations.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_server_config.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_subscriptions.dart';
import 'package:i_zerak_app/services/repositories/secure/secure_credentials_store.dart';
import 'package:i_zerak_app/services/tmdb/tmdb_service.dart';

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

  // Deux boites : les abonnements typees, et une boite de chaines JSON pour les
  // categories ajoutees a la main (cf. HiveSubscriptionRepository).
  getIt.registerSingleton<ISubscriptions>(HiveSubscriptionRepository(
    await Hive.openBox<Subscription>('subscriptions'),
    await Hive.openBox<String>('subscription_prefs'),
  ));

  getIt.registerSingleton<IServerConfig>(
      HiveServerConfigRepository(await Hive.openBox<ServerConfig>('server_config')));

  // Boite de chaines primitives, sans TypeAdapter : les stations favorites ne
  // sont qu'un identifiant et un libelle (cf. HiveGasStationRepository).
  final gasStations = HiveGasStationRepository(await Hive.openBox<String>('gas_stations'));
  await gasStations.seedLegacyStationsIfEmpty();
  getIt.registerSingleton<IGasStations>(gasStations);

  // Meme principe que les stations : des chaines JSON, sans TypeAdapter
  // (cf. HiveCommuteRepository).
  getIt.registerSingleton<ICommute>(
      HiveCommuteRepository(await Hive.openBox<String>('commute')));

  getIt.registerLazySingleton<CommutePriceService>(() => CommutePriceService(
        gas: GasService(client: getIt<http.Client>()),
        favorites: getIt<IGasStations>(),
        store: getIt<ICommute>(),
      ));

  getIt.registerLazySingleton<ICredentials>(() => const SecureCredentialsStore());

  getIt.registerLazySingleton<QbService>(() => QbService(
        config: getIt<IServerConfig>(),
        credentials: getIt<ICredentials>(),
      ));

  getIt.registerLazySingleton<AgentService>(() => AgentService(
        config: getIt<IServerConfig>(),
        credentials: getIt<ICredentials>(),
      ));

  // TMDB est une API publique en HTTPS : elle utilise le client generique, pas
  // le client epingle sur le certificat du serveur auto-heberge.
  getIt.registerLazySingleton<TmdbService>(() => TmdbService(
        credentials: getIt<ICredentials>(),
        client: getIt<http.Client>(),
      ));
}

/// Remet le conteneur a zero. Reserve aux tests.
Future<void> resetServiceLocator() => getIt.reset();
