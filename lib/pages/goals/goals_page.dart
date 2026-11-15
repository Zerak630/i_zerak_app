import 'package:flutter/material.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/commute_dao.dart';
import 'package:i_zerak_app/models/companion_dao.dart';
import 'package:i_zerak_app/models/payback_dao.dart';
import 'package:i_zerak_app/models/subscription_dao.dart' show Subscription, SubscriptionFrequency;
import 'package:i_zerak_app/pages/commute/widgets/commute_ui.dart';
import 'package:i_zerak_app/pages/commute/widgets/goal_sheets.dart';
import 'package:i_zerak_app/pages/subscriptions/widgets/subscription_ui.dart'
    show SubscriptionAvatar;
import 'package:i_zerak_app/services/commute_price_service.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_commute.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_subscriptions.dart';
import 'package:i_zerak_app/services/service_locator.dart';

/// L'onglet Objectifs : ce que le velo rembourse, et ce qu'il rentabilise.
///
/// Deux facons de regarder la meme essence economisee :
///
///   - le mois en cours, face aux abonnements que l'on paie deja. Ils
///     reviennent chaque mois, et n'ont rien a remplir : ce sont des
///     objectifs tout trouves ;
///   - les paliers, les gros achats qu'elle finit par rentabiliser — le velo
///     lui-meme, un telephone. Ils se mesurent sur la duree.
///
/// La cagnotte ou l'on puisait pour acheter a disparu : personne ne lui
/// donnait de but.
class GoalsPage extends StatefulWidget {
  GoalsPage({
    super.key,
    ICommute? store,
    ISubscriptions? subscriptions,
    CommutePriceService? prices,
    DateTime Function()? clock,
  })  : store = store ?? getIt<ICommute>(),
        subscriptions = subscriptions ?? getIt<ISubscriptions>(),
        prices = prices ?? getIt<CommutePriceService>(),
        clock = clock ?? DateTime.now;

  final ICommute store;
  final ISubscriptions subscriptions;
  final CommutePriceService prices;
  final DateTime Function() clock;

  @override
  State<GoalsPage> createState() => _GoalsPageState();
}

