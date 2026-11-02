/// Temps passe sur les reseaux sociaux : mesure, quota et cagnotte.
///
/// Dart pur, sans import Flutter, comme `commute_dao.dart` : decouper des
/// sessions par jour et par heure, et en tirer de l'argent, se rate en
/// silence. Tout se teste avec `package:test`.
///
/// Le principe : une moyenne de depart, mesuree sur les jours precedant la
/// mise en route, puis un quota qui baisse chaque semaine. Chaque journee
/// terminee sous cette moyenne rapporte, au prorata du temps gagne. Comme pour
/// le velo, une journee close est figee : changer de tarif ou de quota ne
/// reecrit pas ce qui a deja ete gagne.
library;

import 'dart:math' as math;

import 'package:i_zerak_app/models/commute_dao.dart'
    show Goal, GoalBook, dateOnly, dayKey, parseDayKey, roundCents;

// Lecteurs tolerants : un champ d'un type inattendu est traite comme absent.
double? _asDouble(Object? raw) => raw is num ? raw.toDouble() : null;

int? _asInt(Object? raw) => raw is num ? raw.toInt() : null;

String? _asString(Object? raw) => raw is String ? raw : null;

/// Nombre de jours calendaires de [from] a [to].
///
/// Calcule en UTC : en heure locale, un passage a l'heure d'ete raccourcit un
/// jour d'une heure, et `inDays` le compterait comme zero.
int daysBetween(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day)
        .difference(DateTime.utc(from.year, from.month, from.day))
        .inDays;

/// Les applications cochees d'office a la premiere configuration, quand elles
/// sont installees. Le libelle n'est qu'un repli : celui que donne Android
/// prime.
const Map<String, String> kSuggestedApps = {
  'com.instagram.android': 'Instagram',
  'com.google.android.youtube': 'YouTube',
  'com.twitter.android': 'X',
  'com.reddit.frontpage': 'Reddit',
  'com.facebook.katana': 'Facebook',
  'com.facebook.lite': 'Facebook Lite',
};

/// Deux passages dans la meme application separes de moins que cela ne font
/// qu'une ouverture : changer d'ecran dans Instagram met l'activite en pause
/// une fraction de seconde, et un coup d'oeil a une notification ne merite pas
/// d'etre compte comme une rechute.
const Duration kSessionMergeGap = Duration(seconds: 30);

/// Une application suivie.
class TrackedApp {
  const TrackedApp({required this.package, required this.label});

  /// Identifiant Android, stable : c'est lui que retiennent les journees.
  final String package;

  final String label;

  Map<String, dynamic> toJson() => {'package': package, 'label': label};

  static TrackedApp? fromJson(Object? raw) {
    if (raw is! Map || raw['package'] is! String) {
      return null;
    }
    final package = raw['package'] as String;
    return TrackedApp(package: package, label: _asString(raw['label']) ?? package);
  }

  @override
  bool operator ==(Object other) => other is TrackedApp && other.package == package;

  @override
  int get hashCode => package.hashCode;
}

/// Un passage au premier plan d'une application, tel qu'Android le rapporte.
class UsageSession {
  const UsageSession(this.package, this.start, this.end);

  final String package;
  final DateTime start;
  final DateTime end;

  Duration get duration => end.difference(start);

  @override
  String toString() => 'UsageSession($package, $start → $end)';
}

/// Fusionne, application par application, les passages separes de moins de
/// [gap]. Le resultat est trie par debut.
List<UsageSession> mergeSessions(Iterable<UsageSession> sessions,
    {Duration gap = kSessionMergeGap}) {
  final sorted = [
    for (final session in sessions)
      if (session.end.isAfter(session.start)) session,
  ]..sort((a, b) => a.start.compareTo(b.start));

  final open = <String, UsageSession>{};
  final merged = <UsageSession>[];
  for (final session in sorted) {
    final current = open[session.package];
    if (current != null && !session.start.isAfter(current.end.add(gap))) {
      final end = session.end.isAfter(current.end) ? session.end : current.end;
      open[session.package] = UsageSession(session.package, current.start, end);
      continue;
    }
    if (current != null) {
      merged.add(current);
    }
    open[session.package] = session;
  }
  merged
    ..addAll(open.values)
    ..sort((a, b) => a.start.compareTo(b.start));
  return merged;
}

/// Temps et ouvertures d'une application sur une journee.
class AppUsage {
  const AppUsage({this.seconds = 0, this.opens = 0});

  final int seconds;
  final int opens;

  Map<String, dynamic> toJson() => {'s': seconds, 'o': opens};

