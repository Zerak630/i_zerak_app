import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:i_zerak_app/models/subscription_dao.dart';
import 'package:i_zerak_app/services/repositories/hive/hive_subscription_repository.dart';
import 'package:i_zerak_app/services/repositories/hive/type_adapters.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_subscriptions.dart';

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

  getIt.registerLazySingleton<http.Client>(() => http.Client());

  getIt.registerSingleton<ISubscriptions>(
      HiveSubscriptionRepository(await Hive.openBox<Subscription>('subscriptions')));
}

/// Remet le conteneur a zero. Reserve aux tests.
Future<void> resetServiceLocator() => getIt.reset();
