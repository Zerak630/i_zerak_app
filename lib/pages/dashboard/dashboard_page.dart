import 'package:flutter/material.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/agent_dao.dart';
import 'package:i_zerak_app/models/commute_dao.dart' hide dateOnly, roundCents;
import 'package:i_zerak_app/models/commute_dao.dart' as commute show dateOnly;
import 'package:i_zerak_app/models/companion_dao.dart';
import 'package:i_zerak_app/models/screen_time_dao.dart' show ScreenTimeLedger;
import 'package:i_zerak_app/models/subscription_dao.dart';
import 'package:i_zerak_app/pages/commute/widgets/commute_ui.dart'
    show bucketLabel, dayLabel, remoteColor;
import 'package:i_zerak_app/pages/commute/widgets/could_bike_sheet.dart';
import 'package:i_zerak_app/pages/gas_stations/widgets/fuel_label.dart';
import 'package:i_zerak_app/pages/dashboard/budget_page.dart';
import 'package:i_zerak_app/pages/dashboard/challenge_page.dart';
import 'package:i_zerak_app/pages/free_time/widgets/free_time_ui.dart' show formatMinutes;
import 'package:i_zerak_app/pages/subscriptions/widgets/subscription_ui.dart';
import 'package:i_zerak_app/services/agent/agent_service.dart';
import 'package:i_zerak_app/services/commute_price_service.dart';
import 'package:i_zerak_app/services/qbittorrent/qb_exceptions.dart';
import 'package:i_zerak_app/services/qbittorrent/qb_service.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_commute.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_gas_stations.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_subscriptions.dart';
import 'package:i_zerak_app/services/screen_time/screen_time_service.dart';
import 'package:i_zerak_app/services/service_locator.dart';
import 'package:i_zerak_app/utils/confirmation_snack_bar.dart';
import 'package:i_zerak_app/utils/formatters.dart';
import 'package:i_zerak_app/utils/wide_layout.dart';

/// L'accueil : ce qui bouge aujourd'hui, en une page.
///
/// Cinq onglets mais aucune vue d'ensemble : il fallait ouvrir chacun pour
/// savoir si le Pi tenait debout, ce qui telechargeait, et ce qui allait etre
/// preleve. Rien n'est saisi ici sauf la journee du jour, qui ne coute qu'un
/// appui.
///
/// Les deux appels au serveur sont passes en parametre plutot que pris dans le
/// conteneur : ils sont les seuls a pouvoir echouer, et les tests ont besoin
/// de les faire echouer.
class DashboardPage extends StatefulWidget {
  DashboardPage({
    super.key,
    ISubscriptions? subscriptionService,
    ICommute? commuteService,
    CommutePriceService? prices,
    IGasStations? stations,
    Future<SystemSnapshot> Function()? systemLoader,
    Future<TorrentsSnapshot> Function()? torrentsLoader,
    Future<ScreenTimeLedger?> Function()? freeTimeLoader,
    DateTime Function()? clock,
  })  : subscriptionService = subscriptionService ?? getIt<ISubscriptions>(),
        commuteService = commuteService ?? getIt<ICommute>(),
        prices = prices ?? getIt<CommutePriceService>(),
        stations = stations ?? getIt<IGasStations>(),
        systemLoader = systemLoader ?? getIt<AgentService>().snapshot,
        torrentsLoader = torrentsLoader ?? getIt<QbService>().snapshot,
        freeTimeLoader = freeTimeLoader ?? _syncFreeTime,
        clock = clock ?? DateTime.now;

  final ISubscriptions subscriptionService;
  final ICommute commuteService;
  final CommutePriceService prices;
  final IGasStations stations;
  final Future<SystemSnapshot> Function() systemLoader;
  final Future<TorrentsSnapshot> Function() torrentsLoader;

  /// Le temps libre du jour. Nul quand l'onglet n'est pas configure, ou hors
  /// Android.
  final Future<ScreenTimeLedger?> Function() freeTimeLoader;

  static Future<ScreenTimeLedger?> _syncFreeTime() async {
    if (!getIt.isRegistered<ScreenTimeService>()) {
      return null;
    }
    final service = getIt<ScreenTimeService>();
    if (!service.source.isSupported) {
      return null;
    }
    return service.sync();
  }
  final DateTime Function() clock;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  CommuteSettings _settings = const CommuteSettings();
  CommuteLedger _commute = CommuteLedger(const [], const []);
  SubscriptionLedger _subscriptions = SubscriptionLedger(const []);
  int _stationCount = 0;

  /// Les cibles mensuelles, par « aaaa-mm ».
  Map<String, int> _targets = const {};

