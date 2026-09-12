import 'dart:async';

import 'package:flutter/material.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/agent_dao.dart';
import 'package:i_zerak_app/pages/settings/settings_page.dart';
import 'package:i_zerak_app/services/agent/agent_service.dart';
import 'package:i_zerak_app/services/qbittorrent/qb_exceptions.dart';
import 'package:i_zerak_app/services/service_locator.dart';
import 'package:i_zerak_app/utils/formatters.dart';
import 'package:url_launcher/url_launcher.dart';

enum _View { loading, notConfigured, ready, error }

/// Supervision du Raspberry Pi : materiel, disque de la bibliotheque et
/// services.
///
/// Le rafraichissement est **manuel uniquement** : bouton, ou tirer vers le
/// bas. Un instantane coute trois requetes HTTPS successives a un Pi 3B+, et
/// les repeter en fond faisait surgir « Agent injoignable » a la moindre
/// hesitation du reseau, pour des metriques qui evoluent lentement. Entre deux
/// releves, seule la duree de fonctionnement avance, calculee localement.
class SystemPage extends StatefulWidget {
  const SystemPage({super.key});

  @override
  State<SystemPage> createState() => _SystemPageState();
}

class _SystemPageState extends State<SystemPage> {
  final AgentService _agent = getIt<AgentService>();

  _View _view = _View.loading;
  SystemStats _stats = const SystemStats();
  List<StorageVolume> _volumes = const [];
  List<ServiceStatus> _services = const [];
  QbException? _error;

