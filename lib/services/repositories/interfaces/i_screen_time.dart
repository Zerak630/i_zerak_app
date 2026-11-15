import 'package:i_zerak_app/models/screen_time_dao.dart';

/// Depot de l'onglet Temps libre.
///
/// Comme pour le velo, il ne stocke que des faits : les reglages et les
/// journees terminees. Le temps repris se recalcule (cf. `ScreenTimeLedger`),
/// et la journee en cours n'est jamais ecrite : elle se remesure a chaque
/// ouverture.
abstract class IScreenTime {
  Future<ScreenTimeSettings> readSettings();

  Future<void> saveSettings(ScreenTimeSettings settings);

  Future<List<ScreenTimeDay>> getDays();

  /// Une seule journee par date : enregistrer de nouveau la remplace.
  Future<void> saveDay(ScreenTimeDay day);
}
