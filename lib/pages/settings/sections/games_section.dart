import 'package:flutter/material.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/commute_dao.dart' show dateOnly;
import 'package:i_zerak_app/models/game_dao.dart';
import 'package:i_zerak_app/pages/settings/widgets/settings_ui.dart';
import 'package:i_zerak_app/pages/sport/widgets/sport_ui.dart' show sportMinutes;
import 'package:i_zerak_app/services/gaming/gaming_service.dart';
import 'package:i_zerak_app/services/service_locator.dart';

/// La categorie « Jeux » : les regles du contrat jeu contre sport.
///
/// Chaque reglage s'enregistre des qu'on lache le curseur. Les nouvelles
/// regles ne valent qu'a partir du lundi suivant (cf.
/// `GameContractSettings.edited`) : ni les semaines passees ni la cible en
/// cours ne bougent, meme si on tatonne plusieurs fois dans la semaine.
class GamesSection extends StatefulWidget {
  GamesSection({super.key, GamingService? service, DateTime Function()? clock})
      : service = service ?? getIt<GamingService>(),
        clock = clock ?? DateTime.now;

  final GamingService service;
  final DateTime Function() clock;

  @override
  State<GamesSection> createState() => _GamesSectionState();
}

class _GamesSectionState extends State<GamesSection> {
  /// Les regles enregistrees, historique compris.
  GameContractSettings? _stored;

  /// Ce que montrent les curseurs, pendant qu'on les deplace.
  GameContractSettings? _rules;

  @override
  void initState() {
    super.initState();
    widget.service.readSettings().then((settings) {
      if (mounted) {
        setState(() {
          _stored = settings;
          _rules = settings;
        });
      }
    });
  }

  void _preview(GameContractSettings rules) => setState(() => _rules = rules);

  Future<void> _save(GameContractSettings rules) async {
    final next = _stored!.edited(rules, dateOnly(widget.clock()));
    setState(() {
      _stored = next;
      _rules = next;
    });
    await widget.service.saveSettings(next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final rules = _rules;
    if (rules == null) {
      return const SettingsLoading();
    }
    final enabled = rules.enabled;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(l10n.goals_game_enabled),
        value: enabled,
        onChanged: (value) => _save(rules.copyWith(enabled: value)),
      ),
      Text(l10n.goals_game_ratio(rules.gameHoursPerSportHour)),
      Slider(
        value: rules.gameHoursPerSportHour.clamp(1, 6).toDouble(),
        min: 1,
        max: 6,
        divisions: 5,
        onChanged: enabled
            ? (value) => _preview(rules.copyWith(gameHoursPerSportHour: value.round()))
            : null,
        onChangeEnd: (value) => _save(rules.copyWith(gameHoursPerSportHour: value.round())),
      ),
      Text(l10n.goals_game_cap(sportMinutes(l10n, rules.capMinutes))),
      Slider(
        value: rules.capMinutes.clamp(60, 720).toDouble(),
        min: 60,
        max: 720,
        divisions: 22,
        onChanged: enabled ? (value) => _preview(rules.copyWith(capMinutes: value.round())) : null,
        onChangeEnd: (value) => _save(rules.copyWith(capMinutes: value.round())),
      ),
      Text(l10n.goals_game_bike(sportMinutes(l10n, rules.bikeMinutesPerDay))),
      Slider(
        value: rules.bikeMinutesPerDay.clamp(0, 120).toDouble(),
        max: 120,
        divisions: 24,
        onChanged: enabled
            ? (value) => _preview(rules.copyWith(bikeMinutesPerDay: value.round()))
            : null,
        onChangeEnd: (value) => _save(rules.copyWith(bikeMinutesPerDay: value.round())),
      ),
      Text(
        l10n.goals_game_rules_hint,
        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    ]);
  }
}
