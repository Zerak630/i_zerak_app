import 'package:flutter/material.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/commute_dao.dart' show dateOnly;
import 'package:i_zerak_app/models/sport_dao.dart';
import 'package:i_zerak_app/pages/sport/widgets/sport_ui.dart';

/// Une seance en plus du programme. Renvoie la seance, pas encore
/// enregistree.
Future<SportSession?> showNewSessionSheet(
  BuildContext context, {
  required List<Sport> sports,
  required DateTime today,
  String? sportId,
}) =>
    showModalBottomSheet<SportSession>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _NewSessionSheet(sports: sports, today: today, sportId: sportId),
    );

class _NewSessionSheet extends StatefulWidget {
  const _NewSessionSheet({required this.sports, required this.today, required this.sportId});

  final List<Sport> sports;
  final DateTime today;
  final String? sportId;

  @override
  State<_NewSessionSheet> createState() => _NewSessionSheetState();
}

class _NewSessionSheetState extends State<_NewSessionSheet> {
  late String? _sport = widget.sportId;
  late DateTime _date = widget.today;
  var _minutes = 30;

  DateTime get _yesterday => DateTime(widget.today.year, widget.today.month, widget.today.day - 1);

  Future<void> _pickDate() async {
    final chosen = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(widget.today.year - 1),
      lastDate: widget.today,
    );
    if (chosen != null) {
      setState(() => _date = dateOnly(chosen));
    }
  }

  void _submit() {
    final sport = _sport;
    if (sport == null) {
      return;
    }
    final now = DateTime.now();
    Navigator.pop(
      context,
      SportSession(
        id: 'session-${now.microsecondsSinceEpoch}',
        date: _date,
        sportId: sport,
        minutes: _minutes,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final format = SportFormat(context);
    final other = _date != widget.today && _date != _yesterday;

    return SportSheet(children: [
      Text(l10n.sport_new_session, style: theme.textTheme.titleLarge),
      const SizedBox(height: 16),
      Text(l10n.sport_which, style: theme.textTheme.labelLarge),
      const SizedBox(height: 8),
      SportChooser(
        sports: widget.sports,
        selected: _sport,
        onSelected: (id) => setState(() => _sport = id),
      ),
      const SizedBox(height: 18),
      Text(l10n.sport_when, style: theme.textTheme.labelLarge),
      const SizedBox(height: 8),
      Wrap(spacing: 8, children: [
        ChoiceChip(
          label: Text(l10n.sport_today),
          selected: _date == widget.today,
          onSelected: (_) => setState(() => _date = widget.today),
        ),
        ChoiceChip(
          label: Text(l10n.sport_yesterday),
          selected: _date == _yesterday,
          onSelected: (_) => setState(() => _date = _yesterday),
        ),
        ChoiceChip(
          avatar: const Icon(Icons.event, size: 18),
          label: Text(other ? format.shortDay(_date) : l10n.sport_other_day),
          selected: other,
          onSelected: (_) => _pickDate(),
        ),
      ]),
      const SizedBox(height: 18),
      Text(l10n.sport_duration, style: theme.textTheme.labelLarge),
      const SizedBox(height: 8),
      MinutesPicker(minutes: _minutes, onChanged: (minutes) => setState(() => _minutes = minutes)),
      const SizedBox(height: 20),
      Row(children: [
        Expanded(
          child: TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: FilledButton(
            onPressed: _sport == null ? null : _submit,
            child: Text(l10n.sport_save_session),
          ),
        ),
      ]),
    ]);
  }
}

/// Ce qu'on dit d'un creneau du programme.
sealed class SlotAnswer {
  const SlotAnswer();
}

class SlotDone extends SlotAnswer {
  const SlotDone(this.minutes, {required this.on});

  final int minutes;

  /// Le jour ou la seance a eu lieu : celui du creneau, ou un autre de la
  /// meme semaine quand on l'a decalee.
  final DateTime on;
}

class SlotSkipped extends SlotAnswer {
  const SlotSkipped();
}

/// Retire ce qui avait ete saisi : le creneau redevient a saisir.
class SlotCleared extends SlotAnswer {
  const SlotCleared();
}

/// La saisie d'un creneau : fait, combien de temps, ou pas fait.
Future<SlotAnswer?> showSlotSheet(
  BuildContext context, {
  required WeekSlot slot,
  required Sport? sport,
}) =>
    showModalBottomSheet<SlotAnswer>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _SlotSheet(slot: slot, sport: sport),
    );

class _SlotSheet extends StatefulWidget {
  const _SlotSheet({required this.slot, required this.sport});

  final WeekSlot slot;
  final Sport? sport;