  /// Instant de la derniere releve reussie. Sert d'origine au compteur de duree
  /// de fonctionnement, et date les valeurs affichees.
  DateTime? _fetchedAt;

  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    // Apres le premier rendu, et non pendant : _refresh appelle setState des sa
    // premiere ligne, ce qui est interdit tant que la page n'a pas ete
    // construite une fois. Le garde couvre le changement d'onglet immediat.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _refresh();
      }
    });
  }

  Future<void> _refresh() async {
    if (_refreshing || !mounted) {
      return;
    }
    setState(() => _refreshing = true);
    try {
      final snapshot = await _agent.snapshot();
      if (!mounted) {
        return;
      }
      setState(() {
        _stats = snapshot.stats;
        _volumes = snapshot.volumes;
        _services = snapshot.services;
        _fetchedAt = DateTime.now();
        _error = null;
        _view = _View.ready;
      });
    } on QbNotConfiguredException {
      if (!mounted) {
        return;
      }
      setState(() => _view = _View.notConfigured);
    } on QbException catch (error) {
      _reportFailure(error);
    } catch (error) {
      // Filet de securite : aucune exception ne doit remonter d'un geste de
      // rafraichissement.
      _reportFailure(QbNetworkException(error.toString()));
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  /// Un echec ne remplace l'ecran que si rien n'a encore ete affiche.
  ///
  /// Une fois des donnees a l'ecran, les effacer pour un incident passager
  /// serait une perte seche : le Pi ne repond pas toujours du premier coup, et
  /// des chiffres d'il y a deux minutes valent mieux qu'une page d'erreur. Le
  /// message passe alors par un bandeau, et la ligne « mis a jour a » dit
  /// d'elle-meme que la releve date.
  void _reportFailure(QbException error) {
    if (!mounted) {
      return;
    }
    final hasData = _view == _View.ready;
    setState(() {
      _error = error;
      if (!hasData) {
        _view = _View.error;
      }
    });
    if (hasData) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_messageFor(context, error))));
    }
  }

  Future<void> _openSettings() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage()));
    if (!mounted) {
      return;
    }
    _agent.invalidate();
    setState(() => _view = _View.loading);
    await _refresh();
  }

  Future<void> _runCommand(ServiceStatus service, ServiceCommand command) async {
    final l10n = AppLocalizations.of(context)!;

    // Arreter ou redemarrer coupe les telechargements en cours ou la lecture
    // en cours : la confirmation n'est pas negociable.
    if (command != ServiceCommand.start) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(command == ServiceCommand.stop
              ? l10n.service_stop
              : l10n.service_restart),
          content: Text(l10n.confirm_service_action(service.name)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
              child: Text(l10n.confirm),
            ),
          ],
        ),
      );
      if (confirmed != true) {
        return;
      }
    }

    // Etat optimiste : systemd n'est pas instantane et l'interface paraitrait
    // figee sans cela.
    setState(() {
      _services = _services
          .map((item) => item.name == service.name
              ? item.copyWith(state: ServiceState.activating)
              : item)
          .toList(growable: false);
    });

    try {
      await _agent.command(service.name, command);
      // Un seul rafraichissement afficherait souvent encore l'ancien etat :
      // systemd met quelques secondes a stabiliser une unite.
      for (final delay in const [1, 3, 6]) {
        await Future<void>.delayed(Duration(seconds: delay));
        if (!mounted) {
          return;
        }
        await _refresh();
      }
    } on QbException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_messageFor(context, error))));
      await _refresh();
    }
  }

  /// Ouvre l'interface web dans le navigateur, et non dans une vue integree :
  /// on y retrouve ses onglets, et une appli comme Cora s'y utilise ensuite
  /// sans repasser par iZerak.
  Future<void> _openWeb(ServiceStatus service) async {
    final l10n = AppLocalizations.of(context)!;
    var opened = false;
    try {
      final uri = await _agent.webUri(service);
      opened = uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Exception {
      opened = false;
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.service_open_failed(service.name))));
    }
  }

  String _messageFor(BuildContext context, QbException error) {
    final l10n = AppLocalizations.of(context)!;
    return switch (error) {
      QbNotConfiguredException() => l10n.error_not_configured,
      QbAuthException() => l10n.error_agent_token,
      QbBannedException() => l10n.error_ip_banned,
      QbCertificateException() => l10n.error_certificate,
      QbNetworkException() => l10n.error_agent_unreachable,
      QbTimeoutException() => l10n.error_timeout,
      QbHttpException() => l10n.error_agent_unreachable,
      QbUnsupportedEndpointException() => l10n.error_agent_unreachable,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      body: switch (_view) {
        _View.loading => const Center(child: CircularProgressIndicator()),
        _View.notConfigured => _placeholder(context, Icons.developer_board,
            l10n.agent_not_configured_message, l10n.configure, _openSettings),
        _View.error => _placeholder(context, Icons.cloud_off,
            _error == null ? '' : _messageFor(context, _error!), l10n.retry, _refresh),
        _View.ready => RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(8.0),
              children: [
                if (_stats.throttled.hasWarning) _throttleWarning(context, l10n),
                _hardwareCard(context, l10n),
                ..._volumes.map((volume) => _storageCard(context, l10n, volume)),
                _servicesCard(context, l10n),
                _lastUpdated(context, l10n),
              ],
            ),
          ),
      },
      // Le rafraichissement est un geste, jamais un minuteur.
      floatingActionButton: _view == _View.ready
          ? FloatingActionButton(
              onPressed: _refreshing ? null : _refresh,
              tooltip: l10n.refresh,
              child: _refreshing
                  ? const SizedBox(
                      width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh),
            )
          : null,
    );
  }

  /// Date les valeurs affichees : sans minuteur, rien d'autre ne dit leur age.
  Widget _lastUpdated(BuildContext context, AppLocalizations l10n) {
    final fetchedAt = _fetchedAt;
    if (fetchedAt == null) {
      return const SizedBox.shrink();
    }
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(fetchedAt),
      alwaysUse24HourFormat: MediaQuery.of(context).alwaysUse24HourFormat,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 88),
      child: Text(
        l10n.last_updated(time),
        textAlign: TextAlign.center,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }

  Widget _throttleWarning(BuildContext context, AppLocalizations l10n) {
    final flags = _stats.throttled;
    // La sous-tension actuelle est un probleme en cours ; « survenue » signale
    // un incident passe, qui explique souvent des pannes deja constatees.
    final message = flags.underVoltageNow
        ? l10n.undervoltage_now
        : flags.underVoltageOccurred
            ? l10n.undervoltage_occurred
            : l10n.throttling_occurred;

    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      margin: const EdgeInsets.all(8.0),
      child: ListTile(
        leading: Icon(Icons.bolt, color: Theme.of(context).colorScheme.onErrorContainer),
        title: Text(message,
            style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
      ),
    );
  }

  Widget _hardwareCard(BuildContext context, AppLocalizations l10n) {
    final temp = _stats.cpuTempC;
    final tempColor = temp == null
        ? null
        : temp < 60
            ? Colors.green
            : temp < 75
                ? Colors.orange
                : Theme.of(context).colorScheme.error;

    return Card(
      margin: const EdgeInsets.all(8.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_stats.model ?? _stats.hostname,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _row(
              context,
              Icons.schedule,
              l10n.uptime,
              formatUptime(_stats.uptimeSeconds),
              // La duree de fonctionnement est la seule grandeur dont on
              // connait l'evolution sans redemander : elle avance d'une seconde
              // par seconde. La faire vivre localement evite une requete.
              valueWidget: _fetchedAt == null
                  ? null
                  : _UptimeTicker(baseSeconds: _stats.uptimeSeconds, fetchedAt: _fetchedAt!),
            ),
            _row(context, Icons.speed, l10n.load_average,
                '${_stats.load1.toStringAsFixed(2)} · ${_stats.load5.toStringAsFixed(2)} · ${_stats.load15.toStringAsFixed(2)}'),
            if (temp != null)
              _row(context, Icons.thermostat, l10n.cpu_temp, '$temp °C', color: tempColor),
            if (_stats.memUsedBytes != null && _stats.memTotalBytes != null)
              _row(context, Icons.memory, l10n.memory,
                  '${formatBytes(_stats.memUsedBytes!)} / ${formatBytes(_stats.memTotalBytes!)}'),
          ],
        ),
      ),
    );
  }

  Widget _storageCard(BuildContext context, AppLocalizations l10n, StorageVolume volume) {
    final scheme = Theme.of(context).colorScheme;

    // L'etat du disque passe avant les chiffres : c'est la question posee.
    if (!volume.mounted) {
      return Card(
        color: scheme.errorContainer,
        margin: const EdgeInsets.all(8.0),
        child: ListTile(
          leading: Icon(Icons.usb_off, color: scheme.onErrorContainer),
          title: Text(volume.label, style: TextStyle(color: scheme.onErrorContainer)),
          subtitle: Text(
            switch (volume.reason) {
              // Le point de montage existe mais rien n'y est monte, ou il
              // pointe vers la racine : dans les deux cas, le disque est absent.
              'not_mounted' || 'same_device_as_root' => l10n.storage_disconnected,
              // L'agent n'a pas le droit de traverser le repertoire parent.
              'permission_denied' => l10n.storage_permission_denied,
              _ => l10n.storage_missing(volume.path),
            },
            style: TextStyle(color: scheme.onErrorContainer),
          ),
        ),
      );
    }

    final ratio = volume.quotaRatio;
    final barColor = ratio == null
        ? scheme.primary
        : ratio >= 0.95
            ? scheme.error
            : ratio >= 0.8
                ? Colors.orange
                : scheme.primary;

    return Card(
      margin: const EdgeInsets.all(8.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.storage, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                    child:
                        Text(volume.label, style: Theme.of(context).textTheme.titleMedium)),
              ],
            ),
            if (volume.readonly) ...[
              const SizedBox(height: 8),
              // Present mais plus inscriptible : c'est ainsi que le noyau
              // remonte un disque USB defaillant.
              Row(
                children: [
                  const Icon(Icons.lock, size: 16, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(l10n.storage_readonly,
                          style: const TextStyle(color: Colors.orange))),
                ],
              ),
            ],
            const SizedBox(height: 12),
            if (ratio != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: ratio, minHeight: 8, color: barColor),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.storage_quota(
                    formatBytes(volume.usedBytes ?? 0), formatBytes(volume.quotaBytes ?? 0)),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            if (volume.totalBytes != null)
              Text(
                l10n.storage_capacity(
                    formatBytes(volume.freeBytes ?? 0), formatBytes(volume.totalBytes!)),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }

  Widget _servicesCard(BuildContext context, AppLocalizations l10n) => Card(
        margin: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            for (final service in _services)
              ListTile(
                leading: Icon(
                  service.state.isTransitioning ? Icons.autorenew : Icons.circle,
                  size: service.state.isTransitioning ? 20 : 14,
                  color: switch (service.state) {
                    ServiceState.active => Colors.green,
                    ServiceState.failed => Theme.of(context).colorScheme.error,
                    ServiceState.activating ||
                    ServiceState.deactivating =>
                      Colors.orange,
                    _ => Theme.of(context).colorScheme.onSurfaceVariant,
                  },
                ),
                title: Text(service.name),
                subtitle: Text(_serviceSubtitle(context, l10n, service)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (service.web != null)
                      IconButton(
                        icon: const Icon(Icons.open_in_new),
                        tooltip: l10n.service_open,
                        onPressed: () => _openWeb(service),
                      ),
                    if (_commandsFor(service).isNotEmpty)
                      PopupMenuButton<ServiceCommand>(
                        onSelected: (command) => _runCommand(service, command),
                        itemBuilder: (context) => [
                          for (final command in _commandsFor(service))
                            PopupMenuItem(
                              value: command,
                              child: switch (command) {
                                ServiceCommand.start => Text(l10n.service_start),
                                ServiceCommand.restart => Text(l10n.service_restart),
                                ServiceCommand.stop => Text(l10n.service_stop,
                                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
                              },
                            ),
                        ],
                      ),
                  ],
                ),
              ),
          ],
        ),
      );

  /// Commandes proposees : celles qui ont un sens dans l'etat courant, parmi
  /// celles que l'agent permet pour ce service.
  List<ServiceCommand> _commandsFor(ServiceStatus service) => [
        if (!service.state.isRunning) ServiceCommand.start,
        if (service.state.isRunning) ...[ServiceCommand.restart, ServiceCommand.stop],
      ].where((command) => service.actions.contains(command.name)).toList(growable: false);

  String _serviceSubtitle(BuildContext context, AppLocalizations l10n, ServiceStatus service) {
    final label = switch (service.state) {
      ServiceState.active => l10n.service_active,
      ServiceState.inactive => l10n.service_inactive,
      ServiceState.failed => l10n.service_failed,
      ServiceState.activating => l10n.service_activating,
      ServiceState.deactivating => l10n.service_deactivating,
      ServiceState.unknown => l10n.state_unknown,
    };
    if (service.memoryBytes == null) {
      return label;
    }
    return '$label · ${formatBytes(service.memoryBytes!)}';
  }

  Widget _row(
    BuildContext context,
    IconData icon,
    String label,
    String value, {
    Color? color,
    Widget? valueWidget,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color ?? Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
            DefaultTextStyle.merge(
              style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600, color: color) ??
                  const TextStyle(),
              child: valueWidget ?? Text(value),
            ),
          ],
        ),
      );

  Widget _placeholder(
    BuildContext context,
    IconData icon,
    String message,
    String actionLabel,
    Future<void> Function() onAction,
  ) =>
      Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton(onPressed: onAction, child: Text(actionLabel)),
            ],
          ),
        ),
      );
}

