import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:i_zerak_app/models/agent_dao.dart';
import 'package:i_zerak_app/models/server_config_dao.dart';
import 'package:i_zerak_app/models/torrent_dao.dart';
import 'package:i_zerak_app/models/transfer_info_dao.dart';
import 'package:i_zerak_app/pages/settings/settings_page.dart';
import 'package:i_zerak_app/pages/torrents/widgets/add_magnet_sheet.dart';
import 'package:i_zerak_app/pages/torrents/widgets/delete_torrent_dialog.dart';
import 'package:i_zerak_app/pages/torrents/widgets/torrent_card.dart';
import 'package:i_zerak_app/pages/torrents/widgets/transfer_banner.dart';
import 'package:i_zerak_app/services/agent/agent_service.dart';
import 'package:i_zerak_app/services/qbittorrent/qb_exceptions.dart';
import 'package:i_zerak_app/services/qbittorrent/qb_service.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_server_config.dart';
import 'package:i_zerak_app/services/service_locator.dart';
import 'package:i_zerak_app/services/tmdb/tmdb_service.dart';

enum _View { loading, notConfigured, ready, error }

class TorrentsPage extends StatefulWidget {
  const TorrentsPage({super.key});

  @override
  State<TorrentsPage> createState() => _TorrentsPageState();
}

class _TorrentsPageState extends State<TorrentsPage> with WidgetsBindingObserver {
  final QbService _service = getIt<QbService>();
  final IServerConfig _configRepository = getIt<IServerConfig>();
  final TmdbService _tmdb = getIt<TmdbService>();
  final AgentService _agent = getIt<AgentService>();

  _View _view = _View.loading;
  List<TorrentDao> _torrents = const [];
  TransferInfoDao _transfer = const TransferInfoDao();
  QbException? _error;
  ServerConfig? _config;

  /// Volume qui empeche d'ajouter un telechargement : disque debranche, monte
  /// en lecture seule, ou quota atteint. Nul quand tout va bien, ou quand
  /// l'agent n'est pas installe.
  StorageVolume? _blockingVolume;

  Timer? _timer;

