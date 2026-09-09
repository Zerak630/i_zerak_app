import 'package:i_zerak_app/models/gas_station_dao.dart';

/// Depot des stations-service retenues en favori.
///
/// Il ne connait que l'identite d'une station, jamais son prix : celui-ci vient
/// du reseau a chaque affichage.
abstract class IGasStations {
  Future<List<SavedGasStation>> getAll();

  /// Ajoute la station, ou rafraichit son libelle si elle est deja retenue.
  Future<void> add(SavedGasStation station);

  Future<void> delete(int id);

  /// Donne a la station le nom choisi par l'utilisateur.
  ///
  /// `null` ou une chaine blanche efface ce nom et rend la station a son
  /// adresse : le jeu de donnees ne publie aucune enseigne, l'adresse est tout
  /// ce dont il dispose, et elle est parfois illisible.
  Future<void> rename(int id, String? name);

  /// Le carburant que l'utilisateur suit.
  ///
  /// Il vit ici, et non dans `ServerConfig`, pour deux raisons : c'est une
  /// preference de la page carburants, sans rapport avec le Pi ; et
  /// `ServerConfig` passe par un `TypeAdapter` ecrit a la main, ou tout champ
  /// ajoute doit etre reporte a la main sous peine de corrompre la relecture.
  Future<FuelType> readFuel();

  Future<void> saveFuel(FuelType fuel);
}
