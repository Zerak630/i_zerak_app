import 'package:i_zerak_app/models/sport_dao.dart';

/// Depot de l'onglet Sport.
///
/// Il ne stocke que des faits : les sports ajoutes ou renommes, le programme
/// de la semaine et les seances saisies. Totaux, semaines et series se
/// recalculent (cf. `SportLedger`).
abstract class ISport {
  /// Les sports livres, remplaces par leur version enregistree s'ils ont ete
  /// renommes, puis ceux ajoutes a la main.
  Future<List<Sport>> getSports();

  /// Ajoute le sport, ou remplace celui qui porte le meme identifiant.
  Future<void> saveSport(Sport sport);

  Future<List<PlannedSlot>> getPlan();

  Future<void> saveSlot(PlannedSlot slot);

  Future<void> deleteSlot(String id);

  Future<List<SportSession>> getSessions();

  /// Ajoute la seance, ou remplace celle qui porte le meme identifiant.
  Future<void> saveSession(SportSession session);

  Future<void> deleteSession(String id);
}

/// Les sports livres, puis ceux enregistres : un sport livre renomme prend sa
/// place, un sport ajoute vient a la suite.
List<Sport> mergeSports(Iterable<Sport> stored) {
  final byId = {for (final sport in stored) sport.id: sport};
  return [
    for (final sport in Sport.defaults) byId.remove(sport.id) ?? sport,
    ...byId.values,
  ];
}