class _GoalsPageState extends State<GoalsPage> {
  CommuteSettings _settings = const CommuteSettings();
  CommuteLedger _ledger = CommuteLedger(const [], const []);
  List<Subscription> _subscriptions = const [];
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
    final subscriptions = await widget.subscriptions.getAll();
    if (!mounted) {
      return;
    }
    setState(() {
      _settings = settings;
      _ledger = CommuteLedger(days, goals);
      _subscriptions = subscriptions;
      _loading = false;
    });
  }

  double get _tripValue => _price == null ? 0 : _settings.tripValue(_price!.pricePerLitre);

  Future<void> _newGoal() async {
    final l10n = AppLocalizations.of(context)!;
    final format = CommuteFormat(context);
    final tripValue = _tripValue;
    final goal = await showNewGoalSheet(
      context,
      book: _ledger.book,
      today: _today,
      missingHint: (missing) {
        final trips = tripsFor(missing, tripValue);
        return trips == null ? null : l10n.goal_missing_trips(trips, format.euros(tripValue));
      },
    );
    if (goal == null) {
      return;
    }
    await widget.store.saveGoal(goal);
    await _reload();
  }

  Future<void> _validate(Goal goal) async {
    final confirmed = await showValidateGoalSheet(context, goal: goal, book: _ledger.book);
    // Relu apres la feuille : un trajet annule entre-temps pourrait avoir fait
    // repasser le palier sous son montant.
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

  Future<void> _chooseSubscriptions() async {
    final excluded = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _ChooseSubscriptionsSheet(
        subscriptions: paybackSubscriptions(_subscriptions),
        excluded: _settings.paybackExcluded,
      ),
    );
    if (excluded == null) {
      return;
    }
    await widget.store.saveSettings(_settings.copyWith(paybackExcluded: excluded));
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
    final history = paybackHistory(
      _today,
      subscriptions: _subscriptions,
      commute: _ledger,
      excluded: _settings.paybackExcluded,
    );

    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          _PaybackCard(
            payback: history.first,
            tripValue: _tripValue,
            hasSubscriptions: paybackSubscriptions(_subscriptions).isNotEmpty,
            onChoose: _chooseSubscriptions,
          ),
          if (history.skip(1).any((month) => month.saved > 0)) ...[
            const SizedBox(height: 10),
            // Les mois sans un seul trajet, avant les debuts du velo, ne
            // diraient que « 0 sur 4 ».
            _PaybackHistory(months: [for (final month in history.skip(1)) if (month.saved > 0) month]),
          ],
          const SizedBox(height: 22),
          Row(children: [
            Expanded(
              child: Text(l10n.goals_milestones, style: theme.textTheme.titleMedium),
            ),
            FilledButton.tonalIcon(
              onPressed: _newGoal,
              icon: const Icon(Icons.add),
              label: Text(l10n.goal_new_short),
            ),
          ]),
          const SizedBox(height: 4),
          Text(
            l10n.goals_milestones_hint,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          if (active.isEmpty)
            _EmptyGoals(onNew: _newGoal)
          else ...[
            _RateCard(
              rate: rate,
              onWindow: (window) => setState(() => _window = window),
            ),
            const SizedBox(height: 12),
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
          ],
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

/// Le mois en cours : l'essence economisee, et les abonnements qu'elle couvre.
class _PaybackCard extends StatelessWidget {
  const _PaybackCard({
    required this.payback,
    required this.tripValue,
    required this.hasSubscriptions,
    required this.onChoose,
  });

  final MonthPayback payback;
  final double tripValue;

  /// Faux quand aucun abonnement actif n'existe : la carte renvoie alors a
  /// l'onglet Abonnements plutot que d'afficher une liste vide.
  final bool hasSubscriptions;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = CommuteFormat(context);
    final next = payback.next;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.pedal_bike, size: 18, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.payback_title(format.month(payback.month)).toUpperCase(),
              style: theme.textTheme.labelMedium?.copyWith(
                letterSpacing: 0.7,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            format.euros(payback.saved),
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.primary,
              letterSpacing: -1,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          l10n.payback_saved(payback.bikeDays),
          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 14),
        if (!hasSubscriptions)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              l10n.payback_no_subscription,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline, height: 1.4),
            ),
          )
        else if (payback.lines.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              l10n.payback_all_excluded,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
            ),
          )
        else ...[
          Row(children: [
            Expanded(
              child: Text(
                l10n.payback_count(payback.paidCount, payback.lines.length),
                style: theme.textTheme.titleSmall,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              l10n.payback_amount(format.euros(payback.covered), format.euros(payback.total)),
              style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: payback.ratio,
              minHeight: 8,
              color: scheme.primary,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 6),
          for (final line in payback.lines) _PaybackRow(line: line, highlighted: line == next),
          if (next != null)
            _NextHint(line: next, tripValue: tripValue)
          else if (payback.surplus > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                l10n.payback_surplus(format.euros(payback.surplus)),
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.primary),
              ),
            ),
        ],
        if (hasSubscriptions)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onChoose,
              icon: const Icon(Icons.tune, size: 18),
              label: Text(l10n.payback_choose),
            ),
          ),
      ]),
    );
  }
}

class _PaybackRow extends StatelessWidget {
  const _PaybackRow({required this.line, required this.highlighted});

  final PaybackLine line;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = CommuteFormat(context);
    final started = line.covered > 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        SubscriptionAvatar(
          iconId: line.subscription.iconId,
          color: scheme.primary,
          size: 30,
          muted: !line.paid && !started,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              line.subscription.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: highlighted ? FontWeight.w600 : null,
              ),
            ),
            if (!line.paid && started) ...[
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: line.ratio,
                  minHeight: 4,
                  color: scheme.primary,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
            ],
          ]),
        ),
        const SizedBox(width: 12),
        Text(
          line.paid ? format.euros(line.monthly) : '${format.euros(line.covered)} / ${format.euros(line.monthly)}',
          style: theme.textTheme.labelMedium?.copyWith(
            color: line.paid ? scheme.primary : scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 6),
        Icon(
          line.paid ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 18,
          color: line.paid ? scheme.primary : scheme.outlineVariant,
        ),
      ]),
    );
  }
}

