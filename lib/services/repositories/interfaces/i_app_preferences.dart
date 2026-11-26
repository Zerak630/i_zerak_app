import 'package:i_zerak_app/models/app_tab.dart';
import 'package:i_zerak_app/models/game_dao.dart' show GameContractSettings, GamingReport;
import 'package:i_zerak_app/models/recap_dao.dart' show RecapSettings;
import 'package:i_zerak_app/models/settings_category.dart';

/// Les preferences d'affichage de l'application, sans rapport avec un onglet
/// en particulier.
abstract class IAppPreferences {
  /// Les onglets epingles a la barre du bas. Renvoie la barre d'origine tant
  /// que rien n'a ete choisi.
  Future<TabLayout> readTabs();

  Future<void> saveTabs(TabLayout layout);

  /// Les notifications de bilan. Propres a l'appareil : elles ne se
  /// synchronisent pas, comme la barre du bas.
  Future<RecapSettings> readRecapSettings();

  Future<void> saveRecapSettings(RecapSettings settings);

  /// Le dernier releve du temps de jeu recu du Pi.
  Future<GamingReport> readGamingReport();

  Future<void> saveGamingReport(GamingReport report);

  /// Les regles du contrat jeu contre sport.
  Future<GameContractSettings> readGameContract();

  Future<void> saveGameContract(GameContractSettings settings);

  /// Les categories des Reglages laissees depliees. Vide tant que rien n'a
  /// ete ouvert : l'ecran s'ouvre alors comme un sommaire. Propre a
  /// l'appareil, comme la barre du bas.
  Future<Set<SettingsCategory>> readExpandedSettings();

  Future<void> saveExpandedSettings(Set<SettingsCategory> expanded);
}