  static AppUsage fromJson(Object? raw) => raw is Map
      ? AppUsage(seconds: _asInt(raw['s']) ?? 0, opens: _asInt(raw['o']) ?? 0)
      : const AppUsage();
}

/// Ce qu'une journee a mesure, sans jugement : ni quota, ni argent.
class DailyUsage {
  DailyUsage({required DateTime date, required this.apps, required List<int> hourly})
      : date = dateOnly(date),
        hourly = List.unmodifiable(hourly.length == 24 ? hourly : List.filled(24, 0));

  DailyUsage.empty(DateTime date) : this(date: date, apps: const {}, hourly: List.filled(24, 0));

  /// Decoupe [sessions] sur la journee [day], pour les seules [packages].
  ///
  /// Le temps est celui des sessions telles quelles ; les ouvertures, celles
  /// des sessions fusionnees (cf. `kSessionMergeGap`). Une session a cheval
  /// sur minuit n'est comptee que pour sa part dans la journee ; son
  /// ouverture compte pour le jour ou elle a commence.
  factory DailyUsage.fromSessions(
    DateTime day,
    Iterable<UsageSession> sessions,
    Set<String> packages,
  ) {
    final start = dateOnly(day);
    final end = DateTime(start.year, start.month, start.day + 1);
    final tracked = [for (final s in sessions) if (packages.contains(s.package)) s];
    final seconds = <String, int>{};
    final opens = <String, int>{};
    final hourly = List<int>.filled(24, 0);

    for (final session in tracked) {
      var from = session.start.isBefore(start) ? start : session.start;
      final to = session.end.isAfter(end) ? end : session.end;
      while (from.isBefore(to)) {
        final nextHour = DateTime(from.year, from.month, from.day, from.hour + 1);
        final sliceEnd = nextHour.isBefore(to) ? nextHour : to;
        final slice = sliceEnd.difference(from).inSeconds;
        hourly[from.hour] += slice;
        seconds[session.package] = (seconds[session.package] ?? 0) + slice;
        from = sliceEnd;
      }
    }
    for (final session in mergeSessions(tracked)) {
      if (!session.start.isBefore(start) && session.start.isBefore(end)) {
        opens[session.package] = (opens[session.package] ?? 0) + 1;
      }
    }
    return DailyUsage(
      date: start,
      apps: {
        for (final package in {...seconds.keys, ...opens.keys})
          package: AppUsage(seconds: seconds[package] ?? 0, opens: opens[package] ?? 0),
      },
      hourly: hourly,
    );
  }

  final DateTime date;

  /// Par identifiant d'application.
  final Map<String, AppUsage> apps;

  /// Secondes passees dans chaque heure de la journee, minuit en tete.
  final List<int> hourly;

  int get seconds => apps.values.fold(0, (sum, app) => sum + app.seconds);

  double get minutes => seconds / 60;

  int get opens => apps.values.fold(0, (sum, app) => sum + app.opens);

  /// Les applications utilisees, de la plus a la moins chronophage.
  List<MapEntry<String, AppUsage>> get ranked => apps.entries
      .where((entry) => entry.value.seconds > 0 || entry.value.opens > 0)
      .toList()
    ..sort((a, b) => b.value.seconds.compareTo(a.value.seconds));

  Map<String, dynamic> toJson() => {
        'apps': {for (final entry in apps.entries) entry.key: entry.value.toJson()},
        'hourly': hourly,
      };

  static DailyUsage fromJson(DateTime date, Object? raw) {
    if (raw is! Map) {
      return DailyUsage.empty(date);
    }
    final apps = <String, AppUsage>{
      if (raw['apps'] case final Map<dynamic, dynamic> map)
        for (final entry in map.entries)
          if (entry.key is String) entry.key as String: AppUsage.fromJson(entry.value),
    };
    final hourly = [
      if (raw['hourly'] case final List<dynamic> list)
        for (final value in list) _asInt(value) ?? 0,
    ];
    return DailyUsage(date: date, apps: apps, hourly: hourly);
  }
}

/// Reglages de l'onglet, et les deux valeurs figees a la mise en route.
class ScreenTimeSettings {
  const ScreenTimeSettings({
    this.apps = const [],
    this.ratePerHour = 2.0,
    this.weeklyDecrease = 0.10,
    this.floorMinutes = 20,
    this.reportEnabled = true,
    this.reportHour = 21,
    this.reportMinute = 30,
    this.baselineMinutes,
    this.startDate,
  });

  final List<TrackedApp> apps;

  /// Ce que rapporte une heure gagnee sur la moyenne de depart, en euros.
  final double ratePerHour;

