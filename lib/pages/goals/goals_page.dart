import 'package:flutter/material.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/commute_dao.dart';
import 'package:i_zerak_app/models/companion_dao.dart';
import 'package:i_zerak_app/pages/commute/widgets/commute_ui.dart';
import 'package:i_zerak_app/pages/commute/widgets/goal_sheets.dart';
import 'package:i_zerak_app/services/commute_price_service.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_commute.dart';
import 'package:i_zerak_app/services/service_locator.dart';

/// L'onglet Objectifs : ce qui reste a atteindre, et quand.
///
/// Les objectifs vivaient dans le carrousel de l'onglet Velo, ou ils
/// defilaient derriere la cagnotte. Ils ont ici la place d'afficher ce qui leur
/// manquait : un rythme mesure, et la date que ce rythme donne. « 8 % » ne dit
/// rien ; « pas avant 2030 » dit que la cible est mal posee.
class GoalsPage extends StatefulWidget {
  GoalsPage({
    super.key,
    ICommute? store,
    CommutePriceService? prices,
    DateTime Function()? clock,
  })  : store = store ?? getIt<ICommute>(),
        prices = prices ?? getIt<CommutePriceService>(),
        clock = clock ?? DateTime.now;

  final ICommute store;
  final CommutePriceService prices;
  final DateTime Function() clock;

  @override
  State<GoalsPage> createState() => _GoalsPageState();
}

class _GoalsPageState extends State<GoalsPage> {
  CommuteSettings _settings = const CommuteSettings();
  CommuteLedger _ledger = CommuteLedger(const [], const []);
  ResolvedPrice? _price;
  var _window = RateWindow.recent;
  var _loading = true;

  DateTime get _today => dateOnly(widget.clock());

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _reload();
    // Le prix ne sert qu'a traduire un reste en trajets : la page s'affiche
    // sans l'attendre.
    final price = await widget.prices.resolve(_settings.fuel, day: _today);
    if (mounted) {
      setState(() => _price = price);
    }
  }

  Future<void> _reload() async {
    final settings = await widget.store.readSettings();
    final days = await widget.store.getDays();
    final goals = await widget.store.getGoals();
    if (!mounted) {
      return;
    }
    setState(() {
      _settings = settings;
      _ledger = CommuteLedger(days, goals);
      _loading = false;
    });
  }

  double get _tripValue => _price == null ? 0 : _settings.tripValue(_price!.pricePerLitre);

  Future<void> _newGoal() async {
    final goal = await showNewGoalSheet(context, ledger: _ledger, tripValue: _tripValue);
    if (goal == null) {
      return;
    }
    await widget.store.saveGoal(goal);
    await _reload();
  }

  Future<void> _validate(Goal goal) async {
    final confirmed = await showValidateGoalSheet(context, goal: goal, ledger: _ledger);
    // Relu apres la feuille : un trajet annule entre-temps pourrait avoir fait
    // repasser l'achat sous son montant.
    if (!confirmed || !_ledger.progressOf(goal).reached) {
      return;
    }
    await widget.store.saveGoal(goal.validated(widget.clock()));
    await _reload();
  }

  Future<void> _delete(Goal goal) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.goal_delete),
        content: Text(l10n.delete_confirm(goal.name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.delete)),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await widget.store.deleteGoal(goal.id);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final active = _ledger.activeGoals;
    final validated = _ledger.validatedGoals;
    final rate = SavingRate.of(_ledger.days, now: _today, window: _window);
    final purchases = active.where((goal) => goal.kind == GoalKind.purchase).length;

    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Row(children: [
            Expanded(
              child: Text(l10n.goals_active(active.length), style: theme.textTheme.titleMedium),
            ),
            FilledButton.tonalIcon(
              onPressed: _newGoal,
              icon: const Icon(Icons.add),
              label: Text(l10n.goal_new),
            ),
          ]),
          const SizedBox(height: 12),
          _RateCard(
            rate: rate,
            onWindow: (window) => setState(() => _window = window),
          ),
          const SizedBox(height: 12),
          if (active.isEmpty)
            _EmptyGoals(onNew: _newGoal)
          else
            for (final goal in active) ...[
              _GoalCard(
                progress: _ledger.progressOf(goal),
                rate: rate,
                today: _today,
                tripValue: _tripValue,
                onValidate: () => _validate(goal),
                onDelete: () => _delete(goal),
              ),
              const SizedBox(height: 10),
            ],
          // Deux achats au moins : avec un seul, la cagnotte ne se partage
          // avec personne et la phrase n'aurait rien a prevenir.
          if (purchases >= 2) const _SharedPotNote(),
          if (validated.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              l10n.goals_reached_section.toUpperCase(),
              style: theme.textTheme.labelMedium?.copyWith(
                letterSpacing: 0.7,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            for (final goal in validated) _ValidatedRow(goal: goal),
          ],
        ],
      ),
    );
  }
}

