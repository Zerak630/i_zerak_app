import 'package:i_zerak_app/models/sport_dao.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_sport.dart';
import 'package:test/test.dart';

const _yoga = PlannedSlot(id: 'y', sportId: Sport.yoga, weekday: DateTime.monday, minutes: 30);
const _strength = PlannedSlot(id: 'r', sportId: Sport.strength, weekday: DateTime.thursday, minutes: 20);

SportSession _extra(DateTime date, int minutes, {String sport = Sport.running}) => SportSession(
      id: 'x-${date.toIso8601String()}-$sport',
      date: date,
      sportId: sport,
      minutes: minutes,
    );

void main() {
  // Mercredi 18 novembre 2026.
  final today = DateTime(2026, 11, 18);
  final monday = DateTime(2026, 11, 16);

  SportLedger ledger(List<SportSession> sessions, {List<PlannedSlot> plan = const [_yoga, _strength]}) =>
      SportLedger(sports: Sport.defaults, plan: plan, sessions: sessions, today: today);

  test('la semaine commence le lundi, meme au changement d heure', () {
    expect(weekStart(DateTime(2026, 11, 18, 23)), monday);
    expect(weekStart(DateTime(2026, 11, 16)), monday);
    expect(weekStart(DateTime(2026, 11, 22)), monday);
    // Dimanche 25 octobre 2026 : passage a l'heure d'hiver.
    expect(weekStart(DateTime(2026, 10, 25)), DateTime(2026, 10, 19));
    expect(dayOfWeek(monday, DateTime.sunday), DateTime(2026, 11, 22));
  });

  group('programme de la semaine', () {
    test('chaque creneau tombe sur son jour, et dit ou il en est', () {
      final slots = ledger([]).slotsOf(today);

      expect(slots.map((slot) => slot.date), [DateTime(2026, 11, 16), DateTime(2026, 11, 19)]);
      expect(slots.map((slot) => slot.status), [SlotStatus.pending, SlotStatus.upcoming]);
    });

    test('un creneau saisi est fait, ou dit pas fait', () {
      final done = ledger([SportSession.forSlot(_yoga, monday, minutes: 35)]).slotsOf(today);
      expect(done.first.status, SlotStatus.done);
      expect(done.first.session!.minutes, 35);

      final skipped = ledger([SportSession.skipped(_yoga, monday)]).slotsOf(today);
      expect(skipped.first.status, SlotStatus.skipped);
    });

    test('un creneau decale remplit son jour, et le temps compte le jour fait', () {
      // Le yoga du lundi 16, fait le mercredi 18.
      final moved = SportSession.forSlot(_yoga, monday, minutes: 40, on: today);
      final week = ledger([moved]);

      final slot = week.slotsOf(today).first;
      expect(slot.status, SlotStatus.done);
      expect(slot.session!.moved, isTrue);
      expect(week.weekOf(monday).perDay, [0, 0, 40, 0, 0, 0, 0]);
      expect(week.extrasOf(monday), isEmpty);
      expect(week.pending, hasLength(2), reason: 'seulement les creneaux de la semaine derniere');

      // Meme identifiant que sans decalage : le redire le remplace.
      expect(moved.id, SportSession.forSlot(_yoga, monday, minutes: 30).id);
      final read = SportSession.fromJson(moved.toJson())!;
      expect((read.date, read.slotDay, read.moved), (today, monday, true));
      expect(SportSession.forSlot(_yoga, monday, minutes: 30, on: monday).moved, isFalse);
    });

    test('un creneau avance a la semaine d avant ne deborde pas sur la suivante', () {
      // Le jeudi 19 fait des le mercredi 18 : toujours dans la semaine.
      final early = SportSession.forSlot(_strength, DateTime(2026, 11, 19), minutes: 20, on: today);
      final slots = ledger([early]).slotsOf(today);
      expect(slots.last.status, SlotStatus.done);
      expect(ledger([early]).slotsOf(DateTime(2026, 11, 23)).last.session, isNull);
    });

    test('saisir de nouveau le meme creneau le remplace', () {
      final first = SportSession.forSlot(_yoga, monday, minutes: 30);
      final again = SportSession.skipped(_yoga, monday);
      expect(again.id, first.id);
    });

    test('les creneaux oublies de cette semaine et de la precedente attendent', () {
      final pending = ledger([SportSession.forSlot(_yoga, monday, minutes: 30)]).pending;

      // La semaine derniere : lundi 9 et jeudi 12. Cette semaine : lundi fait,
      // jeudi pas encore arrive.
      expect(pending.map((slot) => slot.date), [DateTime(2026, 11, 9), DateTime(2026, 11, 12)]);
    });
  });

  group('totaux', () {
    final sessions = [
      SportSession.forSlot(_yoga, monday, minutes: 30),
      SportSession.skipped(_strength, DateTime(2026, 11, 12)),
      _extra(DateTime(2026, 11, 17), 25),
      _extra(DateTime(2026, 11, 10), 40),
      _extra(DateTime(2026, 10, 2), 15, sport: Sport.yoga),
    ];

    test('la semaine : minutes, seances, programme tenu et jour par jour', () {
      final week = ledger(sessions).weekOf(today);

      expect(week.minutes, 55);
      expect(week.sessions, 2);
      expect(week.planned, 2);
      expect(week.plannedDone, 1);
      expect(week.perDay, [30, 25, 0, 0, 0, 0, 0]);
      expect(week.kept, isFalse);
      expect(ledger(sessions).extrasOf(today).single.minutes, 25);
    });

    test('un creneau dit pas fait ne compte ni en temps ni en seance', () {
      final week = ledger(sessions).weekOf(DateTime(2026, 11, 9));
      expect(week.minutes, 40);
      expect(week.sessions, 1);
      expect(week.plannedDone, 0);
    });

    test('le temps par sport, sur une periode ou depuis le debut', () {
      final all = ledger(sessions).totalsBySport();
      expect(all.map((total) => total.sportId), [Sport.running, Sport.yoga]);
      expect(all.first.minutes, 65);
      expect(all.last.sessions, 2);

      final month = ledger(sessions).totalsBySport(from: DateTime(2026, 11, 1), to: today);
      expect(month.map((total) => (total.sportId, total.minutes)),
          [(Sport.running, 65), (Sport.yoga, 30)]);
    });
  });

  group('serie de semaines', () {
    test('sans programme, une seance par semaine suffit', () {
      final streak = ledger([
        _extra(DateTime(2026, 11, 3), 20),
        _extra(DateTime(2026, 11, 10), 20),
      ], plan: const []).weekStreak;
      // Semaine en cours pas encore tenue : elle ne compte pas, mais ne rompt
      // rien.
      expect(streak, 2);
    });

    test('avec un programme, il faut le faire en entier', () {
      final lastWeek = DateTime(2026, 11, 9);
      final full = ledger([
        SportSession.forSlot(_yoga, lastWeek, minutes: 30),
        SportSession.forSlot(_strength, DateTime(2026, 11, 12), minutes: 20),
      ]).weekStreak;
      expect(full, 1);

      final half = ledger([SportSession.forSlot(_yoga, lastWeek, minutes: 30)]).weekStreak;
      expect(half, 0);
    });

    test('la semaine en cours compte des qu elle est tenue', () {
      final streak = ledger([
        SportSession.forSlot(_yoga, monday, minutes: 30),
        SportSession.forSlot(_strength, DateTime(2026, 11, 19), minutes: 20),
      ]).weekStreak;
      expect(streak, 1);
    });
  });

  group('persistance', () {
    test('sport, creneau et seance se relisent a l identique', () {
      const sport = Sport(id: 'escalade', label: 'Escalade', icon: SportIcon.other);
      expect(Sport.fromJson(sport.toJson())!.label, 'Escalade');

      final slot = PlannedSlot.fromJson(_yoga.toJson())!;
      expect((slot.sportId, slot.weekday, slot.minutes), (Sport.yoga, 1, 30));

      final session = SportSession.fromJson(SportSession.skipped(_yoga, monday).toJson())!;
      expect(session.skipped, isTrue);
      expect(session.slotId, 'y');
      expect(session.date, monday);
    });

    test('une entree abimee est ignoree', () {
      expect(PlannedSlot.fromJson({'id': 'a', 'sport': 'yoga', 'weekday': 9, 'minutes': 20}), isNull);
      expect(SportSession.fromJson({'id': 'a', 'sport': 'yoga', 'date': 'hier', 'minutes': 20}), isNull);
      expect(Sport.fromJson({'label': 'sans id'}), isNull);
    });

    test('un sport livre renomme garde sa place, un sport ajoute vient apres', () {
      final sports = mergeSports([
        const Sport(id: 'escalade', label: 'Escalade', icon: SportIcon.other),
        const Sport(id: Sport.cardio, label: 'HIIT', icon: SportIcon.boxing),
      ]);
      expect(sports.map((sport) => sport.id).toList(),
          [...Sport.defaults.map((sport) => sport.id), 'escalade']);
      expect(sports[1].label, 'HIIT');
    });

    test('un sport livre masque ne revient pas, et le masque se relit', () {
      final hidden = Sport.fromJson(hiddenSport(Sport.defaults.first).toJson())!;
      expect(hidden.hidden, isTrue);
      final sports = mergeSports([hidden]);
      expect(sports.map((sport) => sport.id), isNot(contains(Sport.strength)));
      expect(sports, hasLength(Sport.defaults.length - 1));
    });

    test('une icone inconnue retombe sur « autre », les nouvelles se relisent', () {
      expect(SportIcon.fromName('trampoline'), SportIcon.other);
      const sport = Sport(id: 'padel', label: 'Padel', icon: SportIcon.racket);
      expect(Sport.fromJson(sport.toJson())!.icon, SportIcon.racket);
    });
  });

  group('usage', () {
    test('un sport sert tant qu une seance ou un creneau le cite', () {
      final usage = SportUsage.of(
        Sport.yoga,
        plan: [_yoga],
        sessions: [
          SportSession.forSlot(_yoga, monday, minutes: 30),
          SportSession.skipped(_yoga, DateTime(2026, 11, 9)),
        ],
      );
      expect((usage.sessions, usage.slots, usage.inUse), (2, 1, true));
      expect(SportUsage.of('escalade', plan: [_yoga], sessions: const []).inUse, isFalse);
    });
  });
}