/// Ce qu'il faut encore pour faire tomber l'abonnement suivant, en trajets
/// quand le prix du jour est connu.
class _NextHint extends StatelessWidget {
  const _NextHint({required this.line, required this.tripValue});

  final PaybackLine line;
  final double tripValue;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = CommuteFormat(context);
    final trips = tripsFor(line.remaining, tripValue);

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Icon(Icons.flag_outlined, size: 16, color: scheme.onPrimaryContainer),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            trips == null
                ? l10n.payback_next_amount(format.euros(line.remaining), line.subscription.name)
                : l10n.payback_next_trips(trips, line.subscription.name),
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onPrimaryContainer),
          ),
        ),
      ]),
    );
  }
}

/// Les mois precedents, une ligne chacun.
class _PaybackHistory extends StatelessWidget {
  const _PaybackHistory({required this.months});

  final List<MonthPayback> months;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = CommuteFormat(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
          l10n.payback_history.toUpperCase(),
          style: theme.textTheme.labelMedium?.copyWith(
            letterSpacing: 0.7,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        for (final month in months)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              SizedBox(
                width: 110,
                child: Text(format.month(month.month), style: theme.textTheme.bodyMedium),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: month.ratio,
                    minHeight: 6,
                    color: month.allPaid ? scheme.primary : scheme.secondary,
                    backgroundColor: scheme.surfaceContainerHighest,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 92,
                child: Text(
                  month.lines.isEmpty
                      ? format.euros(month.saved)
                      : l10n.payback_history_row(month.paidCount, month.lines.length),
                  textAlign: TextAlign.end,
                  style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ]),
          ),
      ]),
    );
  }
}

/// Le choix des abonnements que le velo rembourse. Renvoie les exclus.
class _ChooseSubscriptionsSheet extends StatefulWidget {
  const _ChooseSubscriptionsSheet({required this.subscriptions, required this.excluded});

  final List<Subscription> subscriptions;
  final Set<String> excluded;

  @override
  State<_ChooseSubscriptionsSheet> createState() => _ChooseSubscriptionsSheetState();
}

class _ChooseSubscriptionsSheetState extends State<_ChooseSubscriptionsSheet> {
  late final Set<String> _excluded = {...widget.excluded};

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final format = CommuteFormat(context);
    return CommuteSheet(children: [
      Text(l10n.payback_choose, style: theme.textTheme.titleLarge),
      const SizedBox(height: 4),
      Text(
        l10n.payback_choose_hint,
        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
      const SizedBox(height: 8),
      for (final subscription in widget.subscriptions)
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: !_excluded.contains(subscription.id),
          title: Text(subscription.name),
          subtitle: Text(l10n.payback_per_month(
              format.euros(roundCents(subscription.amountIn(SubscriptionFrequency.monthly))))),
          onChanged: (kept) => setState(() {
            final id = subscription.id;
            if (id == null) {
              return;
            }
            kept == true ? _excluded.remove(id) : _excluded.add(id);
          }),
        ),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: () => Navigator.pop(context, _excluded),
        child: Text(l10n.save),
      ),
    ]);
  }
}

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


/// Un palier : son anneau, ce qui est rentabilise, et sa date.
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
    final color = scheme.tertiary;

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
                  Icon(goalIconData(goal.icon), size: 18, color: color),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      goal.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ]),
                const SizedBox(height: 3),
                Text(
                  l10n.goal_progress_milestone(
                      format.euros(progress.current), format.euros(goal.target)),
                  style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
                if (goal.since != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    l10n.goal_counted_since(format.shortDayWithYear(goal.since!)),
                    style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline),
                  ),
                ],
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
                foregroundColor: scheme.onTertiary,
              ),
              onPressed: onValidate,
              child: Text(l10n.goal_validate_milestone),
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
              : l10n.goals_forecast(date.year == today.year
                  ? format.dayMonth(date)
                  : '${format.dayMonth(date)} ${date.year}'),
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


class _EmptyGoals extends StatelessWidget {
  const _EmptyGoals({required this.onNew});

  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant, width: 1.5),
      ),
      child: Column(children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: scheme.tertiaryContainer,
          foregroundColor: scheme.onTertiaryContainer,
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
      leading: Icon(Icons.check, color: goalColor(scheme, goal.kind)),
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