/// Le rythme, et la fenetre sur laquelle il se mesure.
///
/// La carte est en tete parce que tout le reste en depend : changer de fenetre
/// change toutes les dates des cartes du dessous.
class _RateCard extends StatelessWidget {
  const _RateCard({required this.rate, required this.onWindow});

  final SavingRate rate;
  final ValueChanged<RateWindow> onWindow;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = CommuteFormat(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.trending_up, size: 18, color: scheme.primary),
          const SizedBox(width: 8),
          Text(
            l10n.goals_rate.toUpperCase(),
            style: theme.textTheme.labelMedium?.copyWith(
              letterSpacing: 0.7,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ]),
        const SizedBox(height: 10),
        if (rate.isMeasurable) ...[
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              l10n.goals_rate_per_month(format.euros(rate.perMonth)),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: scheme.primary,
                letterSpacing: -0.6,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            // Le nombre part brut : `intl` le met en forme lui-meme, et c'est
            // sa partie entiere qui decide du singulier — « 1,35 trajet ».
            l10n.goals_rate_trips(
                double.parse(rate.bikeDaysPerWeek.toStringAsFixed(2))),
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ] else
          Text(
            l10n.goals_rate_unknown,
            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        const SizedBox(height: 12),
        SegmentedButton<RateWindow>(
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: [
            ButtonSegment(
              value: RateWindow.recent,
              label: Text(l10n.goals_rate_window_recent),
            ),
            ButtonSegment(
              value: RateWindow.all,
              label: Text(l10n.goals_rate_window_all),
            ),
          ],
          selected: {rate.window},
          onSelectionChanged: (selection) => onWindow(selection.first),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.goals_rate_window_hint,
          style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline),
        ),
      ]),
    );
  }
}

/// Un objectif : son anneau, son avancement, et sa date.
class _GoalCard extends StatelessWidget {
  const _GoalCard({
    required this.progress,
    required this.rate,
    required this.today,
    required this.tripValue,
    required this.onValidate,
    required this.onDelete,
  });

  final GoalProgress progress;
  final SavingRate rate;
  final DateTime today;
  final double tripValue;
  final VoidCallback onValidate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = CommuteFormat(context);
    final goal = progress.goal;
    final milestone = goal.kind == GoalKind.milestone;
    final color = goalColor(scheme, goal.kind);

    return GestureDetector(
      onLongPress: onDelete,
      child: Container(
        padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(18),
          border: progress.reached ? Border.all(color: color, width: 1.5) : null,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            _Ring(value: progress.ratio, color: color, reached: progress.reached),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(
                    child: Text(
                      goal.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (milestone)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                      decoration: BoxDecoration(
                        border: Border.all(color: color),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        l10n.goal_label_milestone.toUpperCase(),
                        style: theme.textTheme.labelSmall?.copyWith(color: color),
                      ),
                    ),
                ]),
                const SizedBox(height: 3),
                Text(
                  milestone
                      ? l10n.goal_progress_milestone(
                          format.euros(progress.current), format.euros(goal.target))
                      : l10n.goal_progress_purchase(
                          format.euros(progress.current.clamp(0, goal.target).toDouble()),
                          format.euros(goal.target)),
                  style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
                if (!progress.reached) ...[
                  const SizedBox(height: 5),
                  _Forecast(
                    remaining: progress.remaining,
                    rate: rate,
                    today: today,
                    tripValue: tripValue,
                  ),
                ],
              ]),
            ),
          ]),
          if (progress.reached) ...[
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: color,
                foregroundColor: milestone ? scheme.onTertiary : scheme.onPrimary,
              ),
              onPressed: onValidate,
              child: Text(milestone
                  ? l10n.goal_validate_milestone
                  : l10n.goal_spend_validate(format.euros(goal.target))),
            ),
          ],
        ]),
      ),
    );
  }
}

