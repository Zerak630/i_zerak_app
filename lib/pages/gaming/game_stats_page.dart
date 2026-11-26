import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/commute_dao.dart' show dateOnly;
import 'package:i_zerak_app/models/game_dao.dart';
import 'package:i_zerak_app/models/sport_dao.dart' show weekStart;
import 'package:i_zerak_app/pages/sport/widgets/sport_ui.dart' show sportMinutes;
import 'package:i_zerak_app/services/gaming/gaming_service.dart';
import 'package:i_zerak_app/services/service_locator.dart';
import 'package:intl/intl.dart';

enum GameStatsTab { all, steam, lol }

/// Le temps de jeu releve par le Pi : la synthese, puis Steam et LoL en
/// detail. Tout vient de la copie locale du dernier releve, actualisee a
/// l'ouverture : le Pi n'est pas toujours joignable.
class GameStatsPage extends StatefulWidget {
  GameStatsPage({
    super.key,
    GamingService? service,
    this.ledger,
    this.initialTab = GameStatsTab.all,
    DateTime Function()? clock,
  })  : service = service ?? getIt<GamingService>(),
        clock = clock ?? DateTime.now;

  final GamingService service;

  /// Pour montrer le contrat de la semaine choisie. Sans lui, pas de carte.
  final GameContractLedger? ledger;

  final GameStatsTab initialTab;
  final DateTime Function() clock;

  @override
  State<GameStatsPage> createState() => _GameStatsPageState();
}

class _GameStatsPageState extends State<GameStatsPage> {
  GamingReport? _report;
  DateTime? _monday;
  late var _tab = widget.initialTab;
  LolQueue? _queue;
  var _refreshing = false;

  DateTime get _today => dateOnly(widget.clock());

  @override
  void initState() {
    super.initState();
    widget.service.revision.addListener(_read);
    _read();
    _refresh();
  }

  @override
  void dispose() {
    widget.service.revision.removeListener(_read);
    super.dispose();
  }

  Future<void> _read() async {
    final report = await widget.service.read();
    if (mounted) {
      setState(() => _report = report);
    }
  }

  Future<void> _refresh() async {
    if (_refreshing) {
      return;
    }
    setState(() => _refreshing = true);
    await widget.service.refresh();
    if (mounted) {
      setState(() => _refreshing = false);
    }
  }

  /// Du plus ancien au plus recent.
  List<GameWeek> get _weeks {
    final weeks = [...?_report?.weeks]..sort((a, b) => a.monday.compareTo(b.monday));
    return weeks;
  }

  GameWeek? get _selected {
    final weeks = _weeks;
    if (weeks.isEmpty) {
      return null;
    }
    final monday = _monday ?? weekStart(_today);
    return weeks.firstWhere((week) => week.monday == monday, orElse: () => weeks.last);
  }

  GameWeek? _before(GameWeek week) {
    final monday = DateTime(week.monday.year, week.monday.month, week.monday.day - 7);
    for (final candidate in _weeks) {
      if (candidate.monday == monday) {
        return candidate;
      }
    }
    return null;
  }