  /// Empeche l'empilement des requetes quand le serveur repond plus lentement
  /// que l'intervalle de rafraichissement.
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
    // Inutile d'interroger le serveur quand l'application n'est pas visible.
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
    final seconds = _config?.pollIntervalSeconds ?? 0;
    if (seconds <= 0) {
      return;
    }
    _timer = Timer.periodic(Duration(seconds: seconds), (_) => _refresh());
  }

  /// Coupe definitivement le rafraichissement automatique.
  ///
  /// Indispensable sur une erreur d'authentification : continuer a interroger
  /// le serveur avec de mauvais identifiants declencherait le bannissement de
  /// l'adresse au bout de cinq tentatives.
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
      final snapshot = await _service.snapshot();
      final blocking = await _checkStorage();
      if (!mounted) {
        return;
      }
      setState(() {
        _torrents = snapshot.torrents;
        _transfer = snapshot.transfer;
        _blockingVolume = blocking;
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
      if (error is QbAuthException || error is QbBannedException || error is QbCertificateException) {
        _stopPolling();
      }
      setState(() {
        _error = error;
        _view = _View.error;
      });
    } catch (error) {
      // Filet de securite : aucune exception ne doit remonter d'un timer.
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

  /// Interroge l'agent sur l'etat du disque de la bibliotheque.
  ///
  /// L'agent est facultatif : s'il n'est pas installe ou pas joignable, on ne
  /// bloque rien. Le garde-fou ne se declenche que sur une reponse explicite,
  /// jamais sur une absence de reponse.
  Future<StorageVolume?> _checkStorage() async {
    try {
      final volumes = await _agent.storage();
      for (final volume in volumes) {
        if (volume.blocksDownloads) {
          return volume;
        }
      }
      return null;
    } on QbException {
      return null;
    }
  }

  Future<void> _openSettings() async {
    _stopPolling();
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage()));
    if (!mounted) {
      return;
    }
    setState(() => _view = _View.loading);
    await _bootstrap();
  }

  Future<void> _onAction(TorrentDao torrent, TorrentAction action) async {
    try {
      switch (action) {
        case TorrentAction.pause:
          await _service.pause([torrent.hash]);
          break;
        case TorrentAction.resume:
          await _service.resume([torrent.hash]);
          break;
        case TorrentAction.delete:
          final deleteFiles = await showDeleteTorrentDialog(context, torrent.name);
          if (deleteFiles == null) {
            return;
          }
          await _service.delete([torrent.hash], deleteFiles: deleteFiles);
          break;
      }
      // Rafraichissement immediat : sans cela l'interface paraitrait figee
      // jusqu'au prochain battement du timer.
      await _refresh();
    } on QbException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_messageFor(context, error))));
    }
  }

  Future<void> _addMagnet() async {
    final config = _config;
    if (config == null) {
      return;
    }

    // Ajouter un telechargement alors que le disque externe est absent le
    // ferait atterrir sur la carte SD du Pi, jusqu'a la saturer.
    final blocking = _blockingVolume;
    if (blocking != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppLocalizations.of(context)!.storage_blocked_add),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
      return;
    }

    final request = await showAddMagnetSheet(context, config: config, tmdb: _tmdb);
    if (request == null || !mounted) {
      return;
    }

    try {
      await _service.addMagnet(
        request.magnet,
        savePath: request.savePath,
        category: request.category,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.torrent_added)));
      await _refresh();
    } on QbException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_messageFor(context, error))));
    }
  }

  String _messageFor(BuildContext context, QbException error) {
    final l10n = AppLocalizations.of(context)!;
    return switch (error) {
      QbNotConfiguredException() => l10n.error_not_configured,
      QbAuthException() => l10n.error_invalid_credentials,
      QbBannedException() => l10n.error_ip_banned,
      QbCertificateException() => l10n.error_certificate,
      QbNetworkException() => l10n.error_unreachable,
      QbTimeoutException() => l10n.error_timeout,
      QbHttpException() => l10n.error_unreachable,
      QbUnsupportedEndpointException() => l10n.error_unreachable,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: switch (_view) {
        _View.loading => const Center(child: CircularProgressIndicator()),
        _View.notConfigured => _placeholder(
            context,
            Icons.settings_ethernet,
            AppLocalizations.of(context)!.not_configured_message,
            AppLocalizations.of(context)!.configure,
            _openSettings,
          ),
        _View.error => _placeholder(
            context,
            Icons.cloud_off,
            _error == null ? '' : _messageFor(context, _error!),
            AppLocalizations.of(context)!.retry,
            () async {
              await _refresh();
              _startPolling();
            },
          ),
        _View.ready => _list(context),
      },
      floatingActionButton: _view == _View.ready
          ? FloatingActionButton(
              onPressed: _addMagnet,
              tooltip: _blockingVolume == null
                  ? AppLocalizations.of(context)!.add_magnet
                  : AppLocalizations.of(context)!.storage_blocked_add,
              backgroundColor: _blockingVolume == null
                  ? null
                  : Theme.of(context).colorScheme.surfaceVariant,
              child: Icon(_blockingVolume == null ? Icons.add : Icons.block),
            )
          : null,
    );
  }

  Widget _list(BuildContext context) => Column(
        children: [
          TransferBanner(transfer: _transfer),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: _torrents.isEmpty
                  // Enveloppe dans une liste defilable pour que le tirer-pour-
                  // rafraichir reste actif quand il n'y a aucun torrent.
                  ? ListView(
                      children: [
                        const SizedBox(height: 120),
                        Center(child: Text(AppLocalizations.of(context)!.no_torrents)),
                      ],
                    )
                  : ListView.builder(
                      itemCount: _torrents.length,
                      itemBuilder: (context, index) {
                        final torrent = _torrents[index];
                        return TorrentCard(
                          key: ValueKey<String>(torrent.hash),
                          torrent: torrent,
                          onAction: (action) => _onAction(torrent, action),
                        );
                      },
                    ),
            ),
          ),
        ],
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
