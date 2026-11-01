import 'package:i_zerak_app/models/commute_dao.dart' show Goal, dateOnly, dayKey;
import 'package:i_zerak_app/models/screen_time_dao.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_screen_time.dart';
import 'package:i_zerak_app/services/screen_time/usage_source.dart';

/// Depot du temps libre en memoire : le comportement Hive est verifie a part.
class MemoryScreenTime implements IScreenTime {
  MemoryScreenTime({ScreenTimeSettings? settings, List<ScreenTimeDay>? days})
      : settings = settings ?? const ScreenTimeSettings(),
        days = {for (final day in days ?? const <ScreenTimeDay>[]) dayKey(day.date): day};

  ScreenTimeSettings settings;
  final Map<String, ScreenTimeDay> days;
  final Map<String, Goal> goals = {};

  @override
  Future<ScreenTimeSettings> readSettings() async => settings;

  @override
  Future<void> saveSettings(ScreenTimeSettings settings) async => this.settings = settings;

  @override
  Future<List<ScreenTimeDay>> getDays() async => [...days.values];

  @override
  Future<void> saveDay(ScreenTimeDay day) async => days[dayKey(day.date)] = day;

  @override
  Future<List<Goal>> getGoals() async => [...goals.values];

  @override
  Future<void> saveGoal(Goal goal) async => goals[goal.id] = goal;

  @override
  Future<void> deleteGoal(String id) async => goals.remove(id);
}

/// Un Android imaginaire : des sessions, et les jours dont il garde la trace.
class FakeUsageSource implements IUsageSource {
  FakeUsageSource({
    this.access = true,
    this.supported = true,
    List<UsageSession>? recorded,
    Set<DateTime>? recordedDays,
    this.apps = const [],
  })  : recorded = recorded ?? [],
        recordedDays = recordedDays ?? {};

  bool access;
  bool supported;
  /// Tout ce qu'Android a vu, toutes applications confondues.
  final List<UsageSession> recorded;

  /// Les jours pour lesquels Android repond quelque chose.
  final Set<DateTime> recordedDays;

  final List<TrackedApp> apps;

  /// Chaque configuration du bilan, dans l'ordre.
  final List<Map<String, Object?>?> reports = [];

  /// Chaque fenetre demandee, pour verifier ce qui est relu.
  final List<DateTime> queried = [];

  int notificationRequests = 0;
  int accessSettingsOpened = 0;

  @override
  bool get isSupported => supported;

  @override
  Future<bool> hasAccess() async => access;

  @override
  Future<void> openAccessSettings() async => accessSettingsOpened++;

  @override
  Future<UsageWindow> sessions(DateTime from, DateTime to, Set<String> packages) async {
    queried.add(from);
    return UsageWindow(
      sessions: [
        for (final s in recorded)
          if (packages.contains(s.package) && s.end.isAfter(from) && s.start.isBefore(to)) s,
      ],
      hasData: recordedDays.contains(dateOnly(from)),
    );
  }

  @override
  Future<List<TrackedApp>> launchableApps() async => apps;

  @override
  Future<void> configureReport(Map<String, Object?>? config) async => reports.add(config);

  @override
  Future<bool> requestNotifications() async {
    notificationRequests++;
    return true;
  }
}