  void _select(GameWeek week) => setState(() {
        _monday = week.monday;
        _queue = null;
      });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final report = _report;
    final week = _selected;

    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l10n.game_stats_title),
          Text(
            _updatedLine(context, l10n, report?.updatedAt),
            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ]),
        actions: [
          IconButton(
            tooltip: l10n.game_stats_refresh,
            onPressed: _refreshing ? null : _refresh,
            icon: _refreshing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: report == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  if (report.errors.isNotEmpty) ...[
                    Text(
                      l10n.goals_game_error(_sourceNames(report.errors.keys)),
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (week == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 48),
                      child: Text(l10n.game_stats_never, textAlign: TextAlign.center),
                    )
                  else ...[
                    if (report.sources.length > 1) ...[
                      _Tabs(tab: _tab, onChanged: (tab) => setState(() => _tab = tab)),
                      const SizedBox(height: 8),
                    ],
                    _WeekBar(
                      week: week,
                      today: _today,
                      onPrevious: _neighbour(week, -1),
                      onNext: _neighbour(week, 1),
                    ),
                    const SizedBox(height: 8),
                    ...switch (_effectiveTab(report)) {
                      GameStatsTab.all => _overview(context, report, week),
                      GameStatsTab.steam => _steam(context, week),
                      GameStatsTab.lol => _lol(context, report, week),
                    },
                  ],
                ],
              ),
            ),
    );
  }

  GameStatsTab _effectiveTab(GamingReport report) {
    if (report.sources.length > 1) {
      return _tab;
    }
    return report.sources.contains('lol') ? GameStatsTab.lol : GameStatsTab.steam;
  }

  VoidCallback? _neighbour(GameWeek week, int step) {
    final weeks = _weeks;
    final index = weeks.indexOf(week) + step;
    if (index < 0 || index >= weeks.length) {
      return null;
    }
    return () => _select(weeks[index]);
  }

  List<Widget> _overview(BuildContext context, GamingReport report, GameWeek week) {
    final l10n = AppLocalizations.of(context)!;
    final before = _before(week);
    final contract = widget.ledger?.contractOf(week.monday);
    return [
      _HeroCard(week: week, before: before, sources: report.sources),
      const SizedBox(height: 12),
      _WeeksChart(
        weeks: _weeks,
        selected: week,
        current: weekStart(_today),
        onSelect: _select,
        showSteam: report.sources.contains('steam'),
        showLol: report.sources.contains('lol'),
      ),
      if (contract != null && contract.targetMinutes > 0) ...[
        const SizedBox(height: 12),
        _ContractCard(contract: contract),
      ],
      if (!week.complete) ...[
        const SizedBox(height: 12),
        _Note(text: l10n.game_stats_partial),
      ],
    ];
  }

  List<Widget> _steam(BuildContext context, GameWeek week) {
    final l10n = AppLocalizations.of(context)!;
    final lifetime = [
      for (final game in week.games)
        if (game.lifetimeMinutes != null) game,
    ]..sort((a, b) => b.lifetimeMinutes!.compareTo(a.lifetimeMinutes!));
    return [
      _SteamCard(week: week),
      if (week.days.isNotEmpty) ...[
        const SizedBox(height: 12),
        _DaysCard(days: week.days),
      ],
      if (lifetime.isNotEmpty) ...[
        const SizedBox(height: 12),
        _Section(
          title: l10n.game_stats_lifetime,
          children: [
            for (final game in lifetime)
              _Line(
                leading: _GameIcon(game: game, size: 28),
                title: game.name,
                trailing: l10n.game_stats_hours(game.lifetimeMinutes! ~/ 60),
              ),
          ],
        ),
      ],
      const SizedBox(height: 12),
      _Note(text: l10n.game_stats_steam_hint),
    ];
  }

  List<Widget> _lol(BuildContext context, GamingReport report, GameWeek week) {
    final l10n = AppLocalizations.of(context)!;
    final shown = [
      for (final match in week.matches)
        if (_queue == null || match.queue == _queue) match,
    ];
    final counts = <LolQueue, int>{};
    for (final match in week.matches) {
      counts[match.queue] = (counts[match.queue] ?? 0) + 1;
    }
    final rank = report.lolRank;
    return [
      _LolNumbers(week: week),
      const SizedBox(height: 12),
      _Section(
        title: l10n.game_stats_matches_title,
        children: [
          if (counts.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                ChoiceChip(
                  label: Text(l10n.game_stats_filter(l10n.game_stats_filter_all, week.matches.length)),
                  selected: _queue == null,
                  onSelected: (_) => setState(() => _queue = null),
                ),
                for (final queue in LolQueue.values)
                  if (counts[queue] case final int count)
                    ChoiceChip(
                      label: Text(l10n.game_stats_filter(l10n.game_stats_queue(queue.name), count)),
                      selected: _queue == queue,
                      onSelected: (_) => setState(() => _queue = _queue == queue ? null : queue),
                    ),
              ]),
            ),
          if (week.matches.isEmpty && week.lolGames == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(l10n.game_stats_no_matches),
            ),
          for (final match in shown) _MatchRow(match: match),
          if (week.matchesWithoutDetail > 0 && _queue == null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                l10n.game_stats_no_detail(week.matchesWithoutDetail),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
        ],
      ),
      if (rank != null) ...[
        const SizedBox(height: 12),
        _RankCard(rank: rank, lpChange: week.lpChange),
      ],
    ];
  }
}

String _sourceNames(Iterable<String> sources) => sources
    .map((source) => switch (source) {
          'lol' => 'LoL',
          'steam' => 'Steam',
          _ => 'Pi',
        })
    .join(', ');

