/// Les categories de l'ecran Reglages, dans l'ordre ou il les presente.
///
/// Dart pur, comme les onglets : l'ecran les affiche, les preferences
/// retiennent lesquelles sont depliees, par leur nom.
library;

enum SettingsCategory {
  /// Distance, consommation, carburant, et ce que le velo rembourse.
  commute,

  /// Applications suivies et quota.
  freeTime,

  /// Le contrat jeu contre sport.
  games,

  /// Tout ce qui notifie : rappels du soir, bilan du Temps libre, bilans.
  notifications,

  /// Le Pi et les services qui y tournent.
  server,

  /// Le dossier partage avec les autres appareils.
  sync,

  /// La barre du bas.
  display;

  static SettingsCategory? fromName(String? raw) {
    for (final category in values) {
      if (category.name == raw) {
        return category;
      }
    }
    return null;
  }

  /// Relecture tolerante : un nom inconnu — une categorie disparue depuis —
  /// est ignore plutot que de tout replier.
  static Set<SettingsCategory> fromNames(Iterable<Object?> raw) => {
        for (final name in raw)
          if (fromName(name is String ? name : null) case final SettingsCategory category) category,
      };

  static List<String> toNames(Set<SettingsCategory> categories) =>
      [for (final category in values) if (categories.contains(category)) category.name];
}
