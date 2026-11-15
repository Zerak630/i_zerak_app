/// Le sport a la maison : des sports, un programme de la semaine, et les
/// seances faites.
///
/// Dart pur, comme `commute_dao.dart` : semaines, totaux et series se testent
/// avec `package:test`, sans widgets.
///
/// Tout se compte en temps, jamais en euros : une seance de gainage
/// n'economise rien, et lui inventer un prix ne motiverait pas longtemps.
///
/// Le programme ne cree rien tout seul. Chaque semaine, ses creneaux
/// attendent qu'on dise s'ils ont ete faits — c'est la saisie manuelle qui
/// fait l'habitude, pas un compteur qui tourne dans le dos.
library;

import 'package:i_zerak_app/models/commute_dao.dart' show dateOnly, dayKey, parseDayKey;

String? _asString(Object? raw) => raw is String ? raw : null;

int? _asInt(Object? raw) => raw is num ? raw.toInt() : null;

/// Le lundi de la semaine qui contient [day].
///
/// Arithmetique par composants : soustraire des `Duration` decalerait d'une
/// heure au changement d'heure, et `dateOnly` ramenerait au dimanche.
DateTime weekStart(DateTime day) => DateTime(day.year, day.month, day.day - (day.weekday - 1));

/// Le jour [weekday] (1 pour lundi) de la semaine qui commence le [monday].
DateTime dayOfWeek(DateTime monday, int weekday) =>
    DateTime(monday.year, monday.month, monday.day + weekday - 1);

/// Icones proposees pour un sport. Le nom est la cle de persistance : on
/// peut reordonner la liste, jamais renommer une valeur.
enum SportIcon {
  strength,
  run,
  yoga,
  stretch,
  gymnastics,
  bike,
  walk,
  hiking,
  swim,
  rowing,
  dance,
  boxing,
  martialArts,
  racket,
  football,
  basketball,
  volleyball,
  handball,
  rugby,
  hockey,
  golf,
  ski,
  skate,
  surf,
  other;

  static SportIcon fromName(String? raw) =>
      values.firstWhere((icon) => icon.name == raw, orElse: () => other);
}

/// Un sport pratique. Ceux livres ont un identifiant fixe et un libelle nul :
/// leur nom vient des traductions, comme les raisons de prendre la voiture.
class Sport {
  const Sport({required this.id, this.label, required this.icon, this.hidden = false});

  final String id;

  /// Nul pour un sport livre qui n'a pas ete renomme.
  final String? label;

  final SportIcon icon;

  /// Vrai pour un sport livre qu'on a supprime : il ne peut pas sortir de
  /// `defaults`, alors on garde sa trace pour ne plus le proposer.
  final bool hidden;

  static const String strength = 'strength';
  static const String cardio = 'cardio';
  static const String yoga = 'yoga';
  static const String stretching = 'stretching';
  static const String running = 'running';

  /// Ce qui se fait le plus souvent a la maison, ou juste devant.
  static const List<Sport> defaults = [
    Sport(id: strength, icon: SportIcon.strength),
    Sport(id: cardio, icon: SportIcon.boxing),
    Sport(id: yoga, icon: SportIcon.yoga),
    Sport(id: stretching, icon: SportIcon.stretch),
    Sport(id: running, icon: SportIcon.run),
  ];

  bool get isBuiltIn => defaults.any((sport) => sport.id == id);

  Map<String, dynamic> toJson() => {
        'id': id,
        if (label != null) 'label': label,
        'icon': icon.name,
        if (hidden) 'hidden': true,
      };

  static Sport? fromJson(Object? raw) {
    if (raw is! Map || raw['id'] is! String) {
      return null;
    }
    return Sport(
      id: raw['id'] as String,
      label: _asString(raw['label']),
      icon: SportIcon.fromName(_asString(raw['icon'])),
      hidden: raw['hidden'] == true,
    );
  }
}

/// Ce qui renvoie encore a un sport. Un sport utilise ne se supprime pas :
/// ses seances et ses creneaux perdraient leur nom.
class SportUsage {
  const SportUsage({required this.sessions, required this.slots});

  /// Seances saisies, creneaux dits « pas faits » compris.
  final int sessions;

  /// Creneaux du programme.
  final int slots;

