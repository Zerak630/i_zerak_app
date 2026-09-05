import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:i_zerak_app/models/torrent_dao.dart';
import 'package:i_zerak_app/pages/torrents/widgets/torrent_state_style.dart';
import 'package:i_zerak_app/utils/formatters.dart';

enum TorrentAction { pause, resume, delete }

class TorrentCard extends StatelessWidget {
  const TorrentCard({
    super.key,
    required this.torrent,
    required this.onAction,
  });

  final TorrentDao torrent;
  final void Function(TorrentAction action) onAction;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16.0, 12.0, 4.0, 12.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2.0),
              child: Icon(torrent.state.icon, color: torrent.state.color(context)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    torrent.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: torrent.progress.clamp(0.0, 1.0),
                      minHeight: 6,
                      color: torrent.state.color(context),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _summary(context),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            PopupMenuButton<TorrentAction>(
              // Pas de Dismissible ici : sur une liste qui se rafraichit toutes
              // les trois secondes, un glissement accidentel supprimerait un
              // telechargement.
              onSelected: onAction,
              itemBuilder: (context) => [
                if (torrent.state.isPaused)
                  PopupMenuItem(
                    value: TorrentAction.resume,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.play_arrow),
                      title: Text(l10n.resume),
                    ),
                  )
                else
                  PopupMenuItem(
                    value: TorrentAction.pause,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.pause),
                      title: Text(l10n.pause),
                    ),
                  ),
                PopupMenuItem(
                  value: TorrentAction.delete,
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                    title: Text(l10n.delete,
                        style: TextStyle(color: theme.colorScheme.error)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _summary(BuildContext context) {
    final parts = <String>[
      formatProgress(torrent.progress),
      formatBytes(torrent.size),
      torrent.state.label(context),
    ];

    if (torrent.dlspeed > 0) {
      parts.add('↓ ${formatSpeed(torrent.dlspeed)}');
    }
    if (torrent.upspeed > 0) {
      parts.add('↑ ${formatSpeed(torrent.upspeed)}');
    }
    // Le temps restant n'a de sens que pendant un telechargement actif.
    if (torrent.state.isDownloading && torrent.eta < kInfiniteEta && torrent.eta >= 0) {
      parts.add(formatEta(torrent.eta));
    }

    return parts.join(' · ');
  }
}