/// Duree de fonctionnement qui avance seule entre deux releves.
///
/// L'affichage repart de la valeur rapportee par l'agent et y ajoute le temps
/// ecoule depuis, mesure a l'horloge murale et non par comptage de battements :
/// une application mise en arriere-plan puis reprise retrouve ainsi la bonne
/// valeur, alors qu'un compteur incremente aurait pris du retard.
///
/// Le minuteur bat chaque seconde mais ne reconstruit que lorsque le texte
/// change reellement — au-dela d'une heure, le format n'affiche plus les
/// secondes, et il n'y aurait rien a redessiner.
class _UptimeTicker extends StatefulWidget {
  const _UptimeTicker({required this.baseSeconds, required this.fetchedAt});

  final int baseSeconds;
  final DateTime fetchedAt;

  @override
  State<_UptimeTicker> createState() => _UptimeTickerState();
}

class _UptimeTickerState extends State<_UptimeTicker> {
  Timer? _timer;
  late String _label = _compute();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void didUpdateWidget(_UptimeTicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Une nouvelle releve replace l'origine du compteur.
    if (oldWidget.baseSeconds != widget.baseSeconds || oldWidget.fetchedAt != widget.fetchedAt) {
      _label = _compute();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }

  String _compute() =>
      formatUptimeSince(widget.baseSeconds, widget.fetchedAt, DateTime.now());

  void _tick() {
    final next = _compute();
    if (next != _label && mounted) {
      setState(() => _label = next);
    }
  }

  @override
  Widget build(BuildContext context) => Text(_label);
}