  @override
  State<_SlotSheet> createState() => _SlotSheetState();
}

class _SlotSheetState extends State<_SlotSheet> {
  late int _minutes = (widget.slot.session?.done ?? false)
      ? widget.slot.session!.minutes
      : widget.slot.slot.minutes;

  /// Le jour de la seance : celui du creneau, sauf si elle a deja ete
  /// saisie decalee, ou si le creneau n'est pas encore arrive — une seance
  /// avancee s'est faite au plus tard aujourd'hui.
  late DateTime _on = (widget.slot.session?.done ?? false)
      ? widget.slot.session!.date
      : (widget.slot.date.isAfter(widget.slot.today) ? widget.slot.today : widget.slot.date);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = SportFormat(context);
    final answered = widget.slot.session != null;
    final monday = weekStart(widget.slot.date);
    final today = widget.slot.today;

    return SportSheet(children: [
      Row(children: [
        SportAvatar(sport: widget.sport, color: scheme.primary, size: 44),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(sportLabel(l10n, widget.sport), style: theme.textTheme.titleLarge),
            Text(
              l10n.sport_slot_planned(format.shortDay(widget.slot.date),
                  sportMinutes(l10n, widget.slot.slot.minutes)),
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ]),
        ),
      ]),
      const SizedBox(height: 18),
      Text(l10n.sport_slot_which_day, style: theme.textTheme.labelLarge),
      const SizedBox(height: 8),
      // Les jours de la semaine du creneau, jusqu'a aujourd'hui : une
      // seance decalee se fait la meme semaine, et pas encore demain.
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (var day = DateTime.monday; day <= DateTime.sunday; day++)
          if (dayOfWeek(monday, day) case final date when !date.isAfter(today))
            ChoiceChip(
              label: Text(format.weekdayDay(date)),
              selected: _on == date,
              onSelected: (_) => setState(() => _on = date),
            ),
      ]),
      const SizedBox(height: 18),
      Text(l10n.sport_slot_how_long, style: theme.textTheme.labelLarge),
      const SizedBox(height: 8),
      MinutesPicker(minutes: _minutes, onChanged: (minutes) => setState(() => _minutes = minutes)),
      const SizedBox(height: 20),
      FilledButton.icon(
        onPressed: () => Navigator.pop(context, SlotDone(_minutes, on: _on)),
        icon: const Icon(Icons.check),
        label: Text(l10n.sport_slot_done(sportMinutes(l10n, _minutes))),
      ),
      const SizedBox(height: 8),
      OutlinedButton(
        onPressed: () => Navigator.pop(context, const SlotSkipped()),
        child: Text(l10n.sport_slot_skip),
      ),
      if (answered)
        TextButton(
          onPressed: () => Navigator.pop(context, const SlotCleared()),
          child: Text(l10n.sport_slot_clear),
        ),
    ]);
  }
}

/// Un creneau du programme, nouveau ou modifie. Renvoie le creneau.
Future<PlannedSlot?> showSlotEditor(
  BuildContext context, {
  required List<Sport> sports,
  PlannedSlot? slot,
}) =>
    showModalBottomSheet<PlannedSlot>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _SlotEditor(sports: sports, slot: slot),
    );

class _SlotEditor extends StatefulWidget {
  const _SlotEditor({required this.sports, required this.slot});

  final List<Sport> sports;
  final PlannedSlot? slot;

  @override
  State<_SlotEditor> createState() => _SlotEditorState();
}

class _SlotEditorState extends State<_SlotEditor> {
  late String? _sport = widget.slot?.sportId;
  late int _weekday = widget.slot?.weekday ?? DateTime.monday;
  late int _minutes = widget.slot?.minutes ?? 30;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final format = SportFormat(context);

    return SportSheet(children: [
      Text(widget.slot == null ? l10n.sport_plan_add : l10n.sport_plan_edit,
          style: theme.textTheme.titleLarge),
      const SizedBox(height: 16),
      Text(l10n.sport_which, style: theme.textTheme.labelLarge),
      const SizedBox(height: 8),
      SportChooser(
        sports: widget.sports,
        selected: _sport,
        onSelected: (id) => setState(() => _sport = id),
      ),
      const SizedBox(height: 18),
      Text(l10n.sport_plan_day, style: theme.textTheme.labelLarge),
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (var day = DateTime.monday; day <= DateTime.sunday; day++)
          ChoiceChip(
            label: Text(format.weekdayShort(day)),
            selected: _weekday == day,
            onSelected: (_) => setState(() => _weekday = day),
          ),
      ]),
      const SizedBox(height: 18),
      Text(l10n.sport_duration, style: theme.textTheme.labelLarge),
      const SizedBox(height: 8),
      MinutesPicker(minutes: _minutes, onChanged: (minutes) => setState(() => _minutes = minutes)),
      const SizedBox(height: 20),
      Row(children: [
        Expanded(
          child: TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: FilledButton(
            onPressed: _sport == null
                ? null
                : () => Navigator.pop(
                      context,
                      PlannedSlot(
                        id: widget.slot?.id ?? 'slot-${DateTime.now().microsecondsSinceEpoch}',
                        sportId: _sport!,
                        weekday: _weekday,
                        minutes: _minutes,
                      ),
                    ),
            child: Text(l10n.save),
          ),
        ),
      ]),
    ]);
  }
}