  /// Baisse du quota chaque semaine, en fraction : 0,10 pour 10 %.
  final double weeklyDecrease;

  /// Le quota ne descend pas plus bas. Viser zero ferait d'une seule story
  /// regardee un echec, et c'est le meilleur moyen d'abandonner.
  final int floorMinutes;

  /// Le bilan du soir.
  final bool reportEnabled;
  final int reportHour;
  final int reportMinute;

  /// Minutes par jour avant la mise en route. Nulle tant que l'onglet n'est
  /// pas configure : une moyenne inventee remplirait la cagnotte de vent.
  final double? baselineMinutes;

  /// Premier jour compte. Les semaines du quota partent de ce jour-la.
  final DateTime? startDate;

  bool get isConfigured => apps.isNotEmpty && baselineMinutes != null && startDate != null;

  Set<String> get packages => {for (final app in apps) app.package};

  String labelOf(String package) {
    for (final app in apps) {
      if (app.package == package) {
        return app.label;
      }
    }
    return kSuggestedApps[package] ?? package;
  }

  /// Rang de la semaine de [day], la premiere etant la semaine 0.
  int weekOf(DateTime day) =>
      startDate == null ? 0 : math.max(0, daysBetween(startDate!, day) ~/ 7);

  /// Quota du jour, en minutes entieres.
  ///
  /// La premiere semaine baisse deja : une semaine « a la moyenne » ne
  /// demanderait aucun effort, et ne rapporterait rien. Si la moyenne de
  /// depart est deja sous le plancher, c'est elle qui sert de quota.
  double quotaFor(DateTime day) {
    final baseline = baselineMinutes ?? 0;
    final target = baseline * math.pow(1 - weeklyDecrease, weekOf(day) + 1);
    final floor = math.min(floorMinutes.toDouble(), baseline);
    return math.max(target, floor).roundToDouble();
  }

  /// Ce que vaudraient [minutes] passees sous la moyenne de depart.
  ///
  /// Mesure sur la moyenne, pas sur le quota : sous le quota, chaque minute
  /// gagnee en plus compte.
  double gainFor(double minutes) {
    final saved = math.max(0.0, (baselineMinutes ?? 0) - minutes);
    return roundCents(saved / 60 * ratePerHour);
  }

  /// Ce que rapporte une journee de [minutes] le jour [day] : son gain si le
  /// quota est tenu, rien sinon.
  double earnedOn(DateTime day, double minutes) =>
      minutes * 60 <= quotaFor(day) * 60 + 1e-6 ? gainFor(minutes) : 0;

  /// Ce qu'une journee au-dessus du quota a laisse passer : ce que le quota
  /// tenu tout juste aurait rapporte. Rien les jours ou il est tenu.
  ///
  /// Le montant ne grossit pas avec le depassement : une journee ratee est
  /// ratee, et une soiree perdue n'a pas a peser comme une semaine.
  double missedOn(DateTime day, double minutes) {
    final quota = quotaFor(day);
    return minutes * 60 <= quota * 60 + 1e-6 ? 0 : gainFor(quota);
  }

  /// Fige une journee terminee : quota, moyenne, gain et economie loupee ne
  /// bougeront plus.
  ScreenTimeDay close(DailyUsage usage) => ScreenTimeDay(
        usage: usage,
        quotaMinutes: quotaFor(usage.date),
        baselineMinutes: baselineMinutes ?? 0,
        amount: earnedOn(usage.date, usage.minutes),
        missed: missedOn(usage.date, usage.minutes),
      );

  ScreenTimeSettings copyWith({
    List<TrackedApp>? apps,
    double? ratePerHour,
    double? weeklyDecrease,
    int? floorMinutes,
    bool? reportEnabled,
    int? reportHour,
    int? reportMinute,
  }) =>
      ScreenTimeSettings(
        apps: apps ?? this.apps,
        ratePerHour: ratePerHour ?? this.ratePerHour,
        weeklyDecrease: weeklyDecrease ?? this.weeklyDecrease,
        floorMinutes: floorMinutes ?? this.floorMinutes,
        reportEnabled: reportEnabled ?? this.reportEnabled,
        reportHour: reportHour ?? this.reportHour,
        reportMinute: reportMinute ?? this.reportMinute,
        baselineMinutes: baselineMinutes,
        startDate: startDate,
      );

  /// Repart de zero : nouvelle moyenne, et le quota reprend a la semaine 0.
  ScreenTimeSettings startingOn(DateTime day, double baselineMinutes) => ScreenTimeSettings(
        apps: apps,
        ratePerHour: ratePerHour,
        weeklyDecrease: weeklyDecrease,
        floorMinutes: floorMinutes,
        reportEnabled: reportEnabled,
        reportHour: reportHour,
        reportMinute: reportMinute,
        baselineMinutes: baselineMinutes,
        startDate: dateOnly(day),
      );

