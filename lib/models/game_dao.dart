/// Le temps de jeu et le contrat qui le compense par du sport.
///
/// Le jeu d'une semaine fixe le sport de la suivante : la cible ne bouge plus
/// une fois la semaine commencee, et une session du dimanche soir ne cree pas
/// une dette impossible a rattraper.
///
/// Dart pur. Seuls les releves viennent de l'agent du Pi : le contrat se
/// recalcule a partir d'eux, des seances et des trajets.
library;

import 'dart:convert';

import 'package:i_zerak_app/models/commute_dao.dart' show CommuteDay, dateOnly, dayKey, parseDayKey;
import 'package:i_zerak_app/models/sport_dao.dart' show SportLedger, dayOfWeek, weekStart;

int _asInt(Object? raw) => raw is num ? raw.toInt() : 0;

int? _asIntOrNull(Object? raw) => raw is num ? raw.toInt() : null;

/// Les seuls hotes d'ou l'application accepte de charger une image de jeu.
///
/// L'agent compose les adresses, mais un rapport n'est qu'un texte : une
/// adresse ailleurs ne serait jamais chargee.
const _imageHosts = {'media.steampowered.com', 'ddragon.leagueoflegends.com'};

String? _imageUrl(Object? raw) {
  if (raw is! String) {
    return null;
  }
  final uri = Uri.tryParse(raw);
  if (uri == null || uri.scheme != 'https' || !_imageHosts.contains(uri.host)) {
    return null;
  }
  return raw;
}

/// Un jeu Steam et son temps sur la semaine.
class GameTitle {
  const GameTitle({
    required this.name,
    required this.minutes,
    this.appId,
    this.lifetimeMinutes,
    this.icon,
  });

  final String name;
  final int minutes;
  final String? appId;

  /// Le cumul Steam depuis toujours, tel que releve.
  final int? lifetimeMinutes;

  /// L'icone du jeu, sur le CDN de Steam.
  final String? icon;

  Map<String, dynamic> toJson() => {
        'name': name,
        'minutes': minutes,
        if (appId != null) 'appid': appId,
        if (lifetimeMinutes != null) 'lifetime_minutes': lifetimeMinutes,
        if (icon != null) 'icon': icon,
      };

  static GameTitle? fromJson(Object? raw) {
    if (raw is! Map || raw['name'] is! String) {
      return null;
    }
    return GameTitle(
      name: raw['name'] as String,
      minutes: _asInt(raw['minutes']),
      appId: raw['appid'] is String ? raw['appid'] as String : null,
      lifetimeMinutes: _asIntOrNull(raw['lifetime_minutes']),
      icon: _imageUrl(raw['icon']),
    );
  }
}

/// Un jour de la semaine, source par source.
class GameDay {
  const GameDay({
    required this.day,
    this.steamMinutes = 0,
    this.lolMinutes = 0,
    this.measured = const [],
  });

  final DateTime day;
  final int steamMinutes;
  final int lolMinutes;

  /// Les sources qui ont releve ce jour-la. Vide : on ne sait pas, ce n'est
  /// pas 0 h.
  final List<String> measured;

  int get minutes => steamMinutes + lolMinutes;

  Map<String, dynamic> toJson() => {
        'day': dayKey(day),
        'steam_minutes': steamMinutes,
        'lol_minutes': lolMinutes,
        'measured': measured,
      };

  static GameDay? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final day = parseDayKey('${raw['day']}');
    if (day == null) {
      return null;
    }
    return GameDay(
      day: day,
      steamMinutes: _asInt(raw['steam_minutes']),
      lolMinutes: _asInt(raw['lol_minutes']),
      measured: [
        if (raw['measured'] case final List<dynamic> list)
          for (final source in list)
            if (source is String) source,
      ],
    );
  }
}

/// Le genre de partie LoL, tel que l'ecran le regroupe.
enum LolQueue {
  ranked,
  aram,
  normal,
  arena,
  other;

  /// D'apres le `queueId` de Riot.
  static LolQueue of(int? id) => switch (id) {
        420 || 440 => LolQueue.ranked,
        450 || 100 || 720 => LolQueue.aram,
        400 || 430 || 480 || 490 => LolQueue.normal,
        1700 || 1710 => LolQueue.arena,
        _ => LolQueue.other,
      };
}

/// Une partie de LoL.
class LolMatch {
  const LolMatch({
    required this.minutes,
    required this.win,
    this.start,
    this.champion,
    this.kills,
    this.deaths,
    this.assists,
    this.queueId,
    this.portrait,
  });

