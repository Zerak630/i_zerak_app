import 'package:flutter/material.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/commute_dao.dart';
import 'package:i_zerak_app/models/companion_dao.dart';
import 'package:i_zerak_app/pages/commute/widgets/commute_ui.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_commute.dart';
import 'package:i_zerak_app/services/service_locator.dart';

/// La meme matiere que l'historique, lue autrement : non plus combien, mais a
/// quelle frequence.
///
/// L'historique montre un mois a la fois, ce qui cache les suites et les
/// habitudes. Rien n'est stocke pour cet ecran : series, grille et moyennes se
/// deduisent des journees deja saisies.
class RegularityPage extends StatefulWidget {
  RegularityPage({super.key, ICommute? store, DateTime Function()? clock})
      : store = store ?? getIt<ICommute>(),
        clock = clock ?? DateTime.now;

  final ICommute store;
  final DateTime Function() clock;

  /// Cote d'une case de la grille, et l'ecart entre deux cases.
  static const double cell = 14;
  static const double gap = 4;

  /// Largeur de la colonne des initiales, et son ecart avec la grille.
  static const double initials = 14;
  static const double initialsGap = 7;

  @override
  State<RegularityPage> createState() => _RegularityPageState();
}

class _RegularityPageState extends State<RegularityPage> {
  Regularity _regularity = Regularity(const []);
  var _loading = true;

  DateTime get _today => dateOnly(widget.clock());

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final days = await widget.store.getDays();
    if (mounted) {
      setState(() {
        _regularity = Regularity(days);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.regularity_title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _regularity.recordedDays == 0
              ? _Empty(message: l10n.regularity_empty)
              : _Body(regularity: _regularity, today: _today),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      );
}

class _Body extends StatelessWidget {
  const _Body({required this.regularity, required this.today});

  final Regularity regularity;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final best = regularity.bestMonth;
    final flawless = regularity.flawlessWeekday;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _StreakCard(streak: regularity.streak),
        const SizedBox(height: 12),
        _GridCard(regularity: regularity, today: today),
        const SizedBox(height: 12),
        _WeekdayCard(regularity: regularity),
        if (best != null || flawless != null) ...[
          const SizedBox(height: 12),
          // `IntrinsicHeight` pour que les deux cartes aient la meme hauteur :
          // dans une liste, un `stretch` n'a pas de hauteur a quoi s'etirer.
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (best != null) Expanded(child: _BestMonthCard(month: best)),
              if (best != null && flawless != null) const SizedBox(width: 11),
              if (flawless != null) Expanded(child: _FlawlessCard(stat: flawless)),
            ]),
          ),
        ],
        const SizedBox(height: 14),
        const _Rule(),
      ],
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

class _CardTitle extends StatelessWidget {
  const _CardTitle({required this.label, this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
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

/// La serie en cours, mesuree contre le record.
class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.streak});

  final StreakInfo streak;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = CommuteFormat(context);
    final end = streak.recordEnd;

    return _Card(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.local_fire_department_outlined, size: 18, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(child: _CardTitle(label: l10n.regularity_streak)),
        ]),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic,
            children: [
          Text(
            '${streak.current}',
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.primary,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.regularity_streak_days(streak.current),
              style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ]),
        if (streak.record > 0) ...[
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (streak.current / streak.record).clamp(0, 1).toDouble(),
              minHeight: 8,
              color: scheme.primary,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: Text(
                end == null
                    ? l10n.regularity_record_none
                    : l10n.regularity_record(streak.record, format.monthName(end)),
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              streak.holdsRecord
                  ? l10n.regularity_record_held
                  : l10n.regularity_to_beat(streak.toBeatRecord),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ]),
        ] else ...[
          const SizedBox(height: 8),
          Text(
            l10n.regularity_record_none,
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ]),
    );
  }
}

/// La grille : une colonne par semaine, cinq cases du lundi au vendredi.
///
/// Le nombre de semaines s'adapte a la largeur plutot que de defiler : une
/// grille qu'il faut faire glisser cache justement ce qu'elle doit montrer
/// d'un coup d'oeil.
class _GridCard extends StatelessWidget {
  const _GridCard({required this.regularity, required this.today});

