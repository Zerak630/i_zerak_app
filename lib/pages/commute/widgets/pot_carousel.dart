import 'package:flutter/material.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/commute_dao.dart';
import 'package:i_zerak_app/models/companion_dao.dart';
import 'package:i_zerak_app/pages/commute/widgets/commute_ui.dart';

/// La tuile de tete de l'onglet Velo : la cagnotte, ses objectifs, et de quoi
/// en ajouter un.
class PotCarousel extends StatelessWidget {
  const PotCarousel({
    super.key,
    required this.ledger,
    required this.today,
    required this.tripValue,
    required this.onValidate,
    required this.onNewGoal,
    required this.onDeleteGoal,
  });

  final CommuteLedger ledger;
  final DateTime today;

  /// Valeur d'un trajet au prix du jour, pour traduire un reste en trajets.
  final double tripValue;

  final ValueChanged<Goal> onValidate;
  final VoidCallback onNewGoal;
  final ValueChanged<Goal> onDeleteGoal;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final format = CommuteFormat(context);
    return GoalCarousel(
      book: ledger.book,
      leading: _PotTile(ledger: ledger, today: today),
      remainingLabel: (remaining) {
        final trips = tripsFor(remaining, tripValue);
        return trips == null
            ? l10n.goal_remaining_amount(format.euros(remaining))
            : l10n.goal_remaining(format.euros(remaining), trips);
      },
      onValidate: onValidate,
      onNewGoal: onNewGoal,
      onDeleteGoal: onDeleteGoal,
    );
  }
}

/// Une cagnotte qui defile : sa tuile de tete, puis un objectif par tuile,
/// puis de quoi en ajouter un.
///
/// La tuile suivante depasse sur le bord droit, et des points suivent : sans
/// eux, rien ne dirait qu'il y a quelque chose a faire defiler.
class GoalCarousel extends StatefulWidget {
  const GoalCarousel({
    super.key,
    required this.book,
    required this.leading,
    required this.remainingLabel,
    required this.onValidate,
    required this.onNewGoal,
    required this.onDeleteGoal,
  });

  final GoalBook book;

  /// La tuile de la cagnotte elle-meme, propre a chaque onglet.
  final Widget leading;

  /// Ce qui manque a un objectif, dit dans l'unite de l'onglet.
  final String Function(double remaining) remainingLabel;

  final ValueChanged<Goal> onValidate;
  final VoidCallback onNewGoal;
  final ValueChanged<Goal> onDeleteGoal;

  /// Assez pour la tuile la plus chargee, celle d'un objectif atteint et de
  /// son bouton.
  static const double height = 206;

  @override
  State<GoalCarousel> createState() => _GoalCarouselState();
}

class _GoalCarouselState extends State<GoalCarousel> {
  final _controller = PageController(viewportFraction: 0.9);
  var _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final goals = widget.book.activeGoals;
    final count = goals.length + 2;
    final scheme = Theme.of(context).colorScheme;

    return Column(children: [
      SizedBox(
        height: GoalCarousel.height,
        child: PageView.builder(
          controller: _controller,
          padEnds: false,
          itemCount: count,
          onPageChanged: (page) => setState(() => _page = page),
          itemBuilder: (context, index) {
            final Widget tile;
            if (index == 0) {
              tile = widget.leading;
            } else if (index <= goals.length) {
              final goal = goals[index - 1];
              final progress = widget.book.progressOf(goal);
              tile = _GoalTile(
                progress: progress,
                remaining: widget.remainingLabel(progress.remaining),
                onValidate: () => widget.onValidate(goal),
                onDelete: () => widget.onDeleteGoal(goal),
              );
            } else {
              tile = _NewGoalTile(onTap: widget.onNewGoal);
            }
            // La marge gauche de chaque page sert d'espace avec la precedente.
            return Padding(padding: const EdgeInsets.only(left: 16), child: tile);
          },
        ),
      ),
      const SizedBox(height: 10),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == _page ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: i == _page ? scheme.primary : scheme.outlineVariant,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
        ],
      ),
    ]);
  }
}

class PotTileFrame extends StatelessWidget {
  const PotTileFrame({super.key, required this.child, this.highlight});

  final Widget child;

  /// Bordure d'un objectif atteint.
  final Color? highlight;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(20),
          border: highlight == null ? null : Border.all(color: highlight!, width: 1.5),
        ),
        child: child,
      );
}