  final DateTime? start;
  final int minutes;
  final bool win;
  final String? champion;
  final int? kills;
  final int? deaths;
  final int? assists;
  final int? queueId;

  /// Le portrait du champion, sur Data Dragon.
  final String? portrait;

  LolQueue get queue => LolQueue.of(queueId);

  /// Le classe solo, seul a faire bouger le rang affiche.
  bool get isSoloRanked => queueId == 420;

  bool get hasKda => kills != null && deaths != null && assists != null;

  Map<String, dynamic> toJson() => {
        if (start != null) 'start': start!.millisecondsSinceEpoch ~/ 1000,
        'minutes': minutes,
        'win': win,
        if (champion != null) 'champion': champion,
        if (kills != null) 'kills': kills,
        if (deaths != null) 'deaths': deaths,
        if (assists != null) 'assists': assists,
        if (queueId != null) 'queue': queueId,
        if (portrait != null) 'portrait': portrait,
      };

  static LolMatch? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final start = _asIntOrNull(raw['start']);
    return LolMatch(
      start: start == null ? null : DateTime.fromMillisecondsSinceEpoch(start * 1000),
      minutes: _asInt(raw['minutes']),
      win: raw['win'] == true,
      champion: raw['champion'] is String ? raw['champion'] as String : null,
      kills: _asIntOrNull(raw['kills']),
      deaths: _asIntOrNull(raw['deaths']),
      assists: _asIntOrNull(raw['assists']),
      queueId: _asIntOrNull(raw['queue']),
      portrait: _imageUrl(raw['portrait']),
    );
  }
}

/// Le rang en classe solo.
class LolRank {
  const LolRank({this.tier, this.division, this.lp = 0, this.wins = 0, this.losses = 0});

  /// `GOLD`, `DIAMOND`… Nul : pas classe cette saison.
  final String? tier;
  final String? division;
  final int lp;
  final int wins;
  final int losses;

  bool get isRanked => tier != null;

  /// Les trois derniers paliers n'ont pas de division.
  bool get hasDivision => !const {'MASTER', 'GRANDMASTER', 'CHALLENGER'}.contains(tier);

  Map<String, dynamic> toJson() => {
        'tier': tier,
        if (division != null) 'division': division,
        'lp': lp,
        'wins': wins,
        'losses': losses,
      };

  static LolRank? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    return LolRank(
      tier: raw['tier'] is String ? raw['tier'] as String : null,
      division: raw['division'] is String ? raw['division'] as String : null,
      lp: _asInt(raw['lp']),
      wins: _asInt(raw['wins']),
      losses: _asInt(raw['losses']),
    );
  }
}

/// Une semaine de jeu, telle que l'agent l'a relevee.
class GameWeek {
  const GameWeek({
    required this.monday,
    required this.minutes,
    required this.complete,
    this.steamMinutes = 0,
    this.lolMinutes = 0,
    this.lolGames = 0,
    this.lolWins = 0,
    this.games = const [],
    this.days = const [],
    this.matches = const [],
    this.lpChange,
  });

  final DateTime monday;
  final int minutes;

  /// Faux quand un releve manque : le total ne vaut alors pas mesure, et ne
  /// fixe aucun contrat.
  final bool complete;

  final int steamMinutes;
  final int lolMinutes;
  final int lolGames;
  final int lolWins;

  /// Du plus joue au moins joue.
  final List<GameTitle> games;

  /// Du lundi au dimanche. Vide avec un agent qui ne les publie pas encore.
  final List<GameDay> days;

  /// De la plus recente a la plus ancienne. Seules celles que l'agent a
  /// relevees en detail : il peut y en avoir moins que [lolGames].
  final List<LolMatch> matches;

  /// Les LP gagnes en classe solo, nul d'une division a l'autre.
  final int? lpChange;

  /// Les parties comptees sans detail, relevees avant que l'agent le garde.
  int get matchesWithoutDetail => lolGames > matches.length ? lolGames - matches.length : 0;

  Map<String, dynamic> toJson() => {
        'monday': dayKey(monday),
        'minutes': minutes,
        'complete': complete,
        'steam_minutes': steamMinutes,
        'lol_minutes': lolMinutes,
        'lol_games': lolGames,
        'lol_wins': lolWins,
        'games': [for (final game in games) game.toJson()],
        'days': [for (final day in days) day.toJson()],
        'matches': [for (final match in matches) match.toJson()],
        if (lpChange != null) 'lp_change': lpChange,
      };