String _updatedLine(BuildContext context, AppLocalizations l10n, DateTime? updatedAt) {
  if (updatedAt == null) {
    return l10n.game_stats_never;
  }
  final elapsed = DateTime.now().difference(updatedAt);
  if (elapsed.inHours < 24) {
    return l10n.game_stats_updated(sportMinutes(l10n, math.max(1, elapsed.inMinutes)));
  }
  final locale = Localizations.localeOf(context).toLanguageTag();
  return l10n.game_stats_updated_on(DateFormat.MMMd(locale).add_Hm().format(updatedAt));
}

/// Les couleurs des deux sources, lisibles sur les deux themes.
Color _steamColor(BuildContext context) => Theme.of(context).colorScheme.tertiary;

Color _lolColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark ? const Color(0xFFD9A86C) : const Color(0xFF8A5A1E);

class _Tabs extends StatelessWidget {
  const _Tabs({required this.tab, required this.onChanged});

  final GameStatsTab tab;
  final ValueChanged<GameStatsTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SegmentedButton<GameStatsTab>(
      showSelectedIcon: false,
      segments: [
        ButtonSegment(value: GameStatsTab.all, label: Text(l10n.game_stats_tab_all)),
        const ButtonSegment(value: GameStatsTab.steam, label: Text('Steam')),
        const ButtonSegment(value: GameStatsTab.lol, label: Text('LoL')),
      ],
      selected: {tab},
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}

class _WeekBar extends StatelessWidget {
  const _WeekBar({required this.week, required this.today, this.onPrevious, this.onNext});

  final GameWeek week;
  final DateTime today;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final label = week.monday == weekStart(today)
        ? l10n.game_stats_this_week
        : l10n.game_stats_week(DateFormat.MMMMd(locale).format(week.monday));
    return Row(children: [
      IconButton(
        tooltip: l10n.game_stats_previous_week,
        onPressed: onPrevious,
        icon: const Icon(Icons.chevron_left),
      ),
      Expanded(
        child: Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleSmall),
      ),
      IconButton(
        tooltip: l10n.game_stats_next_week,
        onPressed: onNext,
        icon: const Icon(Icons.chevron_right),
      ),
    ]);
  }
}

class _Section extends StatelessWidget {
  const _Section({this.title, this.trailing, required this.children});

  final String? title;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(color: scheme.surfaceContainer, borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (title != null) ...[
          Row(children: [
            Expanded(
              child: Text(
                title!.toUpperCase(),
                style: theme.textTheme.labelMedium?.copyWith(
                  letterSpacing: 0.7,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ]),
          const SizedBox(height: 8),
        ],
        ...children,
      ]),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(color: scheme.surfaceContainer, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Icon(Icons.info_outline, size: 17, color: scheme.outline),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant))),
      ]),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({this.leading, required this.title, required this.trailing});

  final Widget? leading;
  final String title;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 44,
      child: Row(children: [
        if (leading != null) ...[leading!, const SizedBox(width: 12)],
        Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)),
        Text(trailing, style: theme.textTheme.titleSmall),
      ]),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.week, required this.before, required this.sources});

  final GameWeek week;
  final GameWeek? before;
  final List<String> sources;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final before = this.before;
    final both = sources.contains('steam') && sources.contains('lol');
    String? delta;
    if (before != null) {
      final diff = week.minutes - before.minutes;
      delta = diff == 0
          ? l10n.game_stats_delta_same
          : diff < 0
              ? l10n.game_stats_delta_less(sportMinutes(l10n, -diff))
              : l10n.game_stats_delta_more(sportMinutes(l10n, diff));
    }
    return _Section(children: [
      Text(
        sportMinutes(l10n, week.minutes),
        style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700),
      ),
      if (delta != null)
        Text(
          delta,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: before!.minutes > week.minutes ? scheme.primary : scheme.onSurfaceVariant,
          ),
        ),
      if (both && week.minutes > 0) ...[
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: SizedBox(
            height: 10,
            child: Row(children: [
              if (week.steamMinutes > 0)
                Expanded(flex: week.steamMinutes, child: ColoredBox(color: _steamColor(context))),
              if (week.steamMinutes > 0 && week.lolMinutes > 0) const SizedBox(width: 2),
              if (week.lolMinutes > 0)
                Expanded(flex: week.lolMinutes, child: ColoredBox(color: _lolColor(context))),
            ]),
          ),
        ),
      ],
      if (both) ...[
        const SizedBox(height: 8),
        Wrap(spacing: 16, runSpacing: 4, children: [
          _Legend(color: _steamColor(context), text: l10n.game_stats_share('Steam', sportMinutes(l10n, week.steamMinutes))),
          _Legend(
            color: _lolColor(context),
            text: [
              l10n.game_stats_share('LoL', sportMinutes(l10n, week.lolMinutes)),
              if (week.lolGames > 0) l10n.game_stats_lol_games(week.lolGames),
            ].join(' · '),
          ),
        ]),
      ],
    ]);
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.text});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
      ),
      const SizedBox(width: 6),
      Text(text, style: Theme.of(context).textTheme.bodySmall),
    ]);
  }
}