  Map<String, dynamic> toJson() => {
        'apps': [for (final app in apps) app.toJson()],
        'rate': ratePerHour,
        'decrease': weeklyDecrease,
        'floor': floorMinutes,
        'report': reportEnabled,
        'report_hour': reportHour,
        'report_minute': reportMinute,
        if (baselineMinutes != null) 'baseline': baselineMinutes,
        if (startDate != null) 'start': dayKey(startDate!),
      };

  /// Relecture tolerante : un champ manquant ou d'un type inattendu reprend sa
  /// valeur par defaut plutot que d'empecher l'onglet de s'ouvrir.
  factory ScreenTimeSettings.fromJson(Object? raw) {
    if (raw is! Map) {
      return const ScreenTimeSettings();
    }
    const defaults = ScreenTimeSettings();
    return ScreenTimeSettings(
      apps: [
        if (raw['apps'] case final List<dynamic> list)
          for (final item in list)
            if (TrackedApp.fromJson(item) case final TrackedApp app) app,
      ],
      ratePerHour: _asDouble(raw['rate']) ?? defaults.ratePerHour,
      weeklyDecrease: _asDouble(raw['decrease']) ?? defaults.weeklyDecrease,
      floorMinutes: _asInt(raw['floor']) ?? defaults.floorMinutes,
      reportEnabled: raw['report'] is bool ? raw['report'] as bool : defaults.reportEnabled,
      reportHour: _asInt(raw['report_hour']) ?? defaults.reportHour,
      reportMinute: _asInt(raw['report_minute']) ?? defaults.reportMinute,
      baselineMinutes: _asDouble(raw['baseline']),
      startDate: parseDayKey('${raw['start']}'),
    );
  }
}

/// Une journee terminee, et ce qu'elle a rapporte.
class ScreenTimeDay {
  const ScreenTimeDay({
    required this.usage,
    required this.quotaMinutes,
    required this.baselineMinutes,
    required this.amount,
    this.missed = 0,
  });

  final DailyUsage usage;

  /// Le quota de ce jour-la.
  final double quotaMinutes;

  /// La moyenne de depart en vigueur ce jour-la.
  final double baselineMinutes;

  /// Ce que la journee a rapporte a la cagnotte, en euros. Nul au-dessus du
  /// quota.
  final double amount;

  /// Ce que la journee a laisse passer, en euros : la case « Economies
  /// loupees ». Nul sous le quota.
  final double missed;

  DateTime get date => usage.date;

  double get minutes => usage.minutes;

  /// A la seconde pres : 30 minutes et 20 secondes depassent un quota de 30.
  bool get underQuota => usage.seconds <= quotaMinutes * 60;

  /// Minutes gagnees sur la moyenne de depart, et comptees dans la
  /// cagnotte : aucune un jour au-dessus du quota.
  double get savedMinutes => underQuota ? math.max(0.0, baselineMinutes - minutes) : 0;

  Map<String, dynamic> toJson() => {
        'date': dayKey(date),
        ...usage.toJson(),
        'quota': quotaMinutes,
        'baseline': baselineMinutes,
        'amount': amount,
        if (missed > 0) 'missed': missed,
      };

  static ScreenTimeDay? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final date = parseDayKey('${raw['date']}');
    final quota = _asDouble(raw['quota']);
    final amount = _asDouble(raw['amount']);
    if (date == null || quota == null || amount == null) {
      return null;
    }
    return ScreenTimeDay(
      usage: DailyUsage.fromJson(date, raw),
      quotaMinutes: quota,
      baselineMinutes: _asDouble(raw['baseline']) ?? 0,
      amount: amount,
      // Absent des journees figees avant l'existence de la case : elles
      // gardent ce qu'elles ont rapporte.
      missed: _asDouble(raw['missed']) ?? 0,
    );
  }
}

/// Tout ce que l'onglet affiche, calcule a partir des journees et des
/// objectifs. Rien n'y est stocke.
class ScreenTimeLedger {
  factory ScreenTimeLedger({
    required ScreenTimeSettings settings,
    required Iterable<ScreenTimeDay> days,
    required Iterable<Goal> goals,
    required DateTime today,
    DailyUsage? live,
  }) {
    final sorted = [...days]..sort((a, b) => b.date.compareTo(a.date));
    final saved = roundCents(sorted.fold(0.0, (sum, day) => sum + day.amount));
    return ScreenTimeLedger._(
      settings: settings,
      days: sorted,
      book: GoalBook(goals, totalSaved: saved),
      today: dateOnly(today),
      live: live ?? DailyUsage.empty(today),
    );
  }

