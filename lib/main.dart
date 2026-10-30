import 'dart:async';

import 'package:flutter/material.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:i_zerak_app/homepage.dart';
import 'package:i_zerak_app/services/service_locator.dart';
import 'package:i_zerak_app/services/sync/sync_service.dart';
import 'package:i_zerak_app/theme/darktheme_default.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await setupServiceLocator();

  // Sans attendre : le dossier peut etre lent ou absent, et le premier ecran
  // n'a pas a patienter. Les pages se rechargent quand l'import aboutit.
  unawaited(getIt<SyncService>().start());

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
        home: HomePage());
  }
}
