import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:i_zerak_app/models/agent_dao.dart';
import 'package:i_zerak_app/models/server_config_dao.dart';
import 'package:i_zerak_app/pages/settings/settings_page.dart';
import 'package:i_zerak_app/services/agent/agent_service.dart';
import 'package:i_zerak_app/services/qbittorrent/qb_exceptions.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_server_config.dart';
import 'package:i_zerak_app/services/service_locator.dart';
import 'package:i_zerak_app/utils/formatters.dart';

enum _View { loading, notConfigured, ready, error }

/// Supervision du Raspberry Pi : materiel, disque de la bibliotheque et
/// services.
class SystemPage extends StatefulWidget {
  const SystemPage({super.key});

  @override
  State<SystemPage> createState() => _SystemPageState();
}

class _SystemPageState extends State<SystemPage> with WidgetsBindingObserver {
  final AgentService _agent = getIt<AgentService>();
  final IServerConfig _configRepository = getIt<IServerConfig>();

  _View _view = _View.loading;
  SystemStats _stats = const SystemStats();
  List<StorageVolume> _volumes = const [];
  List<ServiceStatus> _services = const [];
  QbException? _error;
  ServerConfig? _config;

  Timer? _timer;
  bool _inFlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _timer?.cancel();
      _timer = null;
    } else if (state == AppLifecycleState.resumed && _view == _View.ready) {
      _refresh();
      _startPolling();
    }
  }

  Future<void> _bootstrap() async {
    _config = await _configRepository.read();
    await _refresh();
    _startPolling();
  }

  void _startPolling() {
    _timer?.cancel();
    // Les metriques materielles evoluent lentement : inutile de suivre la
    // cadence du suivi des torrents.
    final seconds = (_config?.pollIntervalSeconds ?? 0) <= 0 ? 0 : 10;
    if (seconds == 0) {
      return;
    }
    _timer = Timer.periodic(Duration(seconds: seconds), (_) => _refresh());
  }

  void _stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _refresh() async {
    if (_inFlight) {
      return;
    }
    _inFlight = true;
    try {
      final snapshot = await _agent.snapshot();
      if (!mounted) {
        return;
      }
      setState(() {
        _stats = snapshot.stats;
        _volumes = snapshot.volumes;
        _services = snapshot.services;
        _error = null;
        _view = _View.ready;
      });
    } on QbNotConfiguredException {
      if (!mounted) {
        return;
      }
      _stopPolling();
      setState(() => _view = _View.notConfigured);
    } on QbException catch (error) {
      if (!mounted) {
        return;
      }
      if (error is QbAuthException || error is QbCertificateException) {
        _stopPolling();
      }
      setState(() {
        _error = error;
        _view = _View.error;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = QbNetworkException(error.toString());
        _view = _View.error;
      });
    } finally {
      _inFlight = false;
    }
  }

  Future<void> _openSettings() async {
    _stopPolling();
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage()));
    if (!mounted) {
      return;
    }
    _agent.invalidate();
    setState(() => _view = _View.loading);
    await _bootstrap();
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

    return switch (_view) {
      _View.loading => const Center(child: CircularProgressIndicator()),
      _View.notConfigured => _placeholder(context, Icons.developer_board,
          l10n.agent_not_configured_message, l10n.configure, _openSettings),
      _View.error => _placeholder(context, Icons.cloud_off,
          _error == null ? '' : _messageFor(context, _error!), l10n.retry, () async {
          await _refresh();
          _startPolling();
        }),
      _View.ready => RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(8.0),
            children: [
              if (_stats.throttled.hasWarning) _throttleWarning(context, l10n),
              _hardwareCard(context, l10n),
              ..._volumes.map((volume) => _storageCard(context, l10n, volume)),
              _servicesCard(context, l10n),
            ],
          ),
        ),
    };
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
            _row(context, Icons.schedule, l10n.uptime, formatUptime(_stats.uptimeSeconds)),
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
            volume.reason == 'not_mounted' || volume.reason == 'same_device_as_root'
                ? l10n.storage_disconnected
                : l10n.storage_missing(volume.path),
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
                trailing: PopupMenuButton<ServiceCommand>(
                  onSelected: (command) => _runCommand(service, command),
                  itemBuilder: (context) => [
                    if (!service.state.isRunning)
                      PopupMenuItem(
                          value: ServiceCommand.start, child: Text(l10n.service_start)),
                    if (service.state.isRunning) ...[
                      PopupMenuItem(
                          value: ServiceCommand.restart, child: Text(l10n.service_restart)),
                      PopupMenuItem(
                        value: ServiceCommand.stop,
                        child: Text(l10n.service_stop,
                            style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      );

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

  Widget _row(BuildContext context, IconData icon, String label, String value, {Color? color}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color ?? Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
            Text(value,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600, color: color)),
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
