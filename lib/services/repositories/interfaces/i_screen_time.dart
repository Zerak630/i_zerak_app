import 'package:i_zerak_app/models/commute_dao.dart' show Goal;
import 'package:i_zerak_app/models/screen_time_dao.dart';

/// Depot de l'onglet Temps libre.
///
/// Comme pour le velo, il ne stocke que des faits : les reglages, les
/// journees terminees et les objectifs. La cagnotte se recalcule (cf.
/// `ScreenTimeLedger`), et la journee en cours n'est jamais ecrite : elle se
/// remesure a chaque ouverture.
abstract class IScreenTime {
  Future<ScreenTimeSettings> readSettings();

  Future<void> saveSettings(ScreenTimeSettings settings);

  Future<List<ScreenTimeDay>> getDays();

  /// Une seule journee par date : enregistrer de nouveau la remplace.
  Future<void> saveDay(ScreenTimeDay day);

  Future<List<Goal>> getGoals();

  /// Ajoute l'objectif, ou le remplace s'il existe deja.
  Future<void> saveGoal(Goal goal);

  Future<void> deleteGoal(String id);
}
