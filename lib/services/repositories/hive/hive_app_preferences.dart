import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:i_zerak_app/models/app_tab.dart';
import 'package:i_zerak_app/models/game_dao.dart' show GameContractSettings, GamingReport;
import 'package:i_zerak_app/models/recap_dao.dart' show RecapSettings;
import 'package:i_zerak_app/models/settings_category.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_app_preferences.dart';

/// Preferences d'affichage, dans une `Box<String>` de JSON.
///
/// Meme parti pris que les stations et les trajets : pas de `TypeAdapter`,
/// donc pas d'identifiant de type brule a vie pour une liste de six noms.
class HiveAppPreferences implements IAppPreferences {
  HiveAppPreferences(this._box);

  final Box<String> _box;

  static const String _tabsKey = 'pinned_tabs';
  static const String _recapKey = 'recap';
  static const String _gamingKey = 'gaming_report';
  static const String _contractKey = 'game_contract';
  static const String _expandedKey = 'settings_expanded';

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

  @override
  Future<RecapSettings> readRecapSettings() async {
    final raw = _box.get(_recapKey);
    if (raw == null) {
      return const RecapSettings();
    }
    try {
      return RecapSettings.fromJson(json.decode(raw));
    } on FormatException {
      return const RecapSettings();
    }
  }

  @override
  Future<void> saveRecapSettings(RecapSettings settings) async {
    await _box.put(_recapKey, json.encode(settings.toJson()));
    await _box.flush();
  }

  @override
  Future<GamingReport> readGamingReport() async {
    final raw = _box.get(_gamingKey);
    return raw == null ? const GamingReport() : GamingReport.decode(raw);
  }

  @override
  Future<void> saveGamingReport(GamingReport report) async {
    await _box.put(_gamingKey, report.encode());
    await _box.flush();
  }

  @override
  Future<GameContractSettings> readGameContract() async {
    final raw = _box.get(_contractKey);
    if (raw == null) {
      return const GameContractSettings();
    }
    try {
      return GameContractSettings.fromJson(json.decode(raw));
    } on FormatException {
      return const GameContractSettings();
    }
  }

  @override
  Future<void> saveGameContract(GameContractSettings settings) async {
    await _box.put(_contractKey, json.encode(settings.toJson()));
    await _box.flush();
  }

  @override
  Future<Set<SettingsCategory>> readExpandedSettings() async {
    final raw = _box.get(_expandedKey);
    if (raw == null) {
      return {};
    }
    try {
      final decoded = json.decode(raw);
      return decoded is List ? SettingsCategory.fromNames(decoded) : {};
    } on FormatException {
      // Au pire, tout se replie : rien de grave pour un ecran de reglages.
      return {};
    }
  }

  @override
  Future<void> saveExpandedSettings(Set<SettingsCategory> expanded) async {
    await _box.put(_expandedKey, json.encode(SettingsCategory.toNames(expanded)));
    await _box.flush();
  }
}