  ResolvedPrice? _price;
  SystemSnapshot? _system;
  Object? _systemError;
  TorrentsSnapshot? _torrents;
  ScreenTimeLedger? _freeTime;
  Object? _torrentsError;

  bool _loading = true;
  bool _busy = false;

  DateTime get _today => commute.dateOnly(widget.clock());

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Le local d'abord : la page s'affiche sans attendre le Pi, qui peut etre
  /// eteint. Les trois sources distantes se chargent ensuite chacune de leur
  /// cote, et l'echec de l'une n'efface pas les autres.
  Future<void> _load() async {
    await _loadLocal();
    if (mounted) {
      setState(() => _loading = false);
    }
    await Future.wait([_loadPrice(), _loadSystem(), _loadTorrents(), _loadFreeTime()]);
  }

  Future<void> _loadLocal() async {
    final settings = await widget.commuteService.readSettings();
    final days = await widget.commuteService.getDays();
    final goals = await widget.commuteService.getGoals();
    final challenges = await widget.commuteService.getChallenges();
    final subscriptions = await widget.subscriptionService.getAll();
    final stations = await widget.stations.getAll();
    if (!mounted) {
      return;
    }
    setState(() {
      _settings = settings;
      _commute = CommuteLedger(days, goals);
      _targets = {for (final target in challenges) monthKey(target.month): target.target};
      _subscriptions = SubscriptionLedger(subscriptions);
      _stationCount = stations.length;
    });
  }

  Future<void> _loadFreeTime() async {
    try {
      final ledger = await widget.freeTimeLoader();
      if (mounted) {
        setState(() => _freeTime = ledger);
      }
    } catch (error) {
      // La carte reste simplement absente : le reste de l'accueil n'en
      // depend pas.
      debugPrint('Temps libre indisponible : $error');
    }
  }

  Future<void> _loadPrice() async {
    final price = await widget.prices.resolve(_settings.fuel, day: _today);
    if (mounted) {
      setState(() => _price = price);
    }
  }

