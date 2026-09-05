import 'package:flutter/material.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/torrent_state.dart';

/// Rendu d'un etat de torrent : icone, couleur et libelle traduit.
///
/// Volontairement separe du modele, qui doit rester du Dart pur pour etre
/// testable avec `package:test`, sans dependance a Flutter.
extension TorrentStateStyle on TorrentState {
  IconData get icon => switch (this) {
        TorrentState.downloading || TorrentState.forcedDl => Icons.download,
        TorrentState.metaDl || TorrentState.forcedMetaDl => Icons.hourglass_top,
        TorrentState.uploading || TorrentState.forcedUp => Icons.upload,
        TorrentState.pausedDl || TorrentState.pausedUp => Icons.pause_circle,
        TorrentState.queuedDl || TorrentState.queuedUp => Icons.schedule,
        TorrentState.stalledDl || TorrentState.stalledUp => Icons.pending,
        TorrentState.checkingDl ||
        TorrentState.checkingUp ||
        TorrentState.checkingResumeData =>
          Icons.fact_check,
        TorrentState.moving => Icons.drive_file_move,
        TorrentState.allocating => Icons.sd_storage,
        TorrentState.error || TorrentState.missingFiles => Icons.error,
        TorrentState.unknown => Icons.help_outline,
      };

  Color color(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (isError) {
      return scheme.error;
    }
    if (isPaused) {
      return scheme.onSurfaceVariant;
    }
    if (isCompleted) {
      return Colors.green;
    }
    if (isChecking) {
      return Colors.orange;
    }
    return scheme.primary;
  }

  String label(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return switch (this) {
      TorrentState.downloading || TorrentState.forcedDl => l10n.state_downloading,
      TorrentState.metaDl || TorrentState.forcedMetaDl => l10n.state_fetching_metadata,
      TorrentState.uploading || TorrentState.forcedUp => l10n.state_uploading,
      TorrentState.pausedDl || TorrentState.pausedUp => l10n.state_paused,
      TorrentState.queuedDl || TorrentState.queuedUp => l10n.state_queued,
      TorrentState.stalledDl || TorrentState.stalledUp => l10n.state_stalled,
      TorrentState.checkingDl ||
      TorrentState.checkingUp ||
      TorrentState.checkingResumeData =>
        l10n.state_checking,
      TorrentState.moving => l10n.state_moving,
      TorrentState.allocating => l10n.state_allocating,
      TorrentState.error => l10n.state_error,
      TorrentState.missingFiles => l10n.state_missing_files,
      TorrentState.unknown => l10n.state_unknown,
    };
  }
}