/// Les semaines en barres empilees ; un appui choisit la semaine.
class _WeeksChart extends StatelessWidget {
  const _WeeksChart({
    required this.weeks,
    required this.selected,
    required this.current,
    required this.onSelect,
    required this.showSteam,
    required this.showLol,
  });

  final List<GameWeek> weeks;
  final GameWeek selected;
  final DateTime current;
  final ValueChanged<GameWeek> onSelect;
  final bool showSteam;
  final bool showLol;

  static const _height = 110.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final complete = [
      for (final week in weeks)
        if (week.complete) week.minutes,
    ];
    final average = complete.isEmpty ? null : complete.reduce((a, b) => a + b) ~/ complete.length;
    final highest = weeks.fold<int>(average ?? 0, (top, week) => math.max(top, week.minutes));
    final scale = highest == 0 ? 0.0 : _height / highest;

    return _Section(
      title: l10n.game_stats_weeks_title(weeks.length),
      trailing: average == null
          ? null
          : Text(
              l10n.game_stats_average(sportMinutes(l10n, average)),
              style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline),
            ),
      children: [
        SizedBox(
          height: _height + 22,
          child: Stack(children: [
            if (average != null && scale > 0)
              Positioned(
                left: 0,
                right: 0,
                top: _height - average * scale,
                child: Container(height: 1, color: scheme.outlineVariant),
              ),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (final week in weeks)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: week == selected,
                    label: '${DateFormat.MMMd(locale).format(week.monday)} : ${sportMinutes(l10n, week.minutes)}',
                    child: InkWell(
                      onTap: () => onSelect(week),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                          _Bar(
                            steam: showSteam ? week.steamMinutes * scale : 0,
                            lol: showLol ? week.lolMinutes * scale : 0,
                            dimmed: week != selected,
                            provisional: !week.complete,
                          ),
                          const SizedBox(height: 6),
                          SizedBox(
                            height: 16,
                            child: Text(
                              week.monday == current
                                  ? l10n.game_stats_in_progress
                                  : DateFormat.Md(locale).format(week.monday),
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.clip,
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontSize: 10,
                                height: 1.2,
                                color: week == selected ? scheme.onSurface : scheme.outline,
                              ),
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ),
            ]),
          ]),
        ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.steam, required this.lol, required this.dimmed, required this.provisional});

  final double steam;
  final double lol;
  final bool dimmed;
  final bool provisional;

  @override
  Widget build(BuildContext context) {
    final alpha = dimmed ? 0.5 : 1.0;
    Widget part(double height, Color color, BorderRadius radius) => Container(
          height: height,
          decoration: BoxDecoration(
            color: provisional ? null : color.withValues(alpha: alpha),
            border: provisional ? Border.all(color: color.withValues(alpha: alpha)) : null,
            borderRadius: radius,
          ),
        );
    return Column(children: [
      if (steam > 0)
        part(steam, _steamColor(context),
            lol > 0 ? const BorderRadius.vertical(top: Radius.circular(3)) : BorderRadius.circular(3)),
      if (lol > 0)
        part(lol, _lolColor(context),
            steam > 0 ? const BorderRadius.vertical(bottom: Radius.circular(3)) : BorderRadius.circular(3)),
      if (steam <= 0 && lol <= 0) Container(height: 2, color: Theme.of(context).colorScheme.outlineVariant),
    ]);
  }
}

class _ContractCard extends StatelessWidget {
  const _ContractCard({required this.contract});

