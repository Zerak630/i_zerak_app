import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:i_zerak_app/models/commute_dao.dart';
import 'package:i_zerak_app/models/screen_time_dao.dart' show ScreenTimeLedger;
import 'package:i_zerak_app/services/commute_price_service.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_commute.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_screen_time.dart';

/// Ce que l'application peut demander aux widgets de l'ecran d'accueil.
abstract interface class IHomeWidgetBridge {
  bool get isSupported;

  /// Remplace l'instantane que lisent les widgets, et les redessine.
  Future<void> update(Map<String, Object?> snapshot);

  /// Les journees a velo enregistrees depuis le widget, « aaaa-mm-jj ».
  /// Les relire les efface : chacune n'est rendue qu'une fois.
  Future<List<String>> takePendingBikeDays();

  /// Ce qu'un widget a demande en ouvrant l'application (« car » pour le
  /// bouton Voiture), une seule fois.
  Future<String?> takeLaunchAction();
}

/// Les widgets Android, par le canal `izerak/home_widgets` (cf. HomeWidgets.kt).
class AndroidHomeWidgetBridge implements IHomeWidgetBridge {
  AndroidHomeWidgetBridge({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('izerak/home_widgets');

  final MethodChannel _channel;

  @override
  bool get isSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<void> update(Map<String, Object?> snapshot) async {
    if (isSupported) {
      await _channel.invokeMethod<void>('update', snapshot);
    }
  }

  @override
  Future<List<String>> takePendingBikeDays() async {
    if (!isSupported) {
      return const [];
    }
    final raw = await _channel.invokeListMethod<Object?>('takePendingBikeDays') ?? const [];
    return [for (final item in raw) if (item is String) item];
  }

  @override
  Future<String?> takeLaunchAction() async =>
      isSupported ? await _channel.invokeMethod<String>('takeLaunchAction') : null;
}

/// Tient les widgets de l'ecran d'accueil a jour, et rapatrie ce qui y a ete
/// fait.
///
/// Les widgets ne lisent pas Hive : ils dessinent un instantane que
/// l'application leur transmet chaque fois qu'elle passe en arriere-plan,
/// c'est-a-dire chaque fois qu'ils redeviennent visibles. Un appui sur
/// « Velo » ne calcule rien cote natif : il note la date, et c'est ici, au
/// lancement suivant, que la journee est enregistree au prix du carburant de
/// ce jour-la.
class HomeWidgetsService {
  HomeWidgetsService({
    required this.commute,
    required this.screenTime,
    required this.prices,
    required this.bridge,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  final ICommute commute;
  final IScreenTime screenTime;
  final CommutePriceService prices;
  final IHomeWidgetBridge bridge;
  final DateTime Function() clock;

  /// Enregistre les journees a velo saisies depuis le widget. Renvoie le
  /// nombre de journees ajoutees.
  ///
  /// Une journee deja enregistree dans l'application n'est pas ecrasee : le
  /// widget a pu etre touche avant que l'application ne lui apprenne que la
  /// journee etait faite.
  Future<int> importPendingBikeDays() async {
    if (!bridge.isSupported) {
      return 0;
    }
    final pending = await bridge.takePendingBikeDays();
    if (pending.isEmpty) {
      return 0;
    }
    final settings = await commute.readSettings();
    if (!settings.isConfigured) {
      return 0;
    }
    final known = {for (final day in await commute.getDays()) day.date};
    var added = 0;
    for (final raw in pending.toSet()) {
      final date = parseDayKey(raw);
      if (date == null || known.contains(date)) {
        continue;
      }
      final price = await prices.resolve(settings.fuel, day: date);
      await commute.saveDay(CommuteDay.bike(date, settings, price));
      known.add(date);
      added++;
    }
    return added;
  }

  /// Ce qu'un widget a demande en ouvrant l'application, une seule fois.
  Future<String?> takeLaunchAction() async =>
      bridge.isSupported ? await bridge.takeLaunchAction() : null;

  /// Envoie l'etat du jour aux widgets.
  Future<void> refresh() async {
    if (!bridge.isSupported) {
      return;
    }
    try {
      await bridge.update(await snapshot());
    } on Exception catch (error) {
      debugPrint('Widgets non mis a jour : $error');
    }
  }

  @visibleForTesting
  Future<Map<String, Object?>> snapshot() async {
    final now = clock();
    final today = dateOnly(now);
    final settings = await commute.readSettings();
    final ledger = CommuteLedger(await commute.getDays(), await commute.getGoals());
    final free = ScreenTimeLedger(
      settings: await screenTime.readSettings(),
      days: await screenTime.getDays(),
      goals: await screenTime.getGoals(),
      today: today,
    );

    // Pas d'appel reseau ici : l'application passe en arriere-plan, et le
    // montant affiche n'est qu'une estimation que l'import corrigera.
    final observed = await commute.latestPrice(settings.fuel, onOrBefore: today);
    final tripValue = settings.tripValue(observed?.price ?? kFallbackFuelPrice);
    final recorded = ledger.dayOn(today);

    return buildSnapshot(
      today: today,
      commuteConfigured: settings.isConfigured,
      tripValue: tripValue,
      recorded: recorded,
      commuteBook: ledger.book,
      freeBook: free.book,
    );
  }

  /// L'instantane lui-meme, sans acces au stockage.
  @visibleForTesting
  static Map<String, Object?> buildSnapshot({
    required DateTime today,
    required bool commuteConfigured,
    required double tripValue,
    required CommuteDay? recorded,
    required GoalBook commuteBook,
    required GoalBook freeBook,
  }) {
    Map<String, Object?> goal(Goal goal, GoalBook book, String pot) {
      final progress = book.progressOf(goal);
      return {
        'id': goal.id,
        'name': goal.name,
        'pot': pot,
        'milestone': goal.kind == GoalKind.milestone,
        'current': roundCents(progress.current),
        'target': goal.target,
      };
    }

    return {
      'today': dayKey(today),
      'commute': {
        'configured': commuteConfigured,
        'tripValue': tripValue,
        // « bike », « car », « remote » ou absent : ce que le widget affiche a la place
        // des deux boutons.
        if (recorded != null) 'recorded': recorded.mode.name,
        if (recorded != null) 'amount': recorded.amount,
        // En voiture, la cagnotte alimentee : « essential » ou
        // « missed ».
        if (recorded?.bucket != null) 'bucket': recorded!.bucket!.name,
      },
      'goals': [
        for (final g in commuteBook.activeGoals) goal(g, commuteBook, 'commute'),
        for (final g in freeBook.activeGoals) goal(g, freeBook, 'free'),
      ],
    };
  }
}