  final Regularity regularity;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = CommuteFormat(context);
    final first = regularity.firstDay;
    final available = regularity.weeksSince(today);

    return _Card(
      child: LayoutBuilder(builder: (context, constraints) {
        const step = RegularityPage.cell + RegularityPage.gap;
        final room = constraints.maxWidth - RegularityPage.initials - RegularityPage.initialsGap;
        final fits = ((room + RegularityPage.gap) / step).floor();
        final count = fits.clamp(1, available == 0 ? 1 : available);
        final weeks = regularity.lastWeeks(count, now: today);
        final initials = format.weekdayInitials();

        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _CardTitle(
            // Tout l'historique tient dans la grille : autant dater le debut,
            // qui en dit plus qu'un nombre de semaines.
            label: count >= available && first != null
                ? l10n.regularity_since(format.dayMonth(first))
                : l10n.regularity_last_weeks(count),
            trailing: Text(
              l10n.regularity_recorded_days(regularity.recordedDays),
              style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline),
            ),
          ),
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Column(children: [
              for (var weekday = 0; weekday < 5; weekday++) ...[
                SizedBox(
                  width: RegularityPage.initials,
                  height: RegularityPage.cell,
                  child: Center(
                    child: Text(
                      initials[weekday],
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.outline,
                        fontSize: 9.5,
                      ),
                    ),
                  ),
                ),
                if (weekday < 4) const SizedBox(height: RegularityPage.gap),
              ],
            ]),
            const SizedBox(width: RegularityPage.initialsGap),
            for (var index = 0; index < weeks.length; index++) ...[
              Column(children: [
                for (var offset = 0; offset < 5; offset++) ...[
                  _DayCell(
                    day: weeks[index].days[offset],
                    today: weeks[index].monday.add(Duration(days: offset)) == today,
                  ),
                  if (offset < 4) const SizedBox(height: RegularityPage.gap),
                ],
              ]),
              if (index < weeks.length - 1) const SizedBox(width: RegularityPage.gap),
            ],
          ]),
          const SizedBox(height: 10),
          _MonthRuler(weeks: weeks),
          const SizedBox(height: 12),
          const _Legend(),
        ]);
      }),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.day, required this.today});

  final CommuteDay? day;
  final bool today;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: RegularityPage.cell,
      height: RegularityPage.cell,
      decoration: BoxDecoration(
        color: dayColor(scheme, day),
        borderRadius: BorderRadius.circular(4),
        // Le jour en cours se repere meme quand rien n'y est encore
        // enregistre : sans cela, la derniere colonne serait illisible.
        border: today && day == null ? Border.all(color: scheme.primary, width: 1.5) : null,
      ),
    );
  }
}

/// Les mois sous la grille, chacun large de ses semaines.
class _MonthRuler extends StatelessWidget {
  const _MonthRuler({required this.weeks});

  final List<RegularityWeek> weeks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final format = CommuteFormat(context);

    // Un mois par groupe de semaines consecutives, d'apres le lundi : une
    // semaine a cheval appartient au mois ou elle commence.
    final groups = <({DateTime month, int weeks})>[];
    for (final week in weeks) {
      final month = DateTime(week.monday.year, week.monday.month);
      if (groups.isNotEmpty && groups.last.month == month) {
        groups.last = (month: month, weeks: groups.last.weeks + 1);
      } else {
        groups.add((month: month, weeks: 1));
      }
    }

    return Padding(
      padding: const EdgeInsets.only(
          left: RegularityPage.initials + RegularityPage.initialsGap),
      child: Row(children: [
        for (final group in groups)
          SizedBox(
            width: group.weeks * (RegularityPage.cell + RegularityPage.gap),
            child: Text(
              format.shortMonth(group.month),
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
                fontSize: 10,
              ),
            ),
          ),
      ]),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Wrap(spacing: 12, runSpacing: 6, children: [
      _LegendItem(color: scheme.primary, label: l10n.commute_legend_bike),
      _LegendItem(color: scheme.secondary, label: l10n.commute_legend_essential),
      _LegendItem(color: scheme.tertiary, label: l10n.commute_legend_missed),
      _LegendItem(color: scheme.surfaceContainerHighest, label: l10n.regularity_legend_none),
    ]);
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
      ),
      const SizedBox(width: 6),
      Text(label,
          style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline)),
    ]);
  }
}

