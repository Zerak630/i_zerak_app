import 'package:flutter/material.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/commute_dao.dart';
import 'package:i_zerak_app/pages/commute/widgets/commute_ui.dart';

/// La carte de tete de l'onglet Velo : la cagnotte, et ce qu'elle finance.
///
/// Elle a longtemps ete un carrousel ou les objectifs defilaient derriere la
/// cagnotte. Ils ont maintenant leur onglet, ou ils ont la place d'afficher
/// leur date : il ne reste ici que le solde, les quatorze derniers jours, et
/// une ligne vers eux.
class PotCard extends StatelessWidget {
  const PotCard({
    super.key,
    required this.ledger,
    required this.today,
    this.onOpenGoals,
  });

  final CommuteLedger ledger;
  final DateTime today;

  /// Nul quand l'onglet Objectifs n'est pas joignable d'ici — dans un test, ou
  /// si la page est affichee hors de la barre d'onglets. La ligne disparait
  /// alors plutot que de mener nulle part.
  final VoidCallback? onOpenGoals;

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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.account_balance_wallet_outlined, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.commute_pot.toUpperCase(),
                    style: theme.textTheme.labelMedium?.copyWith(
                      letterSpacing: 0.8,
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
              const SizedBox(height: 16),
              Row(children: [
                for (var offset = 13; offset >= 0; offset--) ...[
                  _DayDot(day: ledger.dayOn(today.subtract(Duration(days: offset)))),
                  if (offset > 0) const SizedBox(width: 7),
                ],
              ]),
              const SizedBox(height: 8),
              Text(l10n.commute_last_14_days,
                  style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline)),
            ]),
          ),
          if (onOpenGoals != null) _GoalsLink(ledger: ledger, onTap: onOpenGoals!),
        ]),
      ),
    );
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

/// Le pied de la carte : combien d'objectifs courent, et surtout si l'un est
/// atteint — c'est la seule chose qui demande un geste.
class _GoalsLink extends StatelessWidget {
  const _GoalsLink({required this.ledger, required this.onTap});

  final CommuteLedger ledger;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final active = ledger.activeGoals;
    final reached =
        active.where((goal) => ledger.progressOf(goal).reached).length;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
        color: reached > 0 ? scheme.primaryContainer : scheme.surfaceContainerHigh,
        child: Row(children: [
          Icon(
            Icons.flag_outlined,
            size: 18,
            color: reached > 0 ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              reached > 0 ? l10n.goals_reached_count(reached) : l10n.goals_active(active.length),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: reached > 0 ? scheme.onPrimaryContainer : scheme.onSurface,
                fontWeight: reached > 0 ? FontWeight.w600 : null,
              ),
            ),
          ),
          Icon(
            Icons.chevron_right,
            size: 20,
            color: reached > 0 ? scheme.onPrimaryContainer : scheme.outline,
          ),
        ]),
      ),
    );
  }
}