  ScreenTimeLedger._({
    required this.settings,
    required this.days,
    required this.book,
    required this.today,
    required this.live,
  });

  final ScreenTimeSettings settings;

  /// Les journees terminees, de la plus recente a la plus ancienne.
  final List<ScreenTimeDay> days;

  final GoalBook book;

  final DateTime today;

  /// La journee en cours, mesuree mais pas encore figee.
  final DailyUsage live;

  double get totalSaved => book.totalSaved;

  double get balance => book.balance;

  /// La case « Economies loupees » : ce que les jours au-dessus du quota ont
  /// laisse passer.
  double get totalMissed => roundCents(days.fold(0.0, (sum, day) => sum + day.missed));

  int get missedDays => days.where((day) => day.missed > 0).length;

  /// Les journees qui ont alimente la cagnotte.
  int get earningDays => days.where((day) => day.amount > 0).length;

  /// Heures gagnees sur la moyenne de depart depuis la mise en route.
  double get hoursSaved => days.fold(0.0, (sum, day) => sum + day.savedMinutes) / 60;

  double get todayQuota => settings.quotaFor(today);

  /// Le quota de la semaine prochaine : ce qui attend, pour s'y preparer.
  double get nextWeekQuota {
    final start = settings.startDate ?? today;
    final week = settings.weekOf(today);
    return settings.quotaFor(DateTime(start.year, start.month, start.day + (week + 1) * 7));
  }

  /// Ce qu'aujourd'hui rapporterait s'il s'arretait la.
  double get todayGain => settings.earnedOn(today, live.minutes);

  /// Ce qu'aujourd'hui laisserait passer s'il s'arretait la.
  double get todayMissed => settings.missedOn(today, live.minutes);

  bool get todayUnderQuota => live.seconds <= todayQuota * 60;

  ScreenTimeDay? dayOn(DateTime date) {
    final wanted = dateOnly(date);
    for (final day in days) {
      if (day.date == wanted) {
        return day;
      }
    }
    return null;
  }

  /// Journees consecutives sous le quota, en remontant depuis hier.
  ///
  /// Un jour sans mesure — le telephone n'a pas garde l'historique — rompt la
  /// serie : on ne sait pas s'il a ete tenu.
  int get streak {
    var count = 0;
    var expected = DateTime(today.year, today.month, today.day - 1);
    for (final day in days) {
      if (day.date.isAfter(expected)) {
        continue;
      }
      if (day.date != expected || !day.underQuota) {
        break;
      }
      count++;
      expected = DateTime(expected.year, expected.month, expected.day - 1);
    }
    return count;
  }

  /// Les journees terminees des [count] derniers jours.
  List<ScreenTimeDay> lastDays([int count = 7]) {
    final from = DateTime(today.year, today.month, today.day - count);
    return [for (final day in days) if (!day.date.isBefore(from)) day];
  }

  /// Moyenne quotidienne des sept derniers jours termines, en minutes. Nulle
  /// sans aucune journee mesuree.
  double? get weekAverage {
    final recent = lastDays();
    if (recent.isEmpty) {
      return null;
    }
    return recent.fold(0.0, (sum, day) => sum + day.minutes) / recent.length;
  }

  /// Ecart de la moyenne de la semaine a la moyenne de depart, en fraction :
  /// -0,25 pour un quart de temps en moins.
  double? get trend {
    final average = weekAverage;
    final baseline = settings.baselineMinutes;
    if (average == null || baseline == null || baseline <= 0) {
      return null;
    }
    return average / baseline - 1;
  }

  /// Minutes moyennes passees dans chaque heure, sur les sept derniers jours
  /// termines et aujourd'hui : les moments ou la main part toute seule.
  List<double> get hourlyProfile {
    final sources = [for (final day in lastDays()) day.usage, live];
    return [
      for (var hour = 0; hour < 24; hour++)
        sources.fold(0, (sum, usage) => sum + usage.hourly[hour]) / 60 / sources.length,
    ];
  }

  /// L'heure la plus chargee, ou nulle si rien n'a ete mesure.
  int? get peakHour {
    final profile = hourlyProfile;
    var peak = 0;
    for (var hour = 1; hour < 24; hour++) {
      if (profile[hour] > profile[peak]) {
        peak = hour;
      }
    }
    return profile[peak] > 0 ? peak : null;
  }
}
