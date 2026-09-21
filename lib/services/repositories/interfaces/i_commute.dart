import 'package:i_zerak_app/models/commute_dao.dart';
import 'package:i_zerak_app/models/gas_station_dao.dart';

/// Un prix du litre tel qu'il a ete releve un jour donne.
typedef PriceObservation = ({DateTime day, double price, String? station});

/// Depot des trajets domicile-travail.
///
/// Il ne stocke que des faits : les reglages, les journees enregistrees, les
/// objectifs et les prix releves. La cagnotte n'y figure pas, elle se
/// recalcule (cf. `CommuteLedger`).
abstract class ICommute {
  Future<CommuteSettings> readSettings();

  Future<void> saveSettings(CommuteSettings settings);

  Future<List<CommuteDay>> getDays();

  /// Une seule journee par date : enregistrer de nouveau la remplace.
  Future<void> saveDay(CommuteDay day);

  Future<void> deleteDay(DateTime date);

  Future<List<Goal>> getGoals();

  /// Ajoute l'objectif, ou le remplace s'il existe deja.
  Future<void> saveGoal(Goal goal);

  Future<void> deleteGoal(String id);

  /// Retient le prix le plus bas vu ce jour-la pour ce carburant.
  ///
  /// C'est ce releve qui sert quand les stations ne repondent plus, et pour
  /// rattraper un jour oublie : l'API ne publie que les prix de l'instant.
  Future<void> recordPrice(FuelType fuel, DateTime day, double price, String? station);

  /// Le releve le plus recent pour ce carburant, au plus tard `onOrBefore`
  /// quand il est donne.
  Future<PriceObservation?> latestPrice(FuelType fuel, {DateTime? onOrBefore});
}
