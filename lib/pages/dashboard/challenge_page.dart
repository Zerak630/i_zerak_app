import 'package:flutter/material.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/commute_dao.dart';
import 'package:i_zerak_app/models/companion_dao.dart';
import 'package:i_zerak_app/pages/commute/widgets/commute_ui.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_commute.dart';
import 'package:i_zerak_app/services/service_locator.dart';

/// Le defi du mois : une seule cible, et de quoi savoir si elle tient encore.
///
/// La cagnotte dit combien, pas a quelle frequence. Un chiffre par mois,
/// propose a partir des mois precedents puis ajuste a la main, et le verdict
/// des mois passes pour corriger la cible plutot que pour sanctionner.
class ChallengePage extends StatefulWidget {
  ChallengePage({super.key, ICommute? store, DateTime Function()? clock})
      : store = store ?? getIt<ICommute>(),
        clock = clock ?? DateTime.now;

  final ICommute store;
  final DateTime Function() clock;

  /// Combien de mois passes la page rappelle.
  static const int pastMonths = 3;

  @override
  State<ChallengePage> createState() => _ChallengePageState();
}

class _ChallengePageState extends State<ChallengePage> {
  List<CommuteDay> _days = const [];
  Map<String, int> _targets = const {};
  var _loading = true;
  var _busy = false;

  DateTime get _today => dateOnly(widget.clock());

  DateTime get _month => DateTime(_today.year, _today.month);

  int? get _target => _targets[monthKey(_month)];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final days = await widget.store.getDays();
    final challenges = await widget.store.getChallenges();
    if (mounted) {
      setState(() {
        _days = days;
        _targets = {for (final target in challenges) monthKey(target.month): target.target};
        _loading = false;
      });
    }
  }

  /// Ecrit la cible, et la montre tout de suite : l'ecriture Hive est suivie
  /// d'un `flush`, et attendre le disque ferait trainer le pas du compteur.
  Future<void> _setTarget(int target) async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _targets = {..._targets, monthKey(_month): target};
    });
    try {
      await widget.store.saveChallenge(ChallengeTarget(month: _month, target: target));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  /// Les mois passes auxquels une cible avait ete fixee, du plus recent au
  /// plus ancien. Un mois sans cible n'a rien a juger.
  List<MonthChallenge> get _past {
    final months = <MonthChallenge>[];
    for (var back = 1; back <= ChallengePage.pastMonths; back++) {
      final month = DateTime(_month.year, _month.month - back);
      final target = _targets[monthKey(month)];
      if (target != null) {
        months.add(MonthChallenge.of(month, target: target, days: _days, now: _today));
      }
    }
    return months;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final target = _target;
    final past = _past;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.challenge_title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                if (target == null)
                  _NoTarget(
                    month: _month,
                    days: _days,
                    onSet: _setTarget,
                  )
                else ...[
                  _RingCard(
                    challenge: MonthChallenge.of(
                      _month,
                      target: target,
                      days: _days,
                      now: _today,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _MonthStrip(month: _month, days: _days, today: _today),
                  const SizedBox(height: 12),
                  _TargetStepper(
                    month: _month,
                    days: _days,
                    target: target,
                    onChanged: _setTarget,
                  ),
                ],
                if (past.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text(
                    l10n.challenge_past.toUpperCase(),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          letterSpacing: 0.7,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 4),
                  for (final month in past) _PastRow(challenge: month),
                ],
              ],
            ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding});

  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding ?? const EdgeInsets.fromLTRB(16, 15, 16, 14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        child: child,
      );
}

/// L'anneau, et la seule phrase qui compte : est-ce encore jouable.
class _RingCard extends StatelessWidget {
  const _RingCard({required this.challenge});

  final MonthChallenge challenge;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = CommuteFormat(context);
    final blocked = !challenge.stillPossible;

