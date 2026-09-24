import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:i_zerak_app/models/app_tab.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_app_preferences.dart';

/// Preferences d'affichage, dans une `Box<String>` de JSON.
///
/// Meme parti pris que les stations et les trajets : pas de `TypeAdapter`,
/// donc pas d'identifiant de type brule a vie pour une liste de six noms.
class HiveAppPreferences implements IAppPreferences {
  HiveAppPreferences(this._box);

  final Box<String> _box;

  static const String _tabsKey = 'pinned_tabs';

  @override
  Future<TabLayout> readTabs() async {
    final raw = _box.get(_tabsKey);
    if (raw == null) {
      return TabLayout.initial;
    }
    try {
      final decoded = json.decode(raw);
      return decoded is List ? TabLayout.fromNames(decoded) : TabLayout.initial;
    } on FormatException {
      // Une preference abimee ne doit pas empecher l'application de s'ouvrir :
      // la barre reprend sa composition d'origine.
      return TabLayout.initial;
    }
  }

  @override
  Future<void> saveTabs(TabLayout layout) async {
    await _box.put(_tabsKey, json.encode(layout.toNames()));
    // Une boite Hive sert ses valeurs depuis un cache en memoire : sans ce
    // `flush`, le choix disparaitrait si Android tuait l'application juste
    // apres.
    await _box.flush();
  }
}
