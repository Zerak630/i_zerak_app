import 'package:flutter/foundation.dart';
import 'package:i_zerak_app/models/game_dao.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_app_preferences.dart';

/// Lit le temps de jeu sur le Pi, et garde le dernier releve.
///
/// Le Pi n'est pas toujours joignable, depuis l'exterieur notamment : les
/// ecrans et le bilan travaillent sur la copie locale.
class GamingService {
  GamingService({required this.fetch, required this.preferences, this.origin});

  /// La lecture sur l'agent (cf. `AgentService.gaming`).
  final Future<GamingReport> Function() fetch;
  final IAppPreferences preferences;

  /// L'adresse de l'agent configure : une copie venue d'un autre serveur ne
  /// vaut plus, et son jeton ne doit pas lui etre presente.
  final Future<String?> Function()? origin;

  /// Change a chaque nouveau releve, pour les ecrans deja ouverts.
  final ValueNotifier<int> revision = ValueNotifier(0);

  Future<String?> _currentOrigin() async {
    try {
      return await origin?.call();
    } on Exception catch (error) {
      // Un hote mal saisi : on ne sait pas dire si le serveur a change.
      debugPrint('Adresse de l\'agent illisible : $error');
      return null;
    }
  }

  Future<GamingReport> read() async {
    final report = await preferences.readGamingReport();
    final current = await _currentOrigin();
    if (report.origin != null && current != null && report.origin != current) {
      return const GamingReport();
    }
    return report;
  }

  /// Vrai si un nouveau releve a ete recu.
  Future<bool> refresh() async {
    try {
      final report = await fetch();
      await preferences.saveGamingReport(report.withOrigin(await _currentOrigin()));
      revision.value++;
      return true;
    } on Exception catch (error) {
      // Agent injoignable ou trop ancien : la copie locale reste valable.
      debugPrint('Temps de jeu non actualise : $error');
      return false;
    }
  }

  Future<GameContractSettings> readSettings() => preferences.readGameContract();

  Future<void> saveSettings(GameContractSettings settings) =>
      preferences.saveGameContract(settings);
}