    return _Card(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(
          child: SizedBox(
            width: 152,
            height: 152,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: challenge.ratio,
                  strokeWidth: 11,
                  color: blocked ? scheme.tertiary : scheme.primary,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text(
                  '${challenge.done}',
                  style: theme.textTheme.displayMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1,
                  ),
                ),
                Text(
                  l10n.challenge_of_target(challenge.target),
                  style: theme.textTheme.titleSmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ]),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          l10n.challenge_subtitle(format.monthName(challenge.month)),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 15),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: blocked ? scheme.tertiaryContainer : scheme.primaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(children: [
            Icon(
              challenge.reached
                  ? Icons.check_circle_outline
                  : blocked
                      ? Icons.hourglass_disabled
                      : Icons.trending_up,
              size: 19,
              color: blocked ? scheme.onTertiaryContainer : scheme.onPrimaryContainer,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                challenge.reached
                    ? l10n.challenge_reached(challenge.done, challenge.target)
                    : blocked
                        ? l10n.challenge_impossible(challenge.missing, challenge.openWorkdays)
                        : l10n.challenge_remaining(challenge.missing, challenge.openWorkdays),
                style: theme.textTheme.bodyMedium?.copyWith(
                  height: 1.4,
                  color: blocked ? scheme.onTertiaryContainer : scheme.onPrimaryContainer,
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// Les jours ouvres du mois, dans l'ordre : ce qui est joue, et ce qui reste.
class _MonthStrip extends StatelessWidget {
  const _MonthStrip({required this.month, required this.days, required this.today});

  final DateTime month;
  final List<CommuteDay> days;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = CommuteFormat(context);
    final byDay = {for (final day in days) dayKey(day.date): day};
    final workdays = <DateTime>[];
    for (var day = 1; day <= daysOfMonth(month); day++) {
      final date = DateTime(month.year, month.month, day);
      if (isWorkday(date)) {
        workdays.add(date);
      }
    }

    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Text(
              l10n.challenge_day_by_day(format.monthTitle(month)).toUpperCase(),
              style: theme.textTheme.labelMedium?.copyWith(
                letterSpacing: 0.7,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            l10n.challenge_workdays(workdays.length),
            style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          for (final date in workdays)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.2),
                child: Container(
                  height: 18,
                  decoration: BoxDecoration(
                    color: dayColor(scheme, byDay[dayKey(date)]),
                    borderRadius: BorderRadius.circular(4),
                    border: date == today && byDay[dayKey(date)] == null
                        ? Border.all(color: scheme.primary, width: 1.5)
                        : null,
                  ),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Text('1', style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline)),
          Expanded(
            child: Text(
              // Le reperage de la colonne du jour tient a cette seule ligne :
              // les cases sont trop etroites pour porter un chiffre.
              month.month == today.month && month.year == today.year
                  ? l10n.commute_today_short
                  : '',
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(color: scheme.primary),
            ),
          ),
          Text('${daysOfMonth(month)}',
              style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline)),
        ]),
      ]),
    );
  }
}

/// La cible, et ce que l'application aurait propose.
class _TargetStepper extends StatelessWidget {
  const _TargetStepper({
    required this.month,
    required this.days,
    required this.target,
    required this.onChanged,
  });

  final DateTime month;
  final List<CommuteDay> days;
  final int target;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final suggested = suggestedTarget(month, days: days);
    final max = workdaysIn(month);

    return _Card(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l10n.challenge_target, style: theme.textTheme.titleSmall),
            const SizedBox(height: 3),
            Text(
              suggested == null
                  ? l10n.challenge_suggested_none
                  : l10n.challenge_suggested(suggested),
              style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline),
            ),
          ]),
        ),
        IconButton.outlined(
          tooltip: l10n.challenge_less,
          onPressed: target > 1 ? () => onChanged(target - 1) : null,
          icon: const Icon(Icons.remove),
        ),
        SizedBox(
          width: 40,
          child: Text(
            '$target',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        IconButton.outlined(
          tooltip: l10n.challenge_more,
          onPressed: target < max ? () => onChanged(target + 1) : null,
          icon: const Icon(Icons.add),
        ),
      ]),
    );
  }
}

/// Aucune cible pour ce mois : ce que le defi apporte, et de quoi en fixer une.
class _NoTarget extends StatelessWidget {
  const _NoTarget({required this.month, required this.days, required this.onSet});

  final DateTime month;
  final List<CommuteDay> days;
  final ValueChanged<int> onSet;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final suggested = suggestedTarget(month, days: days);
    // Sans historique, aucune moyenne a proposer : la moitie des jours ouvres
    // sert de point de depart, et le pas-a-pas est juste en dessous pour la
    // corriger. Le libelle dit d'ou vient — ou ne vient pas — le chiffre.
    final start = suggested ?? (workdaysIn(month) / 2).round();

    return _Card(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
      child: Column(children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: scheme.primaryContainer,
          foregroundColor: scheme.onPrimaryContainer,
          child: const Icon(Icons.flag_outlined),
        ),
        const SizedBox(height: 12),
        Text(l10n.challenge_none, style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        Text(
          l10n.challenge_none_hint,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
        ),
        const SizedBox(height: 8),
        Text(
          suggested == null ? l10n.challenge_suggested_none : l10n.challenge_suggested(suggested),
          style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline),
        ),
        const SizedBox(height: 14),
        FilledButton(onPressed: () => onSet(start), child: Text(l10n.challenge_set)),
      ]),
    );
  }
}

class _PastRow extends StatelessWidget {
  const _PastRow({required this.challenge});

  final MonthChallenge challenge;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = CommuteFormat(context);
    final reached = challenge.reached;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      leading: Icon(
        reached ? Icons.check : Icons.close,
        color: reached ? scheme.primary : scheme.tertiary,
      ),
      title: Text(format.monthTitle(challenge.month), style: theme.textTheme.bodyLarge),
      trailing: Text(
        reached
            ? l10n.challenge_past_reached(challenge.done, challenge.target)
            : l10n.challenge_past_missed(challenge.done, challenge.target),
        style: theme.textTheme.labelSmall?.copyWith(
          color: reached ? scheme.primary : scheme.outline,
          fontWeight: reached ? FontWeight.w600 : null,
        ),
      ),
    );
  }
}
