import 'package:flutter/material.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/commute_dao.dart' show dateOnly;
import 'package:i_zerak_app/models/game_dao.dart' show GameTitle;
import 'package:i_zerak_app/models/recap_dao.dart';
import 'package:i_zerak_app/models/settings_category.dart';
import 'package:i_zerak_app/pages/settings/settings_page.dart';
import 'package:i_zerak_app/models/sport_dao.dart' show Sport;
import 'package:i_zerak_app/pages/commute/widgets/commute_ui.dart' show CommuteFormat;
import 'package:i_zerak_app/pages/gaming/game_stats_page.dart';
import 'package:i_zerak_app/services/gaming/gaming_service.dart';
import 'package:i_zerak_app/services/service_locator.dart';
import 'package:i_zerak_app/pages/sport/widgets/sport_ui.dart';
import 'package:i_zerak_app/services/recap/recap_service.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_sport.dart';

/// Le bilan d'une semaine ou d'un mois : ce que le velo a economise, le temps
/// repris aux reseaux, et le temps de sport — chacun dans son unite.
class RecapPage extends StatefulWidget {
  const RecapPage({super.key, required this.service, required this.sport, this.clock});

  final RecapService service;

  /// Pour les noms et couleurs des sports.
  final ISport sport;

  final DateTime Function()? clock;

  @override
  State<RecapPage> createState() => _RecapPageState();
}

class _RecapPageState extends State<RecapPage> {
  late RecapRange _range = RecapRange.weekOf(_today);
  Recap? _recap;
  Recap? _previous;
  List<Sport> _sports = const [];

  DateTime get _today => dateOnly((widget.clock ?? DateTime.now)());

  @override
  void initState() {
    super.initState();
    _load();
    _refreshGames();
    widget.service.readSettings().then((settings) {
      if (settings.weekly || settings.monthly) {
        widget.service.ensureNotifications();
      }
    });
  }

  Future<void> _load() async {
    final recaps = await widget.service.build([_range, _range.previous]);
    final sports = await widget.sport.getSports();
    if (!mounted) {
      return;
    }
    setState(() {
      _recap = recaps.first;
      _previous = recaps.last;
      _sports = sports;
    });
  }

  Future<void> _refreshGames() async {
    if (await widget.service.refreshGames() && mounted) {
      await _load();
    }
  }

  void _show(RecapRange range) {
    setState(() {
      _range = range;
      _recap = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final recap = _recap;
    final current = _range.contains(_today);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.recap_page_title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          SegmentedButton<RecapPeriod>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: RecapPeriod.week, label: Text(l10n.sport_period_week)),
              ButtonSegment(value: RecapPeriod.month, label: Text(l10n.recap_month)),
            ],
            selected: {_range.period},
            onSelectionChanged: (selection) => _show(RecapRange.of(selection.first, _today)),
          ),
          const SizedBox(height: 8),
          Row(children: [
            IconButton(
              onPressed: () => _show(_range.previous),
              tooltip: l10n.recap_previous,
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                _rangeLabel(context, l10n),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
            ),
            IconButton(
              onPressed: current ? null : () => _show(_range.next),
              tooltip: l10n.recap_next,
              icon: const Icon(Icons.chevron_right),
            ),
          ]),
          if (current)
            Text(
              l10n.recap_in_progress,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline),
            ),
          const SizedBox(height: 12),
          if (recap == null)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            _BikeCard(recap: recap, previous: _previous),
            const SizedBox(height: 10),
            if (recap.freeTime != null) ...[
              _FreeCard(recap: recap, previous: _previous),
              const SizedBox(height: 10),
            ],
            _SportCard(recap: recap, previous: _previous, sports: _sports),
            // Le contrat ne depend que de la semaine d'avant : il reste affiche
            // quand la copie locale ne connait pas encore celle-ci.
            if (recap.games?.played != null || recap.games?.contract != null) ...[
              const SizedBox(height: 10),
              _GamesCard(recap: recap, previous: _previous, today: _today),
            ],
          ],
          const SizedBox(height: 16),
          // Raccourci : les notifications de bilan se reglent avec les autres.
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.notifications_outlined),
            title: Text(l10n.recap_notify_settings),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => openSettings(context, open: SettingsCategory.notifications),
          ),
        ],
      ),
    );
  }

  String _rangeLabel(BuildContext context, AppLocalizations l10n) {
    final format = CommuteFormat(context);
    if (_range.period == RecapPeriod.month) {
      return format.month(_range.start);
    }
    final sport = SportFormat(context);
    return l10n.recap_week_range(sport.dayMonth(_range.start), sport.dayMonth(_range.end));
  }
}

/// Une carte du bilan : une icone, un chiffre, et ce qui l'accompagne.
class _RecapCard extends StatelessWidget {
  const _RecapCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
    this.detail,
    this.trend,
    this.children = const [],
  });

  final IconData icon;
  final String title;
  final String value;
  final Color color;
  final String? detail;
  final String? trend;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: theme.textTheme.labelMedium?.copyWith(
                letterSpacing: 0.7,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          if (trend != null)
            Text(trend!, style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline)),
        ]),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700, color: color),
          ),
        ),
        if (detail != null) ...[
          const SizedBox(height: 2),
          Text(detail!, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
        ],
        ...children,
      ]),
    );
  }
}

String? _trend(AppLocalizations l10n, String Function(num) format, num now, num? before) {
  if (before == null || before <= 0) {
    return null;
  }
  return l10n.recap_before(format(before));
}

