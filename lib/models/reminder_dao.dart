/// Les rappels du soir : « Velo ou voiture aujourd'hui ? » les jours ouvres,
/// et « Seance faite ? » les jours ou le programme prevoit du sport.
///
/// Propres a l'appareil, comme les bilans : ils ne se synchronisent pas.
library;

class ReminderSettings {
  const ReminderSettings({
    this.commute = true,
    this.commuteHour = 18,
    this.commuteMinute = 30,
    this.sport = true,
    this.sportHour = 20,
    this.sportMinute = 30,
  });

  /// Rappel du trajet, du lundi au vendredi.
  final bool commute;
  final int commuteHour;
  final int commuteMinute;

  /// Rappel des creneaux du programme, les jours ou il y en a.
  final bool sport;
  final int sportHour;
  final int sportMinute;

  ReminderSettings copyWith({
    bool? commute,
    int? commuteHour,
    int? commuteMinute,
    bool? sport,
    int? sportHour,
    int? sportMinute,
  }) =>
      ReminderSettings(
        commute: commute ?? this.commute,
        commuteHour: commuteHour ?? this.commuteHour,
        commuteMinute: commuteMinute ?? this.commuteMinute,
        sport: sport ?? this.sport,
        sportHour: sportHour ?? this.sportHour,
        sportMinute: sportMinute ?? this.sportMinute,
      );

  Map<String, dynamic> toJson() => {
        'commute': commute,
        'commute_hour': commuteHour,
        'commute_minute': commuteMinute,
        'sport': sport,
        'sport_hour': sportHour,
        'sport_minute': sportMinute,
      };

  /// Relecture tolerante : un champ abime reprend sa valeur par defaut.
  factory ReminderSettings.fromJson(Object? raw) {
    const defaults = ReminderSettings();
    if (raw is! Map) {
      return defaults;
    }
    bool flag(String key, bool fallback) => raw[key] is bool ? raw[key] as bool : fallback;
    int number(String key, int max, int fallback) =>
        raw[key] is num ? (raw[key] as num).toInt().clamp(0, max) : fallback;
    return ReminderSettings(
      commute: flag('commute', defaults.commute),
      commuteHour: number('commute_hour', 23, defaults.commuteHour),
      commuteMinute: number('commute_minute', 59, defaults.commuteMinute),
      sport: flag('sport', defaults.sport),
      sportHour: number('sport_hour', 23, defaults.sportHour),
      sportMinute: number('sport_minute', 59, defaults.sportMinute),
    );
  }
}

/// Une reponse donnee depuis la notification d'un creneau, en attente d'etre
/// enregistree par l'application : « done|slot|aaaa-mm-jj » ou
/// « skipped|slot|aaaa-mm-jj ».
class PendingSlotAnswer {
  const PendingSlotAnswer({required this.done, required this.slotId, required this.day});

  final bool done;
  final String slotId;
  final DateTime day;

  static PendingSlotAnswer? parse(String raw, DateTime? Function(String) parseDay) {
    final parts = raw.split('|');
    if (parts.length != 3 || (parts[0] != 'done' && parts[0] != 'skipped')) {
      return null;
    }
    final day = parseDay(parts[2]);
    if (day == null || parts[1].isEmpty) {
      return null;
    }
    return PendingSlotAnswer(done: parts[0] == 'done', slotId: parts[1], day: day);
  }
}