class PotTileHeader extends StatelessWidget {
  const PotTileHeader({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          label.toUpperCase(),
          style: theme.textTheme.labelMedium?.copyWith(
            letterSpacing: 0.8,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      if (trailing != null) trailing!,
    ]);
  }
}

class _PotTile extends StatelessWidget {
  const _PotTile({required this.ledger, required this.today});

  final CommuteLedger ledger;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = CommuteFormat(context);
    final first = ledger.firstBikeDay;

    final String subtitle;
    if (ledger.spent > 0) {
      subtitle = l10n.commute_saved_and_spent(
          format.euros(ledger.totalSaved), format.euros(ledger.spent));
    } else if (first == null) {
      subtitle = l10n.commute_no_bike_trip;
    } else {
      subtitle = l10n.commute_bike_trips(ledger.totals.bikeDays, format.dayMonth(first));
    }

    return PotTileFrame(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        PotTileHeader(
          icon: Icons.account_balance_wallet_outlined,
          label: l10n.commute_pot,
          color: scheme.primary,
        ),
        const SizedBox(height: 10),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            format.euros(ledger.balance),
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.primary,
              letterSpacing: -1,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
        const Spacer(),
        _WorkdayDots(ledger: ledger, today: today),
        const SizedBox(height: 8),
        Text(l10n.commute_last_14_days,
            style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline)),
      ]),
    );
  }
}

/// Les quatorze derniers jours ouvres : le week-end n'est jamais saisi, et
/// n'y laisserait que des cases vides.
class _WorkdayDots extends StatelessWidget {
  const _WorkdayDots({required this.ledger, required this.today});

  final CommuteLedger ledger;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final days = lastWorkdays(today, 14);
    return Row(children: [
      for (final day in days) ...[
        _DayDot(day: ledger.dayOn(day)),
        if (day != days.last) const SizedBox(width: 7),
      ],
    ]);
  }
}

class _DayDot extends StatelessWidget {
  const _DayDot({required this.day});

  final CommuteDay? day;

  @override
  Widget build(BuildContext context) => Container(
        width: 11,
        height: 11,
        decoration: BoxDecoration(
          color: dayColor(Theme.of(context).colorScheme, day),
          shape: BoxShape.circle,
        ),
      );
}

class _GoalTile extends StatelessWidget {
  const _GoalTile({
    required this.progress,
    required this.remaining,
    required this.onValidate,
    required this.onDelete,
  });

  final GoalProgress progress;
  final String remaining;
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
      child: PotTileFrame(
        highlight: progress.reached ? color : null,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          PotTileHeader(
            icon: milestone ? Icons.flag_outlined : goalIconData(goal.icon),
            label: milestone ? l10n.goal_label_milestone : l10n.goal_label_purchase,
            color: color,
            trailing: progress.reached
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999)),
                    child: Text(
                      l10n.goal_reached,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: milestone ? scheme.onTertiary : scheme.onPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                : Text(format.percent(progress.ratio),
                    style: theme.textTheme.labelLarge?.copyWith(color: color)),
          ),
          const SizedBox(height: 10),
          Text(goal.name,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleLarge),
          const SizedBox(height: 2),
          Text(
            milestone
                ? l10n.goal_progress_milestone(
                    format.euros(progress.current), format.euros(goal.target))
                : l10n.goal_progress_purchase(
                    format.euros(progress.current.clamp(0, goal.target).toDouble()),
                    format.euros(goal.target)),
            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.ratio,
              minHeight: 8,
              color: color,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
          const Spacer(),
          if (progress.reached)
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: milestone ? scheme.onTertiary : scheme.onPrimary,
                ),
                onPressed: onValidate,
                child: Text(milestone
                    ? l10n.goal_validate_milestone
                    : l10n.goal_spend_validate(format.euros(goal.target))),
              ),
            )
          else
            Text(
              remaining,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
            ),
        ]),
      ),
    );
  }
}

class _NewGoalTile extends StatelessWidget {
  const _NewGoalTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: scheme.primaryContainer,
            foregroundColor: scheme.onPrimaryContainer,
            child: const Icon(Icons.add),
          ),
          const SizedBox(height: 10),
          Text(l10n.goal_new,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(color: scheme.primary)),
        ]),
      ),
    );
  }
}
