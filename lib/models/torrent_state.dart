/// Etat d'un torrent tel que rapporte par qBittorrent.
///
/// Dart pur, sans import Flutter : le rendu (icone, couleur, libelle traduit)
/// vit dans `lib/pages/torrents/widgets/torrent_state_style.dart`, ce qui garde
/// ce fichier testable avec `package:test`.
enum TorrentState {
  error,
  missingFiles,
  uploading,
  pausedUp,
  queuedUp,
  stalledUp,
  checkingUp,
  forcedUp,
  allocating,
  downloading,
  metaDl,
  forcedMetaDl,
  pausedDl,
  queuedDl,
  stalledDl,
  checkingDl,
  forcedDl,
  checkingResumeData,
  moving,
  unknown;

  static const Map<String, TorrentState> _byApiName = <String, TorrentState>{
    'error': error,
    'missingFiles': missingFiles,
    'uploading': uploading,
    'pausedUP': pausedUp,
    // qBittorrent 5 a renomme les etats en pause : les deux graphies doivent
    // etre acceptees tant que la version du serveur n'est pas garantie.
    'stoppedUP': pausedUp,
    'queuedUP': queuedUp,
    'stalledUP': stalledUp,
    'checkingUP': checkingUp,
    'forcedUP': forcedUp,
    'allocating': allocating,
    'downloading': downloading,
    'metaDL': metaDl,
    'forcedMetaDL': forcedMetaDl,
    'pausedDL': pausedDl,
    'stoppedDL': pausedDl,
    'queuedDL': queuedDl,
    'stalledDL': stalledDl,
    'checkingDL': checkingDl,
    'forcedDL': forcedDl,
    'checkingResumeData': checkingResumeData,
    'moving': moving,
  };

  /// Un etat inconnu ne doit jamais faire echouer le parsing : les versions
  /// futures de qBittorrent peuvent en introduire.
  static TorrentState fromApi(String? raw) => _byApiName[raw] ?? unknown;

  bool get isPaused => this == pausedUp || this == pausedDl;

  bool get isCompleted =>
      this == uploading ||
      this == pausedUp ||
      this == queuedUp ||
      this == stalledUp ||
      this == checkingUp ||
      this == forcedUp;

  bool get isDownloading =>
      this == downloading || this == metaDl || this == forcedMetaDl || this == forcedDl;

  bool get isActive => this == downloading || this == uploading || this == metaDl;

  bool get isError => this == error || this == missingFiles;

  bool get isChecking =>
      this == checkingDl || this == checkingUp || this == checkingResumeData || this == moving;
}
