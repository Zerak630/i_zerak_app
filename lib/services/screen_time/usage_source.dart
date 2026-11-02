import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:i_zerak_app/models/screen_time_dao.dart';

/// Ce qu'Android a vu entre deux instants.
class UsageWindow {
  const UsageWindow({required this.sessions, required this.hasData});

  const UsageWindow.empty()
      : sessions = const [],
        hasData = false;

  final List<UsageSession> sessions;

  /// Vrai si Android a garde au moins un evenement dans l'intervalle, de
  /// n'importe quelle application.
  ///
  /// C'est ce qui distingue « zero minute sur Instagram » de « historique
  /// efface » : Android ne garde qu'une dizaine de jours, et une journee trop
  /// ancienne repondrait vide. La compter comme une journee parfaite
  /// remplirait la cagnotte de faux gains.
  final bool hasData;
}

/// D'ou viennent les mesures : les statistiques d'utilisation d'Android.
abstract interface class IUsageSource {
  /// Faux hors Android : iOS n'expose pas ces donnees aux applications.
  bool get isSupported;

  /// L'acces aux donnees d'utilisation, accorde a la main dans les reglages.
  Future<bool> hasAccess();

  /// Ouvre l'ecran des reglages ou l'accorder.
  Future<void> openAccessSettings();

  /// Les passages au premier plan des [packages] entre [from] et [to].
  Future<UsageWindow> sessions(DateTime from, DateTime to, Set<String> packages);

  /// Les applications qui ont une icone dans le lanceur.
  Future<List<TrackedApp>> launchableApps();

  /// Programme le bilan du soir, ou l'annule si [config] est nul.
  Future<void> configureReport(Map<String, Object?>? config);

  /// Demande l'autorisation d'afficher des notifications (Android 13+).
  Future<bool> requestNotifications();
}

/// La source Android, par le canal `izerak/screen_time` (cf. MainActivity.kt).
class AndroidUsageSource implements IUsageSource {
  AndroidUsageSource({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('izerak/screen_time');

  final MethodChannel _channel;

  @override
  bool get isSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<bool> hasAccess() async =>
      isSupported && (await _channel.invokeMethod<bool>('hasAccess') ?? false);

  @override
  Future<void> openAccessSettings() => _channel.invokeMethod<void>('openAccessSettings');

  @override
  Future<UsageWindow> sessions(DateTime from, DateTime to, Set<String> packages) async {
    if (!isSupported || packages.isEmpty) {
      return const UsageWindow.empty();
    }
    final raw = await _channel.invokeMapMethod<String, Object?>('sessions', {
      'from': from.millisecondsSinceEpoch,
      'to': to.millisecondsSinceEpoch,
      'packages': packages.toList(),
    });
    return parseUsageWindow(raw);
  }

  @override
  Future<List<TrackedApp>> launchableApps() async {
    if (!isSupported) {
      return const [];
    }
    final raw = await _channel.invokeListMethod<Object?>('launchableApps') ?? const [];
    return [
      for (final item in raw)
        if (item is Map && item['package'] is String)
          TrackedApp(
            package: item['package'] as String,
            label: item['label'] is String ? item['label'] as String : item['package'] as String,
          ),
    ];
  }

  @override
  Future<void> configureReport(Map<String, Object?>? config) async {
    if (isSupported) {
      await _channel.invokeMethod<void>('configureReport', config);
    }
  }

  @override
  Future<bool> requestNotifications() async =>
      isSupported && (await _channel.invokeMethod<bool>('requestNotifications') ?? false);
}

/// Relecture de la reponse du canal : `{hasData, sessions: [{p, s, e}]}`, les
/// instants en millisecondes.
@visibleForTesting
UsageWindow parseUsageWindow(Map<String, Object?>? raw) {
  if (raw == null) {
    return const UsageWindow.empty();
  }
  final sessions = <UsageSession>[];
  if (raw['sessions'] case final List<Object?> list) {
    for (final item in list) {
      if (item is Map && item['p'] is String && item['s'] is int && item['e'] is int) {
        sessions.add(UsageSession(
          item['p'] as String,
          DateTime.fromMillisecondsSinceEpoch(item['s'] as int),
          DateTime.fromMillisecondsSinceEpoch(item['e'] as int),
        ));
      }
    }
  }
  return UsageWindow(sessions: sessions, hasData: raw['hasData'] == true);
}
