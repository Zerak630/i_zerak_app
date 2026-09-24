import 'package:flutter/material.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/agent_dao.dart';
import 'package:i_zerak_app/models/commute_dao.dart' hide dateOnly, roundCents;
import 'package:i_zerak_app/models/commute_dao.dart' as commute show dateOnly;
import 'package:i_zerak_app/models/subscription_dao.dart';
import 'package:i_zerak_app/pages/commute/widgets/car_reason_sheet.dart';
import 'package:i_zerak_app/pages/commute/widgets/commute_ui.dart'
    show carReasonLabel, showAddReasonDialog;
import 'package:i_zerak_app/pages/gas_stations/widgets/fuel_label.dart';
import 'package:i_zerak_app/pages/dashboard/budget_page.dart';
import 'package:i_zerak_app/pages/subscriptions/widgets/subscription_ui.dart';
import 'package:i_zerak_app/services/agent/agent_service.dart';
import 'package:i_zerak_app/services/commute_price_service.dart';
import 'package:i_zerak_app/services/qbittorrent/qb_exceptions.dart';
import 'package:i_zerak_app/services/qbittorrent/qb_service.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_commute.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_gas_stations.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_subscriptions.dart';
import 'package:i_zerak_app/services/service_locator.dart';
import 'package:i_zerak_app/utils/confirmation_snack_bar.dart';
import 'package:i_zerak_app/utils/formatters.dart';

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
    DateTime Function()? clock,
  })  : subscriptionService = subscriptionService ?? getIt<ISubscriptions>(),
        commuteService = commuteService ?? getIt<ICommute>(),
        prices = prices ?? getIt<CommutePriceService>(),
        stations = stations ?? getIt<IGasStations>(),
        systemLoader = systemLoader ?? getIt<AgentService>().snapshot,
        torrentsLoader = torrentsLoader ?? getIt<QbService>().snapshot,
        clock = clock ?? DateTime.now;

  final ISubscriptions subscriptionService;
  final ICommute commuteService;
  final CommutePriceService prices;
  final IGasStations stations;
  final Future<SystemSnapshot> Function() systemLoader;
  final Future<TorrentsSnapshot> Function() torrentsLoader;
  final DateTime Function() clock;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  CommuteSettings _settings = const CommuteSettings();
  CommuteLedger _commute = CommuteLedger(const [], const []);
  SubscriptionLedger _subscriptions = SubscriptionLedger(const []);
  int _stationCount = 0;

  ResolvedPrice? _price;
  SystemSnapshot? _system;
  Object? _systemError;
  TorrentsSnapshot? _torrents;
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
    await Future.wait([_loadPrice(), _loadSystem(), _loadTorrents()]);
  }

  Future<void> _loadLocal() async {
    final settings = await widget.commuteService.readSettings();
    final days = await widget.commuteService.getDays();
    final goals = await widget.commuteService.getGoals();
    final subscriptions = await widget.subscriptionService.getAll();
    final stations = await widget.stations.getAll();
    if (!mounted) {
      return;
    }
    setState(() {
      _settings = settings;
      _commute = CommuteLedger(days, goals);
      _subscriptions = SubscriptionLedger(subscriptions);
      _stationCount = stations.length;
    });
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
        final reason = await showCarReasonSheet(
          context,
          reasons: _settings.reasons,
          subtitle: l10n.commute_why_car_detail(
            format.longDay(_today),
            format.euros(_settings.tripValue(price.pricePerLitre)),
          ),
          onAddReason: _addReason,
        );
        if (reason == null) {
          return;
        }
        await widget.commuteService.saveDay(CommuteDay.car(_today, _settings, price, reason));
        await _loadLocal();
        if (mounted) {
          showConfirmation(context, l10n.commute_snack_car(carReasonLabel(l10n, reason)));
        }
      });

  /// Une raison ajoutee depuis l'accueil rejoint les reglages du trajet : les
  /// deux ecrans lisent la meme liste.
  Future<CarReason?> _addReason() async {
    final reason = await showAddReasonDialog(context);
    if (reason == null) {
      return null;
    }
    final settings = _settings.copyWith(reasons: [..._settings.reasons, reason]);
    await widget.commuteService.saveSettings(settings);
    if (mounted) {
      setState(() => _settings = settings);
    }
    return reason;
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

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text(
              format.longDay(_today),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 10),
            _today_(context, l10n),
            const SizedBox(height: 12),
            _money(context, l10n),
            const SizedBox(height: 12),
            _pi(context, l10n),
            const SizedBox(height: 12),
            _downloads(context, l10n),
            const SizedBox(height: 12),
            _fuel(context, l10n),
          ],
        ),
      ),
    );
  }

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
            recorded.isBike ? Icons.pedal_bike : Icons.directions_car_outlined,
            color: recorded.isBike ? scheme.primary : scheme.secondary,
          ),
          title: Text(recorded.isBike
              ? l10n.commute_recorded_bike
              : l10n.commute_recorded_car(dayLabelOf(l10n, recorded))),
          trailing: Text(
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
    return Row(children: [
      Expanded(
        flex: 3,
        child: FilledButton.icon(
          onPressed: _busy ? null : _recordBike,
          icon: const Icon(Icons.pedal_bike),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            alignment: Alignment.centerLeft,
          ),
          label: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l10n.commute_by_bike, style: theme.textTheme.titleSmall),
            if (trip != null)
              Text(
                l10n.commute_by_bike_gain(format.euros(trip)),
                style: theme.textTheme.labelSmall,
              ),
          ]),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        flex: 2,
        child: OutlinedButton.icon(
          onPressed: _busy ? null : _recordCar,
          icon: const Icon(Icons.directions_car_outlined),
          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
          label: Text(l10n.commute_by_car),
        ),
      ),
    ]);
  }

  /// Le nom de la raison retenue pour une journee en voiture.
  String dayLabelOf(AppLocalizations l10n, CommuteDay day) {
    for (final reason in _settings.reasons) {
      if (reason.id == day.reasonId) {
        return carReasonLabel(l10n, reason);
      }
    }
    return day.reasonLabel ?? '';
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
              Container(width: 1, height: 38, color: theme.dividerColor),
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
                color: active == snapshot.services.length ? scheme.primary : scheme.error,
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
                label: l10n.cpu_temp,
              ),
            ),
            Expanded(
              child: _metric(
                context,
                value: stats.load1.toStringAsFixed(2),
                label: l10n.load_average,
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
                label: l10n.home_services_ok(active, snapshot.services.length),
                showLabel: false,
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _metric(
    BuildContext context, {
    required String value,
    required String label,
    bool showLabel = true,
  }) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(value, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
      const SizedBox(height: 2),
      Text(
        showLabel ? label : label.split(' ').last,
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