  static GameWeek? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final monday = parseDayKey('${raw['monday']}');
    if (monday == null) {
      return null;
    }
    return GameWeek(
      monday: monday,
      minutes: _asInt(raw['minutes']),
      complete: raw['complete'] == true,
      steamMinutes: _asInt(raw['steam_minutes']),
      lolMinutes: _asInt(raw['lol_minutes']),
      lolGames: _asInt(raw['lol_games']),
      lolWins: _asInt(raw['lol_wins']),
      games: [
        if (raw['games'] case final List<dynamic> list)
          for (final item in list)
            if (GameTitle.fromJson(item) case final GameTitle game) game,
      ],
      days: [
        if (raw['days'] case final List<dynamic> list)
          for (final item in list)
            if (GameDay.fromJson(item) case final GameDay day) day,
      ],
      matches: [
        if (raw['matches'] case final List<dynamic> list)
          for (final item in list)
            if (LolMatch.fromJson(item) case final LolMatch match) match,
      ],
      lpChange: _asIntOrNull(raw['lp_change']),
    );
  }
}

/// Ce que l'agent sait du temps de jeu.
class GamingReport {
  const GamingReport({
    this.sources = const [],
    this.weeks = const [],
    this.errors = const {},
    this.updatedAt,
    this.notifyToken,
    this.origin,
    this.lolRank,
  });

  /// L'agent qui a fourni ce releve : il ne vaut pas pour un autre serveur.
  final String? origin;

  /// Nul tant que l'agent ne l'a pas lu (ou sans LoL).
  final LolRank? lolRank;

  GamingReport withOrigin(String? value) => GamingReport(
        sources: sources,
        weeks: weeks,
        errors: errors,
        updatedAt: updatedAt,
        notifyToken: notifyToken,
        origin: value,
        lolRank: lolRank,
      );

  /// Les sources configurees sur le Pi : `steam`, `lol`.
  final List<String> sources;

  final List<GameWeek> weeks;

  /// Par source, le code du dernier releve en echec.
  final Map<String, String> errors;

  final DateTime? updatedAt;

  /// Le jeton limite au total d'une semaine, pour la notification du dimanche.
  final String? notifyToken;

  bool get isConfigured => sources.isNotEmpty;

  GameWeek? weekOf(DateTime day) {
    final monday = weekStart(day);
    for (final week in weeks) {
      if (week.monday == monday) {
        return week;
      }
    }
    return null;
  }

  String encode() => json.encode({
        'sources': sources,
        'weeks': [for (final week in weeks) week.toJson()],
        'errors': errors,
        if (updatedAt != null) 'updated_at': updatedAt!.millisecondsSinceEpoch ~/ 1000,
        if (notifyToken != null) 'notify_token': notifyToken,
        if (origin != null) 'origin': origin,
        if (lolRank != null) 'lol_rank': lolRank!.toJson(),
      });

  /// Relecture de la copie locale : abimee, elle vaut « rien de configure ».
  static GamingReport decode(String body) => tryDecode(body) ?? const GamingReport();

  /// Nul si ce n'est pas un rapport : un portail captif qui repond 200 ne doit
  /// pas passer pour un agent qui n'a rien a dire.
  static GamingReport? tryDecode(String body) {
    final Object? raw;
    try {
      raw = json.decode(body);
    } on FormatException {
      return null;
    }
    if (raw is! Map || raw['sources'] is! List || raw['weeks'] is! List) {
      return null;
    }
    final updated = raw['updated_at'];
    return GamingReport(
      sources: [
        if (raw['sources'] case final List<dynamic> list)
          for (final source in list)
            if (source is String) source,
      ],
      weeks: [
        if (raw['weeks'] case final List<dynamic> list)
          for (final item in list)
            if (GameWeek.fromJson(item) case final GameWeek week) week,
      ],
      errors: {
        if (raw['errors'] case final Map<dynamic, dynamic> map)
          for (final entry in map.entries)
            if (entry.key is String && entry.value is String)
              entry.key as String: entry.value as String,
      },
      updatedAt: updated is num
          ? DateTime.fromMillisecondsSinceEpoch(updated.toInt() * 1000)
          : null,
      notifyToken: raw['notify_token'] is String ? raw['notify_token'] as String : null,
      origin: raw['origin'] is String ? raw['origin'] as String : null,
      lolRank: LolRank.fromJson(raw['lol_rank']),
    );
  }
}