  bool get inUse => sessions > 0 || slots > 0;

  static SportUsage of(
    String sportId, {
    required Iterable<PlannedSlot> plan,
    required Iterable<SportSession> sessions,
  }) =>
      SportUsage(
        sessions: sessions.where((session) => session.sportId == sportId).length,
        slots: plan.where((slot) => slot.sportId == sportId).length,
      );
}

/// Un creneau du programme : tel sport, tel jour de la semaine, tant de
/// minutes.
class PlannedSlot {
  const PlannedSlot({
    required this.id,
    required this.sportId,
    required this.weekday,
    required this.minutes,
  });

  final String id;
  final String sportId;

  /// 1 pour lundi, 7 pour dimanche, comme `DateTime.weekday`.
  final int weekday;

  /// La duree prevue : c'est elle que propose la saisie, modifiable.
  final int minutes;

  Map<String, dynamic> toJson() => {
        'id': id,
        'sport': sportId,
        'weekday': weekday,
        'minutes': minutes,
      };

  static PlannedSlot? fromJson(Object? raw) {
    if (raw is! Map || raw['id'] is! String || raw['sport'] is! String) {
      return null;
    }
    final weekday = _asInt(raw['weekday']);
    final minutes = _asInt(raw['minutes']);
    if (weekday == null || weekday < 1 || weekday > 7 || minutes == null || minutes <= 0) {
      return null;
    }
    return PlannedSlot(
      id: raw['id'] as String,
      sportId: raw['sport'] as String,
      weekday: weekday,
      minutes: minutes,
    );
  }
}

/// Une seance faite — ou un creneau du programme qu'on a dit ne pas avoir
/// fait.
class SportSession {
  const SportSession({
    required this.id,
    required this.date,
    required this.sportId,
    required this.minutes,
    this.slotId,
    this.skipped = false,
    this.plannedDate,
  });

  /// Une seance faite pour le creneau [slot] du jour [date]. Son identifiant
  /// est fixe : saisir de nouveau le meme creneau le remplace, sur cet
  /// appareil comme apres une synchro.
  ///
  /// [on] dit le jour ou elle a vraiment eu lieu, quand on l'a decalee —
  /// la piscine du mardi faite le jeudi. Le creneau du mardi est rempli, et
  /// le temps compte le jeudi.
  factory SportSession.forSlot(PlannedSlot slot, DateTime date, {required int minutes, DateTime? on}) {
    final planned = dateOnly(date);
    final actual = on == null ? planned : dateOnly(on);
    return SportSession(
      id: slotSessionId(slot, planned),
      date: actual,
      sportId: slot.sportId,
      minutes: minutes,
      slotId: slot.id,
      plannedDate: actual == planned ? null : planned,
    );
  }

  /// Un creneau qu'on dit ne pas avoir fait : il sort de la liste « a
  /// saisir », sans rien compter.
  factory SportSession.skipped(PlannedSlot slot, DateTime date) => SportSession(
        id: slotSessionId(slot, date),
        date: dateOnly(date),
        sportId: slot.sportId,
        minutes: 0,
        slotId: slot.id,
        skipped: true,
      );

  static String slotSessionId(PlannedSlot slot, DateTime date) => 'slot-${slot.id}-${dayKey(date)}';

  final String id;
  final DateTime date;
  final String sportId;
  final int minutes;

  /// Le creneau du programme que la seance remplit. Nul pour une seance en
  /// plus.
  final String? slotId;

  /// Vrai pour un creneau dit « pas fait ».
  final bool skipped;

  /// Le jour du creneau, quand la seance a ete decalee a [date]. Nul sinon.
  final DateTime? plannedDate;

  /// Le jour du creneau que la seance remplit.
  DateTime get slotDay => plannedDate ?? date;

  /// Vrai pour un creneau fait un autre jour que prevu.
  bool get moved => plannedDate != null;

