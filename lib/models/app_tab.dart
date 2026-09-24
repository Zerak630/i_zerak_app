/// Les onglets de l'application, et ceux que la barre du bas affiche.
///
/// Dart pur : la regle des trois epingles se teste sans widgets.
library;

enum AppTab {
  home,
  subscriptions,
  torrents,
  system,
  gas,
  commute;

  static AppTab? fromName(String? raw) {
    for (final tab in values) {
      if (tab.name == raw) {
        return tab;
      }
    }
    return null;
  }
}

/// Ce que la barre du bas montre en permanence.
///
/// Six onglets ne tiennent pas cote a cote sans devenir illisibles. Trois sont
/// epingles, le reste se range derriere « Plus » — et c'est l'utilisateur qui
/// decide lesquels.
class TabLayout {
  const TabLayout(this.pinned);

  /// Dans l'ordre ou ils apparaissent, de gauche a droite.
  final List<AppTab> pinned;

  /// Trois, plus le bouton « Plus » : quatre icones, la limite au-dela de
  /// laquelle la barre se serre.
  static const int maxPinned = 3;

  /// Les trois onglets du premier lancement : la vue d'ensemble, l'argent, et
  /// la saisie quotidienne.
  static const TabLayout initial = TabLayout([AppTab.home, AppTab.subscriptions, AppTab.commute]);

  bool isPinned(AppTab tab) => pinned.contains(tab);

  bool get canPinMore => pinned.length < maxPinned;

  /// Les onglets ranges dans le menu, dans l'ordre de l'enumeration.
  List<AppTab> get others => [
        for (final tab in AppTab.values)
          if (!isPinned(tab)) tab,
      ];

  /// Epingle [tab]. Sans effet si la barre est pleine : c'est au menu de
  /// signaler qu'il faut d'abord en retirer un, plutot que d'en chasser un
  /// dans le dos de l'utilisateur.
  TabLayout pin(AppTab tab) =>
      isPinned(tab) || !canPinMore ? this : TabLayout([...pinned, tab]);

  /// Retire [tab] de la barre. Le dernier epingle ne part pas : une barre
  /// reduite au seul bouton « Plus » n'aurait plus rien a montrer.
  TabLayout unpin(AppTab tab) => !isPinned(tab) || pinned.length <= 1
      ? this
      : TabLayout([
          for (final pin in pinned)
            if (pin != tab) pin,
        ]);

  /// Relecture tolerante : un nom inconnu — un onglet supprime depuis — est
  /// ignore, et une liste vide ou trop longue retombe sur la barre d'origine.
  static TabLayout fromNames(Iterable<Object?> raw) {
    final tabs = <AppTab>[];
    for (final name in raw) {
      final tab = AppTab.fromName(name is String ? name : null);
      if (tab != null && !tabs.contains(tab) && tabs.length < maxPinned) {
        tabs.add(tab);
      }
    }
    return tabs.isEmpty ? initial : TabLayout(tabs);
  }

  List<String> toNames() => [for (final tab in pinned) tab.name];
}