  Future<void> _loadSystem() async {
    try {
      final snapshot = await widget.systemLoader();
      if (mounted) {
        setState(() {
          _system = snapshot;
          _systemError = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _systemError = error);
      }
    }
  }

  Future<void> _loadTorrents() async {
    try {
      final snapshot = await widget.torrentsLoader();
      if (mounted) {
        setState(() {
          _torrents = snapshot;
          _torrentsError = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _torrentsError = error);
      }
    }
  }

  Future<void> _guard(Future<void> Function() action) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<ResolvedPrice> _todayPrice() async {
    final known = _price;
    if (known != null) {
      return known;
    }
    await _loadPrice();
    return _price ?? const ResolvedPrice.fallback();
  }

  Future<void> _recordBike() => _guard(() async {
        final l10n = AppLocalizations.of(context)!;
        final format = SubscriptionFormat(context);
        final day = CommuteDay.bike(_today, _settings, await _todayPrice());
        await widget.commuteService.saveDay(day);
        await _loadLocal();
        if (mounted) {
          showConfirmation(context, l10n.commute_snack_bike(format.euros(day.amount)));
        }
      });

  Future<void> _recordCar() => _guard(() async {
        final l10n = AppLocalizations.of(context)!;
        final format = SubscriptionFormat(context);
        final price = await _todayPrice();
        if (!mounted) {
          return;
        }
        final bucket = await showCouldBikeSheet(
          context,
          subtitle: l10n.commute_why_car_detail(
            format.longDay(_today),
            format.euros(_settings.tripValue(price.pricePerLitre)),
          ),
        );
        if (bucket == null) {
          return;
        }
        await widget.commuteService.saveDay(CommuteDay.car(_today, _settings, price, bucket));
        await _loadLocal();
        if (mounted) {
          showConfirmation(context, l10n.commute_snack_car(bucketLabel(l10n, bucket)));
        }
      });

  Future<void> _recordRemote() => _guard(() async {
        final l10n = AppLocalizations.of(context)!;
        await widget.commuteService.saveDay(CommuteDay.remote(_today));
        await _loadLocal();
        if (mounted) {
          showConfirmation(context, l10n.commute_snack_remote);
        }
      });

  Future<void> _openChallenge() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChallengePage(store: widget.commuteService, clock: widget.clock),
      ),
    );
    // La cible a pu changer la-bas : l'anneau doit le montrer au retour.
    await _loadLocal();
  }

  /// Le defi du mois, reduit a son anneau et a ce qu'il reste a faire.
  Widget _challenge(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final month = DateTime(_today.year, _today.month);
    final target = _targets[monthKey(month)];

    // Aucune cible : une seule ligne, juste de quoi savoir que ca existe.
    if (target == null) {
      return Material(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _openChallenge,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Row(children: [
              Icon(Icons.flag_outlined, size: 20, color: scheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(child: Text(l10n.challenge_title, style: theme.textTheme.bodyLarge)),
              Text(l10n.challenge_set,
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.primary)),
              Icon(Icons.chevron_right, size: 20, color: scheme.outline),
            ]),
          ),
        ),
      );
    }

    final challenge = MonthChallenge.of(
      month,
      target: target,
      days: _commute.days,
      now: _today,
    );
    final blocked = !challenge.stillPossible;
    final color = blocked ? scheme.tertiary : scheme.primary;

    return Material(
      color: scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _openChallenge,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(children: [
            SizedBox(
              width: 44,
              height: 44,
              child: Stack(alignment: Alignment.center, children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: challenge.ratio,
                    strokeWidth: 4.5,
                    color: color,
                    backgroundColor: scheme.surfaceContainerHighest,
                  ),
                ),
                Text('${challenge.done}',
                    style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
              ]),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l10n.challenge_title, style: theme.textTheme.bodyLarge),
                const SizedBox(height: 2),
                Text(
                  challenge.reached
                      ? l10n.challenge_card_done(challenge.done, challenge.target)
                      : blocked
                          ? l10n.challenge_impossible(
                              challenge.missing, challenge.openWorkdays)
                          : l10n.challenge_remaining(
                              challenge.missing, challenge.openWorkdays),
                  maxLines: 2,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: challenge.reached ? scheme.primary : color,
                  ),
                ),
              ]),
            ),
            Icon(Icons.chevron_right, size: 20, color: scheme.outline),
          ]),
        ),
      ),
    );
  }

  Future<void> _openBudget() => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BudgetPage(
            subscriptionService: widget.subscriptionService,
            commuteService: widget.commuteService,
            clock: widget.clock,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final format = SubscriptionFormat(context);

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Trois groupes, dans l'ordre de lecture du telephone : la journee et son
    // defi, l'argent, puis le serveur et le carburant. Sur grand ecran ils se
    // posent cote a cote au lieu de s'empiler, sans changer d'ordre.
    final day = [
      _today_(context, l10n),
      // Entre la journee a enregistrer et l'argent : le defi parle du meme
      // geste que les deux boutons du dessus.
      if (_settings.isConfigured) _challenge(context, l10n),
    ];
    final money = [
      _money(context, l10n),
      if (_freeTime?.settings.isConfigured ?? false) _freeTimeCard(context, l10n, _freeTime!),
    ];
    final machine = [_pi(context, l10n), _downloads(context, l10n), _fuel(context, l10n)];

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: LayoutBuilder(builder: (context, constraints) {
          final width = constraints.maxWidth;
          final columns = width >= WideLayout.threeColumns
              ? [day, money, machine]
              : width >= WideLayout.twoColumns
                  ? [
                      [...day, ...money],
                      machine,
                    ]
                  : [
                      [...day, ...money, ...machine],
                    ];
          final wide = columns.length > 1;

          return ListView(
            padding: wide
                ? const EdgeInsets.fromLTRB(28, 20, 28, 28)
                : const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              Text(
                format.longDay(_today),
                style: (wide ? theme.textTheme.bodyMedium : theme.textTheme.bodySmall)
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
              SizedBox(height: wide ? 16 : 10),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final (index, cards) in columns.indexed) ...[
                  if (index > 0) const SizedBox(width: 16),
                  Expanded(child: _stack(cards)),
                ],
              ]),
            ],
          );
        }),
      ),
    );
  }

  Widget _stack(List<Widget> cards) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, card) in cards.indexed) ...[
            if (index > 0) const SizedBox(height: 12),
            card,
          ],
        ],
      );

  /// La journee du jour : les deux boutons, ou ce qui a deja ete enregistre.
  Widget _today_(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = SubscriptionFormat(context);

    if (!_settings.isConfigured) {
      return Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          leading: const Icon(Icons.pedal_bike),
          title: Text(l10n.home_setup_commute),
          subtitle: Text(l10n.commute_settings_entry_hint),
        ),
      );
    }

    final recorded = _commute.dayOn(_today);
    if (recorded != null) {
      return Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          leading: Icon(
            switch (recorded.mode) {
              CommuteMode.bike => Icons.pedal_bike,
              CommuteMode.car => Icons.directions_car_outlined,
              CommuteMode.remote => Icons.home_work_outlined,
            },
            color: switch (recorded.mode) {
              CommuteMode.bike => scheme.primary,
              CommuteMode.car => scheme.secondary,
              CommuteMode.remote => remoteColor(scheme),
            },
          ),
          title: Text(switch (recorded.mode) {
            CommuteMode.bike => l10n.commute_recorded_bike,
            CommuteMode.car => l10n.commute_recorded_car(dayLabel(l10n, recorded)),
            CommuteMode.remote => l10n.commute_recorded_remote,
          }),
          trailing: recorded.isRemote ? null : Text(
            format.euros(recorded.amount),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: recorded.isBike ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final trip = _price == null ? null : _settings.tripValue(_price!.pricePerLitre);
    // Une marge horizontale explicite : `symmetric(vertical:)` seul la remet a
    // zero, et l'icone venait se coller au bord arrondi du bouton.
    const padding = EdgeInsets.symmetric(horizontal: 16, vertical: 12);
    // Ni titleSmall ni labelSmall tels quels : ils portent la couleur du theme
    // et ecrasaient celle du bouton, texte clair sur fond clair.
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          flex: 3,
          child: FilledButton.icon(
            onPressed: _busy ? null : _recordBike,
            icon: const Icon(Icons.pedal_bike),
            style: FilledButton.styleFrom(padding: padding, alignment: Alignment.centerLeft),
            label: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.commute_by_bike,
                  style: TextStyle(fontSize: theme.textTheme.titleSmall?.fontSize),
                ),
                if (trip != null)
                  Text(
                    l10n.commute_by_bike_gain(format.euros(trip)),
                    style: TextStyle(
                      fontSize: theme.textTheme.labelSmall?.fontSize,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: OutlinedButton.icon(
            onPressed: _busy ? null : _recordCar,
            icon: const Icon(Icons.directions_car_outlined),
            style: OutlinedButton.styleFrom(padding: padding),
            label: Text(l10n.commute_by_car),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.outlined(
          onPressed: _busy ? null : _recordRemote,
          tooltip: l10n.commute_remote,
          color: remoteColor(scheme),
          icon: const Icon(Icons.home_work_outlined),
        ),
      ]),
    );
  }

  /// L'argent du mois : ce qui reste a partir, et ce que le velo a mis de cote.
  Widget _money(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = SubscriptionFormat(context);
    final endOfMonth = DateTime(_today.year, _today.month, daysInMonth(_today.year, _today.month));
    final upcoming = _subscriptions.paymentsIn(_today, endOfMonth);
    final next = upcoming.isEmpty ? null : upcoming.first;

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: _openBudget,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Text(
                  l10n.home_month.toUpperCase(),
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant, letterSpacing: 0.8),
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: scheme.outline),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: _figure(
                  context,
                  amount: format.euros(SubscriptionLedger.totalOf(upcoming)),
                  label: l10n.sub_remaining,
                  color: scheme.secondary,
                ),
              ),
              Container(
                width: 1,
                height: 38,
                // Marges de part et d'autre : colle au chiffre, le filet se
                // lisait comme un caractere de plus.
                margin: const EdgeInsets.symmetric(horizontal: 14),
                color: theme.dividerColor,
              ),
              Expanded(
                child: _figure(
                  context,
                  amount: format.euros(_commute.balance),
                  label: l10n.commute_pot,
                  color: scheme.primary,
                ),
              ),
            ]),
            if (next != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(children: [
                  Icon(Icons.event_outlined, size: 16, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_whenLabel(l10n, next.date)} · ${next.subscription.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  Text(
                    format.euros(next.amount),
                    style: theme.textTheme.labelLarge,
                  ),
                ]),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  /// Le temps passe aujourd'hui sur les reseaux, face au quota du jour.
  Widget _freeTimeCard(BuildContext context, AppLocalizations l10n, ScreenTimeLedger ledger) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = SubscriptionFormat(context);
    final quota = ledger.todayQuota;
    final minutes = ledger.live.minutes;
    final color = ledger.todayUnderQuota ? scheme.primary : scheme.tertiary;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            l10n.bb_free_time.toUpperCase(),
            style: theme.textTheme.labelSmall
                ?.copyWith(color: scheme.onSurfaceVariant, letterSpacing: 0.8),
          ),
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Text(formatMinutes(l10n, minutes),
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: color)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(l10n.free_today_quota(formatMinutes(l10n, quota)),
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ),
            Text(format.euros(ledger.balance),
                style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary)),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: quota <= 0 ? 1 : (minutes / quota).clamp(0.0, 1.0),
              minHeight: 6,
              color: color,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${l10n.free_streak_days(ledger.streak)} · ${l10n.free_streak}',
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
          ),
        ]),
      ),
    );
  }

  String _whenLabel(AppLocalizations l10n, DateTime date) {
    final days = date.difference(_today).inDays;
    return switch (days) {
      0 => l10n.sub_today,
      1 => l10n.sub_tomorrow,
      _ => SubscriptionFormat(context).shortDay(date),
    };
  }

  Widget _figure(
    BuildContext context, {
    required String amount,
    required String label,
    required Color color,
  }) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          amount,
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: color),
        ),
      ),
      const SizedBox(height: 2),
      Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline),
      ),
    ]);
  }

  Widget _pi(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final snapshot = _system;

    if (snapshot == null) {
      return _statusCard(
        context,
        icon: Icons.developer_board,
        title: l10n.system_title,
        detail: _systemError == null
            ? null
            : _systemError is QbNotConfiguredException
                ? l10n.home_pi_not_configured
                : l10n.home_pi_unreachable,
      );
    }

    final stats = snapshot.stats;
    final active =
        snapshot.services.where((service) => service.state == ServiceState.active).length;
    final volume = snapshot.volumes.isEmpty ? null : snapshot.volumes.first;
    final used = volume?.totalBytes != null && volume?.usedBytes != null && volume!.totalBytes! > 0
        ? volume.usedBytes! / volume.totalBytes!
        : null;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                // Rouge seulement quand plus rien ne tourne : un service
                // arrete volontairement ne merite pas la couleur d'erreur.
                color: switch (active) {
                  0 => scheme.error,
                  _ when active == snapshot.services.length => scheme.primary,
                  _ => scheme.tertiary,
                },
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                stats.hostname.isEmpty ? l10n.system_title : stats.hostname,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            Text(
              formatUptime(stats.uptimeSeconds),
              style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: _metric(
                context,
                value: stats.cpuTempC == null
                    ? '—'
                    : '${stats.cpuTempC!.toStringAsFixed(0)} °C',
                // Libelles courts : « Température CPU » se coupe au quart de
                // la largeur, et la valeur perd alors son unite de sens.
                label: l10n.home_metric_temp,
              ),
            ),
            Expanded(
              child: _metric(
                context,
                value: stats.load1.toStringAsFixed(2),
                label: l10n.home_metric_load,
              ),
            ),
            Expanded(
              child: _metric(
                context,
                value: used == null ? '—' : '${(used * 100).round()} %',
                label: l10n.home_disk,
              ),
            ),
            Expanded(
              child: _metric(
                context,
                value: '$active/${snapshot.services.length}',
                label: l10n.home_metric_services,
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _metric(BuildContext context, {required String value, required String label}) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(value, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
      const SizedBox(height: 2),
      Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline),
      ),
    ]);
  }

  Widget _downloads(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final snapshot = _torrents;

    if (snapshot == null) {
      return _statusCard(
        context,
        icon: Icons.download,
        title: l10n.torrents_title,
        detail: _torrentsError == null
            ? null
            : _torrentsError is QbNotConfiguredException
                ? l10n.not_configured_message
                : l10n.error_unreachable,
      );
    }

    final running = [
      for (final torrent in snapshot.torrents)
        if (torrent.progress < 1) torrent,
    ]..sort((a, b) => b.progress.compareTo(a.progress));

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(Icons.download, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                running.isEmpty ? l10n.home_downloads_none : l10n.torrents_title,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            if (running.isNotEmpty)
              Text(
                formatSpeed(snapshot.transfer.dlInfoSpeed),
                style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline),
              ),
          ]),
          for (final torrent in running.take(2)) ...[
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: Text(
                  torrent.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatProgress(torrent.progress),
                style: theme.textTheme.labelSmall?.copyWith(color: scheme.primary),
              ),
            ]),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(value: torrent.progress, minHeight: 5),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _fuel(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final price = _price;

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: const Icon(Icons.local_gas_station),
        title: Text(
          price == null
              ? l10n.home_no_fuel
              : '${fuelLabel(l10n, _settings.fuel)} · '
                  '${SubscriptionFormat(context).perLitre(price.pricePerLitre)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: price?.stationLabel == null
            ? null
            : Text(
                l10n.home_fuel_station(price!.stationLabel!, _stationCount),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
              ),
      ),
    );
  }

  /// Une carte reduite a son titre, quand la source n'a rien donne.
  Widget _statusCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String? detail,
  }) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(icon, color: theme.colorScheme.outline),
        title: Text(title, style: theme.textTheme.bodyMedium),
        subtitle: detail == null ? null : Text(detail),
        trailing: detail == null
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : null,
      ),
    );
  }
}
