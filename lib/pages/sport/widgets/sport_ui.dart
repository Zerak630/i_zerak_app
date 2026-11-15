import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/sport_dao.dart';

/// Le nom d'un sport : celui qu'on lui a donne, ou sa traduction pour un
/// sport livre.
String sportLabel(AppLocalizations l10n, Sport? sport) {
  if (sport == null) {
    return l10n.sport_unknown;
  }
  if (sport.label != null && sport.label!.trim().isNotEmpty) {
    return sport.label!;
  }
  return switch (sport.id) {
    Sport.strength => l10n.sport_strength,
    Sport.cardio => l10n.sport_cardio,
    Sport.yoga => l10n.sport_yoga,
    Sport.stretching => l10n.sport_stretching,
    Sport.running => l10n.sport_running,
    _ => sport.id,
  };
}

IconData sportIconData(SportIcon icon) => switch (icon) {
      SportIcon.strength => Icons.fitness_center,
      SportIcon.run => Icons.directions_run,
      SportIcon.yoga => Icons.self_improvement,
      SportIcon.stretch => Icons.accessibility_new,
      SportIcon.gymnastics => Icons.sports_gymnastics,
      SportIcon.bike => Icons.directions_bike,
      SportIcon.walk => Icons.directions_walk,
      SportIcon.hiking => Icons.hiking,
      SportIcon.swim => Icons.pool,
      SportIcon.rowing => Icons.rowing,
      SportIcon.dance => Icons.music_note,
      SportIcon.boxing => Icons.sports_mma,
      SportIcon.martialArts => Icons.sports_martial_arts,
      // Tennis, badminton, padel, squash, ping-pong : Material n'a qu'une
      // raquette.
      SportIcon.racket => Icons.sports_tennis,
      SportIcon.football => Icons.sports_soccer,
      SportIcon.basketball => Icons.sports_basketball,
      SportIcon.volleyball => Icons.sports_volleyball,
      SportIcon.handball => Icons.sports_handball,
      SportIcon.rugby => Icons.sports_rugby,
      SportIcon.hockey => Icons.sports_hockey,
      SportIcon.golf => Icons.sports_golf,
      SportIcon.ski => Icons.downhill_skiing,
      SportIcon.skate => Icons.skateboarding,
      SportIcon.surf => Icons.surfing,
      SportIcon.other => Icons.sports,
    };

/// Une couleur stable par sport, tiree de la palette du theme : la meme d'un
/// ecran a l'autre, pour que les barres « temps par sport » se lisent d'un
/// coup d'oeil.
Color sportColor(ColorScheme scheme, List<Sport> sports, String sportId) {
  final palette = [
    scheme.primary,
    scheme.tertiary,
    scheme.secondary,
    scheme.error,
    scheme.inversePrimary,
    scheme.outline,
  ];
  final index = sports.indexWhere((sport) => sport.id == sportId);
  return palette[(index < 0 ? sports.length : index) % palette.length];
}

/// Formats de l'onglet, dans la langue de l'application.
class SportFormat {
  SportFormat(BuildContext context) : _locale = Localizations.localeOf(context).toLanguageTag();

  final String _locale;

  /// « lundi »
  String weekday(int weekday) =>
      DateFormat('EEEE', _locale).format(DateTime(2026, 11, 15 + weekday));

  /// « lun. »
  String weekdayShort(int weekday) =>
      DateFormat('E', _locale).format(DateTime(2026, 11, 15 + weekday));

  /// « jeu. 12 »
  String weekdayDay(DateTime day) => DateFormat('E d', _locale).format(day);

  /// « lun. 16 nov. »
  String shortDay(DateTime day) => DateFormat('E d MMM', _locale).format(day);

  /// « 16 nov. »
  String dayMonth(DateTime day) => DateFormat('d MMM', _locale).format(day);
}

/// « 45 min », « 1 h 30 ».
String sportMinutes(AppLocalizations l10n, int minutes) {
  if (minutes < 60) {
    return l10n.free_minutes(minutes);
  }
  return l10n.free_hours(minutes ~/ 60, (minutes % 60).toString().padLeft(2, '0'));
}

/// La pastille d'un sport.
class SportAvatar extends StatelessWidget {
  const SportAvatar({super.key, required this.sport, required this.color, this.size = 36, this.muted = false});

  final Sport? sport;
  final Color color;
  final double size;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = muted ? scheme.outline : color;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: muted ? scheme.surfaceContainerHighest : tint.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(size / 3),
      ),
      child: Icon(sportIconData(sport?.icon ?? SportIcon.other), size: size * 0.55, color: tint),
    );
  }
}

/// Poignee et marges communes aux feuilles du bas de l'onglet.
class SportSheet extends StatelessWidget {
  const SportSheet({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: children,
          ),
        ),
      );
}

/// Le choix d'une duree : des valeurs rondes, et la saisie libre au besoin.
class MinutesPicker extends StatefulWidget {
  const MinutesPicker({super.key, required this.minutes, required this.onChanged});

  final int minutes;
  final ValueChanged<int> onChanged;

  static const List<int> presets = [10, 15, 20, 30, 45, 60, 90];

  @override
  State<MinutesPicker> createState() => _MinutesPickerState();
}

class _MinutesPickerState extends State<MinutesPicker> {
  late final TextEditingController _custom = TextEditingController(
    text: MinutesPicker.presets.contains(widget.minutes) ? '' : '${widget.minutes}',
  );

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final preset in MinutesPicker.presets)
          ChoiceChip(
            label: Text(sportMinutes(l10n, preset)),
            selected: widget.minutes == preset,
            onSelected: (_) {
              _custom.clear();
              widget.onChanged(preset);
            },
          ),
      ]),
      const SizedBox(height: 12),
      TextField(
        controller: _custom,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: l10n.sport_minutes_custom,
          suffixText: 'min',
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: (value) {
          final minutes = int.tryParse(value.trim());
          if (minutes != null && minutes > 0 && minutes <= 600) {
            widget.onChanged(minutes);
          }
        },
      ),
    ]);
  }
}

/// Le choix d'un sport, en pastilles.
class SportChooser extends StatelessWidget {
  const SportChooser({super.key, required this.sports, required this.selected, required this.onSelected});

  final List<Sport> sports;
  final String? selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final sport in sports)
        ChoiceChip(
          avatar: Icon(sportIconData(sport.icon), size: 18,
              color: selected == sport.id ? null : sportColor(scheme, sports, sport.id)),
          label: Text(sportLabel(l10n, sport)),
          selected: selected == sport.id,
          onSelected: (_) => onSelected(sport.id),
        ),
    ]);
  }
}