  final GameContract contract;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.directions_run, size: 18, color: scheme.onPrimaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.goals_game_title.toUpperCase(),
              style: theme.textTheme.labelMedium?.copyWith(letterSpacing: 0.7, color: scheme.onPrimaryContainer),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Text(
          l10n.goals_game_target(sportMinutes(l10n, contract.targetMinutes)),
          style: theme.textTheme.titleMedium?.copyWith(color: scheme.onPrimaryContainer),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: contract.ratio,
            minHeight: 8,
            color: scheme.primary,
            backgroundColor: scheme.surface,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          contract.kept
              ? l10n.goals_game_kept
              : l10n.goals_game_remaining(sportMinutes(l10n, contract.remaining)),
          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onPrimaryContainer),
        ),
      ]),
    );
  }
}

/// L'icone d'un jeu, ou son initiale tant qu'elle n'est pas chargee.
class _GameIcon extends StatelessWidget {
  const _GameIcon({required this.game, this.size = 36});

  final GameTitle game;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      color: scheme.tertiaryContainer,
      child: Text(
        game.name.isEmpty ? '?' : game.name.characters.first.toUpperCase(),
        style: TextStyle(
          color: scheme.onTertiaryContainer,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.42,
        ),
      ),
    );
    final icon = game.icon;
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size / 4),
        child: icon == null
            ? fallback
            : Image.network(
                icon,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => fallback,
                frameBuilder: (_, child, frame, loaded) => loaded || frame != null ? child : fallback,
              ),
      ),
    );
  }
}

class _SteamCard extends StatelessWidget {
  const _SteamCard({required this.week});

  final GameWeek week;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = _steamColor(context);
    return _Section(children: [
      Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
        Text(
          sportMinutes(l10n, week.steamMinutes),
          style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            l10n.game_stats_steam_games(week.games.length),
            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ]),
      if (week.games.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(l10n.game_stats_no_steam),
        ),
      for (final game in week.games)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(children: [
            _GameIcon(game: game),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(child: Text(game.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  Text(
                    week.steamMinutes > 0
                        ? '${sportMinutes(l10n, game.minutes)} · ${(game.minutes * 100 / week.steamMinutes).round()} %'
                        : sportMinutes(l10n, game.minutes),
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ]),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: week.steamMinutes > 0 ? game.minutes / week.steamMinutes : 0,
                    minHeight: 6,
                    color: color,
                    backgroundColor: scheme.surfaceContainerHighest,
                  ),
                ),
              ]),
            ),
          ]),
        ),
    ]);
  }
}

class _DaysCard extends StatelessWidget {
  const _DaysCard({required this.days});

  final List<GameDay> days;

  static const _height = 70.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final highest = days.fold<int>(0, (top, day) => math.max(top, day.steamMinutes));
    final label = theme.textTheme.labelSmall?.copyWith(fontSize: 10.5, color: scheme.outline);
    return _Section(
      title: l10n.game_stats_by_day,
      children: [
        SizedBox(
          height: _height + 40,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (final day in days)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(children: [
                    Text(
                      // Un jour sans releve n'est pas un jour sans jeu.
                      day.steamMinutes > 0
                          ? sportMinutes(l10n, day.steamMinutes)
                          : day.measured.contains('steam')
                              ? '0'
                              : '—',
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: label,
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: day.steamMinutes == 0 || highest == 0
                            ? Container(height: 2, color: scheme.outlineVariant)
                            : FractionallySizedBox(
                                heightFactor: math.max(0.05, day.steamMinutes / highest),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: _steamColor(context),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(DateFormat.E(locale).format(day.day), style: label),
                  ]),
                ),
              ),
          ]),
        ),
      ],
    );
  }
}

class _LolNumbers extends StatelessWidget {
  const _LolNumbers({required this.week});

  final GameWeek week;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final games = week.lolGames;
    final rate = games == 0 ? null : (week.lolWins * 100 / games).round();
    Widget tile(String label, String value, {String? extra, Color? color}) => Expanded(
          child: _Section(children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: value,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: color),
                ),
                if (extra != null)
                  TextSpan(text: '  $extra', style: Theme.of(context).textTheme.bodyMedium),
              ]),
            ),
          ]),
        );
    return Column(children: [
      Row(children: [
        tile(l10n.game_stats_games, '$games'),
        const SizedBox(width: 10),
        tile(l10n.game_stats_wins, '${week.lolWins}',
            extra: rate == null ? null : '$rate %', color: _lolColor(context)),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        tile(l10n.game_stats_time, sportMinutes(l10n, week.lolMinutes)),
        const SizedBox(width: 10),
        tile(l10n.game_stats_average_length, games == 0 ? '—' : sportMinutes(l10n, (week.lolMinutes / games).round())),
      ]),
    ]);
  }
}