/// Ce que chaque jour de la semaine donne, et le jour qui coince.
class _WeekdayCard extends StatelessWidget {
  const _WeekdayCard({required this.regularity});

  final Regularity regularity;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = CommuteFormat(context);
    final stats = regularity.weekdays;
    final weakest = regularity.weakestWeekday;
    // Les barres se comparent entre elles : la plus longue est celle du jour
    // le plus souvent enregistre, et les autres disent aussi leur rarete.
    final max = stats.fold(0, (most, stat) => stat.recorded > most ? stat.recorded : most);

    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _CardTitle(label: l10n.regularity_weekdays),
        const SizedBox(height: 12),
        for (final stat in stats) ...[
          Row(children: [
            SizedBox(
              width: 32,
              child: Text(
                format.weekdayShort(stat.weekday),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: stat == weakest ? scheme.tertiary : scheme.onSurfaceVariant,
                  fontWeight: stat == weakest ? FontWeight.w600 : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: _WeekdayBar(stat: stat, max: max)),
            const SizedBox(width: 10),
            SizedBox(
              width: 38,
              child: Text(
                l10n.regularity_weekday_ratio(stat.bike, stat.recorded),
                textAlign: TextAlign.right,
                style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline),
              ),
            ),
          ]),
          const SizedBox(height: 10),
        ],
        if (weakest != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.warning_amber_rounded, size: 17, color: scheme.tertiary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  weakest.missed > 0
                      ? l10n.regularity_weak_day_lazy(
                          format.weekdayName(weakest.weekday),
                          weakest.carDays,
                          weakest.recorded,
                          weakest.missed,
                        )
                      : l10n.regularity_weak_day(
                          format.weekdayName(weakest.weekday),
                          weakest.carDays,
                          weakest.recorded,
                        ),
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.45),
                ),
              ),
            ]),
          ),
      ]),
    );
  }
}

class _WeekdayBar extends StatelessWidget {
  const _WeekdayBar({required this.stat, required this.max});

  final WeekdayStat stat;
  final int max;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rest = max - stat.recorded;
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: Container(
        height: 9,
        color: scheme.surfaceContainerHigh,
        child: Row(children: [
          if (stat.bike > 0) Expanded(flex: stat.bike, child: ColoredBox(color: scheme.primary)),
          if (stat.essential > 0)
            Expanded(flex: stat.essential, child: ColoredBox(color: scheme.secondary)),
          if (stat.missed > 0)
            Expanded(flex: stat.missed, child: ColoredBox(color: scheme.tertiary)),
          if (rest > 0) Expanded(flex: rest, child: const SizedBox()),
        ]),
      ),
    );
  }
}

class _BestMonthCard extends StatelessWidget {
  const _BestMonthCard({required this.month});

  final MonthTally month;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = CommuteFormat(context);
    return _Card(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l10n.regularity_best_month,
            style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline)),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            format.monthName(month.month),
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.regularity_month_detail(month.bike, month.recorded),
          style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ]),
    );
  }
}

class _FlawlessCard extends StatelessWidget {
  const _FlawlessCard({required this.stat});

  final WeekdayStat stat;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = CommuteFormat(context);
    return _Card(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l10n.regularity_flawless,
            style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline)),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            format.weekdayName(stat.weekday),
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.primary,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.regularity_month_detail(stat.bike, stat.recorded),
          style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ]),
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(Icons.info_outline, size: 16, color: scheme.outline),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          AppLocalizations.of(context)!.regularity_rule,
          style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline, height: 1.4),
        ),
      ),
    ]);
  }
}