  bool get done => !skipped && minutes > 0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': dayKey(date),
        'sport': sportId,
        'minutes': minutes,
        if (slotId != null) 'slot': slotId,
        if (skipped) 'skipped': true,
        if (plannedDate != null) 'planned': dayKey(plannedDate!),
      };

  static SportSession? fromJson(Object? raw) {
    if (raw is! Map || raw['id'] is! String || raw['sport'] is! String) {
      return null;
    }
    final date = parseDayKey('${raw['date']}');
    final minutes = _asInt(raw['minutes']);
    if (date == null || minutes == null || minutes < 0) {
      return null;
    }
    return SportSession(
      id: raw['id'] as String,
      date: date,
      sportId: raw['sport'] as String,
      minutes: minutes,
      slotId: _asString(raw['slot']),
      skipped: raw['skipped'] == true,
      plannedDate: raw['planned'] == null ? null : parseDayKey('${raw['planned']}'),
    );
  }
}

/// Ou en est un creneau du programme, une semaine donnee.
enum SlotStatus {
  /// Fait : une seance le remplit.
  done,

  /// Dit « pas fait ».
  skipped,

  /// Passe, et rien de saisi : il attend qu'on dise ce qu'il en a ete.
  pending,

  /// Pas encore arrive.
  upcoming,
}

/// Un creneau du programme pose sur une date.
class WeekSlot {
  const WeekSlot({required this.slot, required this.date, required this.session, required this.today});

  final PlannedSlot slot;
  final DateTime date;

  /// La seance saisie pour ce creneau, faite ou non.
  final SportSession? session;

  final DateTime today;

  SlotStatus get status {
    final session = this.session;
    if (session != null) {
      return session.skipped ? SlotStatus.skipped : SlotStatus.done;
    }
    // Le jour meme, le creneau est deja a saisir : on le remplit souvent
    // juste apres la seance.
    return date.isAfter(today) ? SlotStatus.upcoming : SlotStatus.pending;
  }
}

/// Le temps passe sur un sport, sur une periode.
class SportTotal {
  const SportTotal({required this.sportId, required this.minutes, required this.sessions});

  final String sportId;
  final int minutes;
  final int sessions;
}

/// Une semaine et ce qu'elle a donne.
class WeekSummary {
  const WeekSummary({
    required this.monday,
    required this.minutes,
    required this.sessions,
    required this.planned,
    required this.plannedDone,
    required this.perDay,
  });

  final DateTime monday;
  final int minutes;

  /// Les seances faites, creneaux du programme et seances en plus.
  final int sessions;

  /// Les creneaux du programme cette semaine-la, et ceux qui ont ete faits.
  final int planned;
  final int plannedDone;

  /// Minutes par jour, du lundi au dimanche.
  final List<int> perDay;

  /// Tout le programme fait, ou au moins une seance sans programme.
  bool get kept => planned > 0 ? plannedDone >= planned : sessions > 0;
}

/// Tout ce que l'onglet affiche, calcule a partir des seances et du
/// programme. Rien n'y est stocke.
class SportLedger {
  SportLedger({
    required Iterable<Sport> sports,
    required Iterable<PlannedSlot> plan,
    required Iterable<SportSession> sessions,
    required DateTime today,
  })  : sports = [...sports],
        plan = [...plan]..sort((a, b) {
            final byDay = a.weekday.compareTo(b.weekday);
            return byDay != 0 ? byDay : a.id.compareTo(b.id);
          }),
        sessions = [...sessions]..sort((a, b) {
            final byDate = b.date.compareTo(a.date);
            return byDate != 0 ? byDate : b.id.compareTo(a.id);
          }),
        today = dateOnly(today);

  /// Les sports livres d'abord, puis ceux ajoutes ; un sport livre renomme
  /// est remplace par sa version enregistree.
  final List<Sport> sports;

  /// Du lundi au dimanche.
  final List<PlannedSlot> plan;

  /// De la plus recente a la plus ancienne, creneaux dits « pas faits »
  /// compris.
  final List<SportSession> sessions;

  final DateTime today;

  Sport? sportById(String id) {
    for (final sport in sports) {
      if (sport.id == id) {
        return sport;
      }
    }
    return null;
  }

  /// Les seances vraiment faites.
  Iterable<SportSession> get done => sessions.where((session) => session.done);

  Iterable<SportSession> doneBetween(DateTime from, DateTime to) {
    final start = dateOnly(from);
    final end = dateOnly(to);
    return done.where((session) => !session.date.isBefore(start) && !session.date.isAfter(end));
  }

  int minutesBetween(DateTime from, DateTime to) =>
      doneBetween(from, to).fold(0, (sum, session) => sum + session.minutes);

