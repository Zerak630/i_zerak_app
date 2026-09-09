import 'package:i_zerak_app/models/media_match_dao.dart';

/// Ou deposer un telechargement dans la bibliotheque Emby.
///
/// Dart pur, sans import Flutter, pour rester testable avec `package:test`.
///
/// `MediaKind` vient de TMDB et ne connait que le film et la serie : il ne peut
/// pas exprimer « Autres ». D'ou ce type distinct, qui est le seul a decider du
/// rangement.
enum TorrentDestination {
  films('Films'),
  series('Series'),
  autres('Autres');

  const TorrentDestination(this.folder);

  /// Segment de chemin **et** nom de categorie qBittorrent : les deux sont
  /// volontairement identiques, c'est ce qui reduit la duplication a trois
  /// constantes.
  ///
  /// Toujours en ASCII, jamais accentue et jamais derive d'une traduction :
  /// qBittorrent cree a la volee, sans erreur ni message, toute categorie qu'il
  /// ne connait pas, avec un chemin vide. Une faute de frappe passerait donc
  /// inapercue jusqu'a ce qu'on cherche les fichiers.
  final String folder;

  String get category => folder;

  /// TMDB ne connait que le film et la serie : tout le reste, absence de
  /// resultat comprise, tombe dans Autres.
  static TorrentDestination fromKind(MediaKind? kind) => switch (kind) {
        MediaKind.movie => films,
        MediaKind.tv => series,
        null => autres,
      };
}

/// Les champs de `torrents/add` qui decident du rangement.
///
/// Les booleens sont **nullables a dessein** : cote qBittorrent, `autoTMM` et
/// `root_folder` sont des tri-etats. Un champ absent laisse le reglage de
/// session decider ; envoyer `false` par defaut changerait le comportement du
/// serveur.
typedef AddTorrentOptions = ({
  String? savePath,
  String? category,
  bool? autoTmm,
  bool? createSubfolder,
});

/// Repertoire de la destination, `<racine>/Films` par exemple.
///
/// Renvoie null si la racine n'est pas configuree. Le test porte sur `isEmpty`
/// et non sur `!= null` : les reglages enregistrent une chaine vide, pas null,
/// quand le champ est laisse en blanc.
String? destinationPath({
  required String? libraryRoot,
  required TorrentDestination destination,
}) {
  final root = libraryRoot?.trim() ?? '';
  if (root.isEmpty) {
    return null;
  }
  return '${root.replaceAll(RegExp(r'/+$'), '')}/${destination.folder}';
}

/// Traduit un choix de destination en champs `torrents/add`.
///
/// Deux regimes, et le second n'est pas un detail :
///
/// - **Racine configuree** : l'application impose le chemin complet, dossier
///   Emby compris, et coupe explicitement la gestion automatique. Sans
///   `autoTMM=false`, un serveur regle en gestion automatique ignorerait
///   `savepath` **en silence** au profit du chemin de la categorie, et le
///   dossier `Titre (Annee) [tmdbid=...]` serait perdu sans le moindre message.
/// - **Racine absente** : surtout ne pas envoyer `autoTMM=false` avec un chemin
///   nul, ce serait le pire des deux mondes. On active au contraire la gestion
///   automatique et on laisse la categorie router. On perd le dossier Emby, on
///   ne perd pas la destination.
///
/// `createSubfolder: false` evite que qBittorrent glisse un dossier au nom de
/// la release entre le dossier Emby et les fichiers : Emby y verrait un second
/// film. C'est aussi ce qui permet a un pack de saison de se deverser a plat
/// dans le dossier de la serie.
AddTorrentOptions resolveAddOptions({
  required TorrentDestination destination,
  required String? basePath,
  required String folderName,
}) {
  final base = basePath?.trim() ?? '';
  if (base.isEmpty) {
    return (
      savePath: null,
      category: destination.category,
      autoTmm: true,
      createSubfolder: null,
    );
  }

  final folder = folderName.trim();
  final root = base.replaceAll(RegExp(r'/+$'), '');
  return (
    savePath: folder.isEmpty ? root : '$root/$folder',
    category: destination.category,
    autoTmm: false,
    createSubfolder: false,
  );
}
