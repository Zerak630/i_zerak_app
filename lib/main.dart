import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:i_zerak_app/firebase_options.dart';
import 'package:i_zerak_app/homepage.dart';
import 'package:i_zerak_app/models/subscription_dao.dart';
import 'package:i_zerak_app/services/repositories/hive/hive_subscription_repository.dart';
import 'package:i_zerak_app/services/repositories/hive/type_adapters.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_subscriptions.dart';
import 'package:i_zerak_app/theme/darktheme_default.dart';

// Initialisation de GetIt
final getIt = GetIt.instance;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // `initFlutter` resout le repertoire de documents de l'application via
  // path_provider. L'ancien `Hive.init('i_zerak/test')` utilisait un chemin
  // relatif, invalide sur mobile, ce qui rendait toute persistance impossible
  // et avait motive une demande de permission de stockage externe injustifiee.
  await Hive.initFlutter();

  // Les adaptateurs doivent etre enregistres avant toute ouverture de boite.
  Hive.registerAdapter(SubscriptionTypeAdapter());
  Hive.registerAdapter(SubscriptionFrequencyTypeAdapter());

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  getIt.registerSingleton<ISubscriptions>(
      HiveSubscriptionRepository(await Hive.openBox<Subscription>('subscriptions')));

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: 'iZerak',
        theme: CustomThemes.brightDefault,
        darkTheme: CustomThemes.darkDefault,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const HomePage());
  }
}