/// La date projetee, ou le reste a economiser quand aucun rythme ne se mesure.
class _Forecast extends StatelessWidget {
  const _Forecast({
    required this.remaining,
    required this.rate,
    required this.today,
    required this.tripValue,
  });

  final double remaining;
  final SavingRate rate;
  final DateTime today;
  final double tripValue;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = CommuteFormat(context);
    final date = rate.dateFor(remaining, from: today);
    final trips = tripsFor(remaining, tripValue);

    if (date == null) {
      return Text(
        trips == null
            ? l10n.goal_remaining_amount(format.euros(remaining))
            : l10n.goal_remaining(format.euros(remaining), trips),
        style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
      );
    }

    // Au-dela de l'annee prochaine, la date du jour serait une precision
    // mensongere : seule l'annee est annoncee, et elle dit d'elle-meme que la
    // cible est hors de portee.
    final distant = date.year > today.year + 1;
    final color = distant ? scheme.tertiary : scheme.secondary;

    return Row(children: [
      Icon(distant ? Icons.hourglass_empty : Icons.event_outlined, size: 14, color: color),
      const SizedBox(width: 6),
      Flexible(
        child: Text(
          distant
              ? l10n.goals_forecast_year('${date.year}')
              : l10n.goals_forecast(format.dayMonth(date)),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(color: color, fontWeight: FontWeight.w500),
        ),
      ),
      if (trips != null && !distant) ...[
        const SizedBox(width: 6),
        Text(
          '· ${l10n.goals_forecast_trips(trips)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline),
        ),
      ],
    ]);
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.value, required this.color, required this.reached});

  final double value;
  final Color color;
  final bool reached;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SizedBox(
      width: 52,
      height: 52,
      child: Stack(alignment: Alignment.center, children: [
        SizedBox.expand(
          child: CircularProgressIndicator(
            value: value,
            strokeWidth: 5,
            color: color,
            backgroundColor: scheme.surfaceContainerHighest,
          ),
        ),
        Text(
          CommuteFormat(context).percent(value),
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: reached ? color : scheme.onSurface,
          ),
        ),
      ]),
    );
  }
}

class _SharedPotNote extends StatelessWidget {
  const _SharedPotNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        Icon(Icons.info_outline, size: 17, color: scheme.outline),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            AppLocalizations.of(context)!.goals_shared_pot,
            style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline, height: 1.4),
          ),
        ),
      ]),
    );
  }
}

class _EmptyGoals extends StatelessWidget {
  const _EmptyGoals({required this.onNew});

  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant, width: 1.5),
      ),
      child: Column(children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: scheme.primaryContainer,
          foregroundColor: scheme.onPrimaryContainer,
          child: const Icon(Icons.flag_outlined),
        ),
        const SizedBox(height: 12),
        Text(l10n.goals_empty, style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        Text(
          l10n.goals_empty_hint,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
        ),
        const SizedBox(height: 14),
        FilledButton(onPressed: onNew, child: Text(l10n.goal_new)),
      ]),
    );
  }
}

class _ValidatedRow extends StatelessWidget {
  const _ValidatedRow({required this.goal});

  final Goal goal;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = CommuteFormat(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      leading: Icon(Icons.check, color: scheme.primary),
      title: Text(goal.name, style: theme.textTheme.bodyLarge),
      trailing: Text(
        l10n.commute_validated_on(
          format.euros(goal.target),
          format.shortDay(goal.validatedAt!),
        ),
        style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline),
      ),
    );
  }
}