/// Des regles remplacees, et le lundi a partir duquel elles ne valent plus.
class GameRulesPeriod {
  const GameRulesPeriod({required this.until, required this.rules});

  final DateTime until;
  final GameContractSettings rules;

  Map<String, dynamic> toJson() => {'until': dayKey(until), ...rules.toJson()};

  static GameRulesPeriod? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final until = parseDayKey('${raw['until']}');
    return until == null
        ? null
        : GameRulesPeriod(until: until, rules: GameContractSettings.fromJson(raw));
  }
}

/// Les regles du contrat. Propres a l'appareil, comme les notifications.
class GameContractSettings {
  const GameContractSettings({
    this.enabled = true,
    this.gameHoursPerSportHour = 3,
    this.capMinutes = 360,
    this.bikeMinutesPerDay = 60,
    this.history = const [],
  });

  /// Les regles precedentes, de la plus ancienne a la plus recente : un
  /// contrat garde celles de sa semaine.
  final List<GameRulesPeriod> history;

  /// Les regles qui valent pour la semaine de [day].
  GameContractSettings rulesFor(DateTime day) {
    final monday = weekStart(day);
    for (final period in history) {
      if (monday.isBefore(period.until)) {
        return period.rules;
      }
    }
    return this;
  }

  /// Ces regles remplacees par [next], a partir du lundi qui suit [today] :
  /// ni les semaines passees ni la cible en cours ne bougent.
  GameContractSettings edited(GameContractSettings next, DateTime today) {
    if (next.gameHoursPerSportHour == gameHoursPerSportHour &&
        next.capMinutes == capMinutes &&
        next.bikeMinutesPerDay == bikeMinutesPerDay) {
      return copyWith(enabled: next.enabled);
    }
    final monday = weekStart(today);
    final from = DateTime(monday.year, monday.month, monday.day + 7);
    // Deja modifiees cette semaine : ce qui vaut jusqu'a dimanche est note.
    final noted = history.isNotEmpty && !history.last.until.isBefore(from);
    return next.copyWith(
      history: noted
          ? history
          : [...history, GameRulesPeriod(until: from, rules: copyWith(history: const []))],
    );
  }

  final bool enabled;

  /// Combien d'heures de jeu une heure de sport compense.
  final int gameHoursPerSportHour;

  /// Le plafond : apres une semaine de vacances, le ratio seul demanderait
  /// plus de sport qu'il n'est raisonnable d'en faire.
  final int capMinutes;

  /// Ce que vaut une journee a velo, aller et retour compris.
  final int bikeMinutesPerDay;

  GameContractSettings copyWith({
    bool? enabled,
    int? gameHoursPerSportHour,
    int? capMinutes,
    int? bikeMinutesPerDay,
    List<GameRulesPeriod>? history,
  }) =>
      GameContractSettings(
        enabled: enabled ?? this.enabled,
        gameHoursPerSportHour: gameHoursPerSportHour ?? this.gameHoursPerSportHour,
        capMinutes: capMinutes ?? this.capMinutes,
        bikeMinutesPerDay: bikeMinutesPerDay ?? this.bikeMinutesPerDay,
        history: history ?? this.history,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'ratio': gameHoursPerSportHour,
        'cap': capMinutes,
        'bike': bikeMinutesPerDay,
        if (history.isNotEmpty) 'history': [for (final period in history) period.toJson()],
      };

  factory GameContractSettings.fromJson(Object? raw) {
    const defaults = GameContractSettings();
    if (raw is! Map) {
      return defaults;
    }
    int read(Object? value, int fallback, int min, int max) =>
        value is num ? value.toInt().clamp(min, max) : fallback;
    return GameContractSettings(
      enabled: raw['enabled'] is bool ? raw['enabled'] as bool : defaults.enabled,
      gameHoursPerSportHour: read(raw['ratio'], defaults.gameHoursPerSportHour, 1, 10),
      capMinutes: read(raw['cap'], defaults.capMinutes, 30, 1200),
      bikeMinutesPerDay: read(raw['bike'], defaults.bikeMinutesPerDay, 0, 240),
      history: [
        if (raw['history'] case final List<dynamic> list)
          for (final item in list)
            if (GameRulesPeriod.fromJson(item) case final GameRulesPeriod period) period,
      ]..sort((a, b) => a.until.compareTo(b.until)),
    );
  }

