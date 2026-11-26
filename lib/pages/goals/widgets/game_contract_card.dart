import 'package:flutter/material.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/game_dao.dart';
import 'package:i_zerak_app/pages/commute/widgets/commute_ui.dart' show CommuteSheet;
import 'package:i_zerak_app/pages/sport/widgets/sport_ui.dart' show sportMinutes;

/// Le contrat de la semaine : le jeu de la semaine passee, le sport qu'il
/// demande, et ce qui en est deja fait, trajets a velo compris.
class GameContractCard extends StatelessWidget {
  const GameContractCard({
    super.key,
    required this.report,
    required this.settings,
    required this.contract,
    required this.streak,
    required this.onSettings,
    this.onStats,
  });

  /// Ouvre l'ecran des statistiques de jeu.
  final VoidCallback? onStats;

  final GamingReport report;
  final GameContractSettings settings;
  final GameContract? contract;
  final int streak;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final contract = this.contract;
    final muted = theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.sports_esports, size: 18, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.goals_game_title.toUpperCase(),
              style: theme.textTheme.labelMedium?.copyWith(
                letterSpacing: 0.7,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          if (onStats != null)
            IconButton(
              onPressed: onStats,
              tooltip: l10n.game_stats_open,
              icon: const Icon(Icons.insights, size: 20),
            ),
          IconButton(
            onPressed: onSettings,
            tooltip: l10n.goals_game_settings,
            icon: const Icon(Icons.tune, size: 20),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (!settings.enabled)
              Text(l10n.goals_game_off, style: muted)
            else if (contract == null)
              Text(l10n.goals_game_measuring, style: muted)
            else if (contract.targetMinutes <= 0)
              Text(l10n.goals_game_nothing, style: muted)
            else
              ..._progress(context, l10n, contract),
            if (settings.enabled && report.errors.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                l10n.goals_game_error(
                  report.errors.keys
                      .map((source) => switch (source) {
                            'lol' => 'LoL',
                            'steam' => 'Steam',
                            _ => 'Pi',
                          })
                      .join(', '),
                ),
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
              ),
            ],
          ]),
        ),
      ]),
    );
  }

  List<Widget> _progress(BuildContext context, AppLocalizations l10n, GameContract contract) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return [
      Text(
        l10n.goals_game_played(sportMinutes(l10n, contract.playedBefore)),
        style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),
      const SizedBox(height: 2),
      Text(
        l10n.goals_game_target(sportMinutes(l10n, contract.targetMinutes)),
        style: theme.textTheme.titleMedium,
      ),
      const SizedBox(height: 10),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: contract.ratio,
          minHeight: 8,
          color: scheme.primary,
          backgroundColor: scheme.surfaceContainerHighest,
        ),
      ),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(
          child: Text(
            contract.kept
                ? l10n.goals_game_kept
                : l10n.goals_game_remaining(sportMinutes(l10n, contract.remaining)),
            style: theme.textTheme.bodySmall?.copyWith(
              color: contract.kept ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
        ),
        Text(
          '${sportMinutes(l10n, contract.doneMinutes)} / ${sportMinutes(l10n, contract.targetMinutes)}',
          style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ]),
      const SizedBox(height: 2),
      Text(
        l10n.goals_game_split(
          sportMinutes(l10n, contract.sportMinutes),
          sportMinutes(l10n, contract.bikeMinutes),
        ),
        style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline),
      ),
      if (streak > 0) ...[
        const SizedBox(height: 2),
        Text(
          l10n.goals_game_streak(streak),
          style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline),
        ),
      ],
    ];
  }
}

/// Les regles du contrat. Renvoie les nouvelles, ou rien si on referme.
Future<GameContractSettings?> showGameContractSheet(
  BuildContext context,
  GameContractSettings settings,
) =>
    showModalBottomSheet<GameContractSettings>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _GameContractSheet(settings: settings),
    );

class _GameContractSheet extends StatefulWidget {
  const _GameContractSheet({required this.settings});

  final GameContractSettings settings;

  @override
  State<_GameContractSheet> createState() => _GameContractSheetState();
}

class _GameContractSheetState extends State<_GameContractSheet> {
  late var _rules = widget.settings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return CommuteSheet(children: [
      Text(l10n.goals_game_settings, style: theme.textTheme.titleLarge),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(l10n.goals_game_enabled),
        value: _rules.enabled,
        onChanged: (value) => setState(() => _rules = _rules.copyWith(enabled: value)),
      ),
      Text(l10n.goals_game_ratio(_rules.gameHoursPerSportHour)),
      Slider(
        value: _rules.gameHoursPerSportHour.clamp(1, 6).toDouble(),
        min: 1,
        max: 6,
        divisions: 5,
        onChanged: (value) =>
            setState(() => _rules = _rules.copyWith(gameHoursPerSportHour: value.round())),
      ),
      Text(l10n.goals_game_cap(sportMinutes(l10n, _rules.capMinutes))),
      Slider(
        value: _rules.capMinutes.clamp(60, 720).toDouble(),
        min: 60,
        max: 720,
        divisions: 22,
        onChanged: (value) => setState(() => _rules = _rules.copyWith(capMinutes: value.round())),
      ),
      Text(l10n.goals_game_bike(sportMinutes(l10n, _rules.bikeMinutesPerDay))),
      Slider(
        value: _rules.bikeMinutesPerDay.clamp(0, 120).toDouble(),
        max: 120,
        divisions: 24,
        onChanged: (value) =>
            setState(() => _rules = _rules.copyWith(bikeMinutesPerDay: value.round())),
      ),
      Text(
        l10n.goals_game_rules_hint,
        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
      const SizedBox(height: 8),
      FilledButton(
        onPressed: () => Navigator.pop(context, _rules),
        child: Text(l10n.save),
      ),
    ]);
  }
}
