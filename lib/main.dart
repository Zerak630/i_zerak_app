import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get_it/get_it.dart';
import 'package:hive/hive.dart';
import 'package:i_zerak_app/firebase_options.dart';
import 'package:i_zerak_app/homepage.dart';
import 'package:i_zerak_app/models/subscription_dao.dart';
import 'package:i_zerak_app/services/repositories/hive/subscription_adapter.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_subscriptions.dart';
import 'package:i_zerak_app/theme/darktheme_default.dart';
import 'package:permission_handler/permission_handler.dart';

// Initialisation de GetIt
final getIt = GetIt.instance;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Hive.init('i_zerak/test');

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Demander les permissions
  // await Permission.storage.request();
  await Permission.manageExternalStorage.request();

  getIt.registerSingleton<ISubscriptions>(
      SubscriptionAdapter(await Hive.openBox<Subscription>('subscriptions')));

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
