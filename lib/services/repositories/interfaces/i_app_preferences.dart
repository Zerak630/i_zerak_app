import 'package:i_zerak_app/models/app_tab.dart';

/// Les preferences d'affichage de l'application, sans rapport avec un onglet
/// en particulier.
abstract class IAppPreferences {
  /// Les onglets epingles a la barre du bas. Renvoie la barre d'origine tant
  /// que rien n'a ete choisi.
  Future<TabLayout> readTabs();

  Future<void> saveTabs(TabLayout layout);
}