class _MatchRow extends StatelessWidget {
  const _MatchRow({required this.match});

  final LolMatch match;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final queue = switch (match.queueId) {
      420 => l10n.game_stats_queue_solo,
      440 => l10n.game_stats_queue_flex,
      _ => l10n.game_stats_queue(match.queue.name),
    };
    final detail = [
      if (match.start != null) DateFormat.E(locale).format(match.start!),
      if (match.hasKda) '${match.kills} / ${match.deaths} / ${match.assists}',
    ].join(' · ');
    return Semantics(
      label: match.win ? l10n.game_stats_win : l10n.game_stats_loss,
      child: SizedBox(
        height: 56,
        child: Row(children: [
          _Portrait(match: match),
          const SizedBox(width: 12),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(match.champion ?? '?', maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 7),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                  decoration: BoxDecoration(
                    color: match.queue == LolQueue.ranked
                        ? _lolColor(context).withValues(alpha: 0.18)
                        : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(queue, style: theme.textTheme.labelSmall),
                ),
              ]),
              if (detail.isNotEmpty)
                Text(detail, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ]),
          ),
          Text(sportMinutes(l10n, match.minutes), style: theme.textTheme.bodyMedium),
        ]),
      ),
    );
  }
}

/// Le portrait du champion, cercle dore pour une victoire, gris pour une
/// defaite, et la pastille V ou D pour ne pas dependre de la couleur.
class _Portrait extends StatelessWidget {
  const _Portrait({required this.match});

  final LolMatch match;

  static const _size = 40.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final ring = match.win ? _lolColor(context) : scheme.outline;
    final name = match.champion ?? '?';
    final fallback = Container(
      alignment: Alignment.center,
      color: scheme.secondaryContainer,
      child: Text(
        name.characters.first.toUpperCase(),
        style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onSecondaryContainer),
      ),
    );
    final portrait = match.portrait;
    return SizedBox(
      width: _size + 4,
      height: _size + 4,
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          width: _size,
          height: _size,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(shape: BoxShape.circle, color: ring),
          child: ClipOval(
            child: portrait == null
                ? fallback
                : Image.network(
                    portrait,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => fallback,
                    frameBuilder: (_, child, frame, loaded) => loaded || frame != null ? child : fallback,
                  ),
          ),
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            width: 19,
            height: 19,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: match.win ? _lolColor(context) : scheme.surfaceContainerHighest,
              border: Border.all(color: scheme.surfaceContainer, width: 2),
            ),
            child: Text(
              match.win ? l10n.game_stats_win_short : l10n.game_stats_loss_short,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: match.win ? scheme.surface : scheme.onSurface,
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _RankCard extends StatelessWidget {
  const _RankCard({required this.rank, required this.lpChange});

  final LolRank rank;
  final int? lpChange;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final change = lpChange;
    final title = !rank.isRanked
        ? l10n.game_stats_unranked
        : [
            l10n.game_stats_tier(rank.tier!),
            if (rank.hasDivision && rank.division != null) rank.division!,
            '· ${l10n.game_stats_lp(rank.lp)}',
          ].join(' ');
    return _Section(children: [
      Row(children: [
        Icon(Icons.shield_outlined, size: 32, color: _lolColor(context)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              l10n.game_stats_rank_title.toUpperCase(),
              style: theme.textTheme.labelMedium?.copyWith(letterSpacing: 0.7, color: scheme.onSurfaceVariant),
            ),
            Text(title, style: theme.textTheme.titleMedium),
          ]),
        ),
        if (change != null && change != 0 && rank.isRanked)
          Text(
            l10n.game_stats_lp_week(change > 0 ? '+$change' : '−${-change}'),
            style: theme.textTheme.labelLarge?.copyWith(color: change > 0 ? scheme.primary : scheme.error),
          ),
      ]),
    ]);
  }
}