  /// Les creneaux du programme de la semaine qui commence le [monday].
  ///
  /// Le programme d'aujourd'hui sert pour toutes les semaines : il n'est pas
  /// date. Un creneau supprime disparait donc aussi des semaines passees,
  /// mais les seances qu'il a recues restent comptees.
  List<WeekSlot> slotsOf(DateTime monday) {
    final start = weekStart(monday);
    // Par le jour du creneau, pas celui de la seance : la piscine du mardi
    // faite le jeudi remplit le creneau du mardi.
    final bySlot = <String, SportSession>{
      for (final session in sessions)
        if (session.slotId != null && !session.slotDay.isBefore(start) &&
            session.slotDay.isBefore(dayOfWeek(start, 8)))
          '${session.slotId}|${dayKey(session.slotDay)}': session,
    };
    return [
      for (final slot in plan)
        WeekSlot(
          slot: slot,
          date: dayOfWeek(start, slot.weekday),
          session: bySlot['${slot.id}|${dayKey(dayOfWeek(start, slot.weekday))}'],
          today: today,
        ),
    ];
  }

  /// Les seances en plus du programme, cette semaine-la.
  List<SportSession> extrasOf(DateTime monday) {
    final start = weekStart(monday);
    return [
      for (final session in doneBetween(start, dayOfWeek(start, 7)))
        if (session.slotId == null) session,
    ];
  }

  WeekSummary weekOf(DateTime monday) {
    final start = weekStart(monday);
    final perDay = List<int>.filled(7, 0);
    var sessions = 0;
    for (final session in doneBetween(start, dayOfWeek(start, 7))) {
      perDay[session.date.weekday - 1] += session.minutes;
      sessions++;
    }
    final slots = slotsOf(start);
    return WeekSummary(
      monday: start,
      minutes: perDay.fold(0, (sum, minutes) => sum + minutes),
      sessions: sessions,
      planned: slots.length,
      plannedDone: slots.where((slot) => slot.status == SlotStatus.done).length,
      perDay: perDay,
    );
  }

  /// Les creneaux passes de la semaine en cours et de la precedente qui
  /// attendent d'etre saisis : ce qu'on oublie le plus facilement.
  List<WeekSlot> get pending {
    final current = weekStart(today);
    final previous = DateTime(current.year, current.month, current.day - 7);
    return [
      for (final slot in [...slotsOf(previous), ...slotsOf(current)])
        if (slot.status == SlotStatus.pending) slot,
    ];
  }

  /// Le temps par sport de [from] a [to] inclus, ou depuis le debut, du plus
  /// pratique au moins pratique.
  List<SportTotal> totalsBySport({DateTime? from, DateTime? to}) {
    final minutes = <String, int>{};
    final counts = <String, int>{};
    final source = from == null ? done : doneBetween(from, to ?? today);
    for (final session in source) {
      minutes[session.sportId] = (minutes[session.sportId] ?? 0) + session.minutes;
      counts[session.sportId] = (counts[session.sportId] ?? 0) + 1;
    }
    return [
      for (final id in minutes.keys)
        SportTotal(sportId: id, minutes: minutes[id]!, sessions: counts[id]!),
    ]..sort((a, b) => b.minutes.compareTo(a.minutes));
  }

  /// Semaines tenues d'affilee, en remontant depuis la derniere semaine
  /// terminee — et la semaine en cours si elle est deja tenue.
  ///
  /// Une semaine se tient en faisant tout son programme, ou, sans programme,
  /// une seance au moins. Une semaine pas encore finie ne rompt rien : il
  /// reste des jours pour la tenir.
  int get weekStreak {
    final current = weekStart(today);
    var count = weekOf(current).kept ? 1 : 0;
    var monday = DateTime(current.year, current.month, current.day - 7);
    final first = _firstActivity;
    while (first != null && !monday.isBefore(weekStart(first))) {
      if (!weekOf(monday).kept) {
        break;
      }
      count++;
      monday = DateTime(monday.year, monday.month, monday.day - 7);
    }
    return count;
  }

  DateTime? get _firstActivity {
    DateTime? first;
    for (final session in done) {
      if (first == null || session.date.isBefore(first)) {
        first = session.date;
      }
    }
    return first;
  }
}