class _BikeCard extends StatelessWidget {
  const _BikeCard({required this.recap, required this.previous});

  final Recap recap;
  final Recap? previous;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = CommuteFormat(context);
    final payback = recap.payback;

    return _RecapCard(
      icon: Icons.pedal_bike,
      title: l10n.recap_bike_title,
      value: format.euros(recap.fuelSaved),
      color: scheme.primary,
      detail: l10n.payback_saved(recap.bikeDays),
      trend: _trend(l10n, (v) => format.euros(v.toDouble()), recap.fuelSaved, previous?.fuelSaved),
      children: [
        if (payback != null && payback.lines.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: Text(
                l10n.payback_count(payback.paidCount, payback.lines.length),
                style: theme.textTheme.titleSmall,
              ),
            ),
            Text(
              l10n.payback_amount(format.euros(payback.covered), format.euros(payback.total)),
              style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ]),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: payback.ratio,
              minHeight: 6,
              color: scheme.primary,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final line in payback.lines)
              if (line.paid)
                Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(Icons.check, size: 16, color: scheme.primary),
                  label: Text(line.subscription.name),
                ),
          ]),
        ],
      ],
    );
  }
}

class _FreeCard extends StatelessWidget {
  const _FreeCard({required this.recap, required this.previous});

  final Recap recap;
  final Recap? previous;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final free = recap.freeTime!;
    final writer = _minutes(l10n);

    return _RecapCard(
      icon: Icons.hourglass_bottom,
      title: l10n.free_regained_title,
      value: writer(free.regainedMinutes),
      color: scheme.primary,
      detail: l10n.recap_free_detail(free.keptDays, free.measuredDays, writer(free.overMinutes)),
      trend: _trend(l10n, writer, free.regainedMinutes, previous?.freeTime?.regainedMinutes),
    );
  }
}

class _SportCard extends StatelessWidget {
  const _SportCard({required this.recap, required this.previous, required this.sports});

  final Recap recap;
  final Recap? previous;
  final List<Sport> sports;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final writer = _minutes(l10n);
    final share = recap.sportShareOfRegained;
    String label(String id) {
      for (final sport in sports) {
        if (sport.id == id) {
          return sportLabel(l10n, sport);
        }
      }
      return sportLabel(l10n, null);
    }

    return _RecapCard(
      icon: Icons.fitness_center,
      title: l10n.bb_sport,
      value: writer(recap.sportMinutes),
      color: scheme.primary,
      detail: recap.planned > 0
          ? '${l10n.sport_sessions(recap.sportSessions)} · ${l10n.sport_plan_progress(recap.plannedDone, recap.planned)}'
          : l10n.sport_sessions(recap.sportSessions),
      trend: _trend(l10n, writer, recap.sportMinutes, previous?.sportMinutes),
      children: [
        if (recap.bySport.isNotEmpty) const SizedBox(height: 8),
        for (final total in recap.bySport)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Expanded(child: Text(label(total.sportId), style: theme.textTheme.bodyMedium)),
              Text(
                '${writer(total.minutes)} · ${l10n.sport_sessions_short(total.sessions)}',
                style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ]),
          ),
        // Seulement quand le sport tient dans le temps repris : « 1 h 15 des
        // 51 min reprises » ne voudrait rien dire.
        if (share != null && recap.sportMinutes > 0 && share < 1) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              l10n.recap_sport_share(
                writer(recap.freeTime!.regainedMinutes),
                writer(recap.sportMinutes),
              ),
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onPrimaryContainer),
            ),
          ),
        ],
      ],
    );
  }
}

class _GamesCard extends StatelessWidget {
  const _GamesCard({required this.recap, required this.previous, required this.today});

  final Recap recap;
  final Recap? previous;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final writer = _minutes(l10n);
    final week = recap.games!.played;
    // Une semaine sans releve n'est pas une semaine sans jeu.
    final played = week != null && (week.complete || week.minutes > 0) ? week : null;
    final before = previous?.games?.played;
    final text = RecapWriter(l10n, Localizations.localeOf(context).toLanguageTag(), dateOnlyNow: today);
    final contract = text.contractLine(recap);
    final next = text.nextLine(recap);
    final detail = played == null
        ? l10n.recap_game_unmeasured
        : [
            if (!played.complete) l10n.recap_game_partial_short,
            if (played.lolGames > 0) l10n.recap_game_lol(played.lolGames),
          ].join(' · ');
    final games = played?.games ?? const <GameTitle>[];

    return _RecapCard(
      icon: Icons.sports_esports,
      title: l10n.recap_games_title,
      value: played == null ? '—' : writer(played.minutes),
      color: scheme.primary,
      detail: detail.isEmpty ? null : detail,
      trend: played != null && before != null && before.complete
          ? _trend(l10n, writer, played.minutes, before.minutes)
          : null,
      children: [
        if (games.isNotEmpty) const SizedBox(height: 8),
        for (final game in games.take(5))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Expanded(
                child: Text(
                  game.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              Text(
                writer(game.minutes),
                style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ]),
          ),
        if (contract != null || next != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              [if (contract != null) contract, if (next != null) next].join('\n'),
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onPrimaryContainer),
            ),
          ),
        ],
        if (getIt.isRegistered<GamingService>())
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => GameStatsPage(),
              )),
              icon: const Icon(Icons.insights, size: 18),
              label: Text(l10n.game_stats_open),
            ),
          ),
      ],
    );
  }
}

String Function(num) _minutes(AppLocalizations l10n) => (value) => sportMinutes(l10n, value.round());