/// Ce que la feuille d'un sport decide.
sealed class SportEdit {
  const SportEdit();
}

/// Le sport, nouveau ou modifie, a enregistrer.
class SportSaved extends SportEdit {
  const SportSaved(this.sport);

  final Sport sport;
}

/// Le sport a supprimer.
class SportDeleted extends SportEdit {
  const SportDeleted();
}

/// Un sport, nouveau ou a modifier : son nom, son icone, et sa suppression
/// tant que rien ne l'utilise.
Future<SportEdit?> showSportEditor(
  BuildContext context, {
  Sport? sport,
  SportUsage usage = const SportUsage(sessions: 0, slots: 0),
}) =>
    showModalBottomSheet<SportEdit>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _SportEditor(sport: sport, usage: usage),
    );

class _SportEditor extends StatefulWidget {
  const _SportEditor({required this.sport, required this.usage});

  final Sport? sport;
  final SportUsage usage;

  @override
  State<_SportEditor> createState() => _SportEditorState();
}

class _SportEditorState extends State<_SportEditor> {
  final _name = TextEditingController();
  late var _icon = widget.sport?.icon ?? SportIcon.other;

  /// Le nom traduit d'un sport livre : le garder tel quel laisse le libelle
  /// nul, et le sport suit la langue de l'application.
  String? _builtInName;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final sport = widget.sport;
    if (sport != null && _builtInName == null && _name.text.isEmpty) {
      final l10n = AppLocalizations.of(context)!;
      _builtInName = sport.isBuiltIn ? sportLabel(l10n, Sport(id: sport.id, icon: sport.icon)) : null;
      _name.text = sportLabel(l10n, sport);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    final sport = widget.sport;
    Navigator.pop(
      context,
      SportSaved(Sport(
        id: sport?.id ?? 'sport-${DateTime.now().microsecondsSinceEpoch}',
        label: name == _builtInName ? null : name,
        icon: _icon,
      )),
    );
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.sport_delete_sport),
        content: Text(l10n.delete_confirm(_name.text.trim())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.delete)),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      Navigator.pop(context, const SportDeleted());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = _name.text.trim();
    final editing = widget.sport != null;
    final usage = widget.usage;

    return SportSheet(children: [
      Text(editing ? l10n.sport_edit_sport : l10n.sport_add_sport, style: theme.textTheme.titleLarge),
      const SizedBox(height: 16),
      TextField(
        controller: _name,
        autofocus: !editing,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: l10n.goal_name, border: const OutlineInputBorder()),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 16),
      Text(l10n.goal_icon, style: theme.textTheme.labelLarge),
      const SizedBox(height: 8),
      Wrap(spacing: 10, runSpacing: 10, children: [
        for (final icon in SportIcon.values)
          IconButton(
            key: ValueKey('sport-icon-${icon.name}'),
            isSelected: _icon == icon,
            style: IconButton.styleFrom(
              fixedSize: const Size.square(48),
              backgroundColor: _icon == icon ? scheme.primaryContainer : null,
              side: BorderSide(
                color: _icon == icon ? scheme.primary : scheme.outlineVariant,
                width: _icon == icon ? 2 : 1,
              ),
            ),
            icon: Icon(sportIconData(icon)),
            onPressed: () => setState(() => _icon = icon),
          ),
      ]),
      const SizedBox(height: 20),
      FilledButton(onPressed: name.isEmpty ? null : _save, child: Text(l10n.save)),
      if (editing) ...[
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: usage.inUse ? null : _delete,
          icon: const Icon(Icons.delete_outline),
          label: Text(l10n.sport_delete_sport),
          style: TextButton.styleFrom(foregroundColor: scheme.error),
        ),
        if (usage.inUse)
          Text(
            l10n.sport_in_use(
              [
                if (usage.sessions > 0) l10n.sport_sessions_short(usage.sessions),
                if (usage.slots > 0) l10n.sport_slots_short(usage.slots),
              ].join(' · '),
            ),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
      ],
    ]);
  }
}