  /// Le sport que [played] minutes de jeu demandent : arrondi aux cinq
  /// minutes superieures, dans la limite du plafond. Meme calcul que
  /// `RecapReport.kt`.
  int targetFor(int played) {
    if (played <= 0) {
      return 0;
    }
    final step = gameHoursPerSportHour * 5;
    final target = ((played + step - 1) ~/ step) * 5;
    return target < capMinutes ? target : capMinutes;
  }
}

/// Le contrat d'une semaine.
class GameContract {
  const GameContract({
    required this.monday,
    required this.playedBefore,
    required this.targetMinutes,
    required this.sportMinutes,
    required this.bikeDays,
    required this.bikeMinutes,
  });

  final DateTime monday;

  /// Le jeu de la semaine precedente, celui qui fixe la cible.
  final int playedBefore;

  final int targetMinutes;
  final int sportMinutes;
  final int bikeDays;
  final int bikeMinutes;

  int get doneMinutes => sportMinutes + bikeMinutes;

  bool get kept => doneMinutes >= targetMinutes;

  int get remaining => kept ? 0 : targetMinutes - doneMinutes;

  double get ratio =>
      targetMinutes <= 0 ? 1 : (doneMinutes / targetMinutes).clamp(0, 1).toDouble();
}

/// Ce que le bilan d'une semaine dit du jeu.
class GameRecap {
  const GameRecap({
    required this.played,
    required this.contract,
    required this.streak,
    required this.nextTarget,
  });

  final GameWeek? played;
  final GameContract? contract;
  final int streak;

  /// Le sport de la semaine suivante. Nul tant que le total n'est pas fiable.
  final int? nextTarget;
}

/// Les contrats, calcules a partir des releves, des seances et des trajets.
class GameContractLedger {
  GameContractLedger({
    required this.report,
    required this.settings,
    required this.sport,
    required Iterable<CommuteDay> commute,
  }) : _commute = [...commute];

  final GamingReport report;
  final GameContractSettings settings;
  final SportLedger sport;
  final List<CommuteDay> _commute;

  /// Le contrat de la semaine qui contient [day]. Nul sans semaine precedente
  /// complete : une absence de mesure ne vaut ni 0 h, ni un echec.
  GameContract? contractOf(DateTime day) {
    if (!settings.enabled) {
      return null;
    }
    final monday = weekStart(day);
    final before = report.weekOf(DateTime(monday.year, monday.month, monday.day - 7));
    if (before == null || !before.complete) {
      return null;
    }
    final sunday = dayOfWeek(monday, DateTime.sunday);
    final bikeDays = _commute
        .where((entry) =>
            entry.isBike && !dateOnly(entry.date).isBefore(monday) && !dateOnly(entry.date).isAfter(sunday))
        .length;
    final rules = settings.rulesFor(monday);
    return GameContract(
      monday: monday,
      playedBefore: before.minutes,
      targetMinutes: rules.targetFor(before.minutes),
      sportMinutes: sport.minutesBetween(monday, sunday),
      bikeDays: bikeDays,
      bikeMinutes: bikeDays * rules.bikeMinutesPerDay,
    );
  }

  /// Les semaines tenues d'affilee jusqu'a celle de [day].
  ///
  /// Une semaine sans contrat ou sans jeu a compenser ne compte pas et ne
  /// rompt rien. La semaine en cours ne rompt rien non plus : il reste des
  /// jours pour la tenir.
  int streakAt(DateTime day) {
    final current = weekStart(sport.today);
    var monday = weekStart(day);
    var count = 0;
    for (var index = 0; index < report.weeks.length; index++) {
      final contract = contractOf(monday);
      if (contract != null && contract.targetMinutes > 0) {
        if (contract.kept) {
          count++;
        } else if (monday.isBefore(current)) {
          // `current` date du chargement : une page restee ouverte peut deja
          // regarder la semaine d'apres, qui n'est pas finie non plus.
          break;
        }
      }
      monday = DateTime(monday.year, monday.month, monday.day - 7);
    }
    return count;
  }

  /// Nul quand le contrat est desactive ou que rien n'est configure.
  GameRecap? recapOf(DateTime day) {
    if (!settings.enabled || !report.isConfigured) {
      return null;
    }
    final played = report.weekOf(day);
    final monday = weekStart(day);
    final nextRules = settings.rulesFor(DateTime(monday.year, monday.month, monday.day + 7));
    return GameRecap(
      played: played,
      contract: contractOf(day),
      streak: streakAt(day),
      nextTarget: played != null && played.complete ? nextRules.targetFor(played.minutes) : null,
    );
  }
}
