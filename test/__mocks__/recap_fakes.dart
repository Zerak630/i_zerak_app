import 'package:i_zerak_app/models/app_tab.dart';
import 'package:i_zerak_app/models/game_dao.dart';
import 'package:i_zerak_app/models/recap_dao.dart';
import 'package:i_zerak_app/models/settings_category.dart';
import 'package:i_zerak_app/services/recap/recap_service.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_app_preferences.dart';

/// Preferences en memoire.
class MemoryPreferences implements IAppPreferences {
  TabLayout tabs = TabLayout.initial;
  RecapSettings recap = const RecapSettings();
  GamingReport gaming = const GamingReport();
  GameContractSettings contract = const GameContractSettings();
  Set<SettingsCategory> expanded = {};

  @override
  Future<TabLayout> readTabs() async => tabs;

  @override
  Future<void> saveTabs(TabLayout layout) async => tabs = layout;

  @override
  Future<RecapSettings> readRecapSettings() async => recap;

  @override
  Future<void> saveRecapSettings(RecapSettings settings) async => recap = settings;

  @override
  Future<GamingReport> readGamingReport() async => gaming;

  @override
  Future<void> saveGamingReport(GamingReport report) async => gaming = report;

  @override
  Future<GameContractSettings> readGameContract() async => contract;

  @override
  Future<void> saveGameContract(GameContractSettings settings) async => contract = settings;

  @override
  Future<Set<SettingsCategory>> readExpandedSettings() async => {...expanded};

  @override
  Future<void> saveExpandedSettings(Set<SettingsCategory> value) async => expanded = {...value};
}

/// Un natif imaginaire : il garde ce qu'on lui transmet.
class FakeRecapBridge implements IRecapBridge {
  FakeRecapBridge({this.supported = true});

  bool supported;
  final List<Map<String, Object?>> configs = [];
  int notificationRequests = 0;

  @override
  bool get isSupported => supported;

  @override
  Future<void> configure(Map<String, Object?> config) async => configs.add(config);

  @override
  Future<bool> requestNotifications() async {
    notificationRequests++;
    return true;
  }
}
