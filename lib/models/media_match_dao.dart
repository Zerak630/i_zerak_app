/// Un film ou une serie identifie sur TMDB, et le nom de dossier qu'Emby en
/// deduira.
///
/// Dart pur, sans import Flutter, pour rester testable avec `package:test`.
enum MediaKind {
  movie,
  tv;

  static MediaKind? fromApi(String? raw) => switch (raw) {
        'movie' => movie,
        'tv' => tv,
        _ => null,
      };
}

class MediaMatch {
  const MediaMatch({
    required this.tmdbId,
    required this.kind,
    required this.title,
    this.year,
    this.posterPath,
  });

  final int tmdbId;
  final MediaKind kind;
  final String title;
  final int? year;
  final String? posterPath;

  /// `/search/multi` melange films, series et personnes. Renvoie null pour tout
  /// ce qui n'est pas un titre.
  static MediaMatch? fromSearchJson(Map<String, dynamic> json) {
    final kind = MediaKind.fromApi(json['media_type'] as String?);
    if (kind == null) {
      return null;
    }
    final id = (json['id'] as num?)?.toInt();
    if (id == null) {
      return null;
    }
    // Les films portent title/release_date, les series name/first_air_date.
    final title = (json['title'] ?? json['name']) as String?;
    if (title == null || title.isEmpty) {
      return null;
    }
    return MediaMatch(
      tmdbId: id,
      kind: kind,
      title: title,
      year: _year((json['release_date'] ?? json['first_air_date']) as String?),
      posterPath: json['poster_path'] as String?,
    );
  }

  static int? _year(String? date) {
    if (date == null || date.length < 4) {
      return null;
    }
    return int.tryParse(date.substring(0, 4));
  }

  /// Nom de dossier reconnu par Emby.
  ///
  /// La forme `Titre (Annee) [tmdbid=123456]` force la correspondance et evite
  /// les erreurs d'identification sur les titres ambigus, les remakes et les
  /// traductions.
  ///
  /// **Le signe egal n'est pas une coquille.** C'est la forme documentee par
  /// Emby (`Casino Royale (2006) [tmdbid=36557]`) ; Jellyfin, lui, attend un
  /// tiret. Ne pas « corriger » l'un en l'autre sans savoir lequel des deux
  /// serveurs lit la bibliotheque.
  ///
  /// `tmdbId` n'etant jamais nul, le tag est toujours present : contrairement a
  /// l'identifiant IMDb qu'il remplace, il ne demande aucun appel reseau
  /// supplementaire, il est deja dans le resultat de recherche.
  String embyFolderName() {
    final buffer = StringBuffer(sanitizeForFileSystem(title));
    if (year != null) {
      buffer.write(' ($year)');
    }
    buffer.write(' [tmdbid=$tmdbId]');
    return buffer.toString();
  }

  @override
  String toString() => 'MediaMatch($tmdbId, ${kind.name}, $title, $year)';
}

/// Longueur retenue pour le seul titre : la plupart des systemes de fichiers
/// plafonnent un composant de chemin a 255 octets, et le suffixe annee plus
/// identifiant TMDB doit encore tenir.
const int _maxTitleLength = 150;

/// Rend un titre utilisable comme nom de dossier.
///
/// Sans cela, un titre contenant `:` ou `/` fait echouer `torrents/add` cote
/// serveur, avec un message opaque.
String sanitizeForFileSystem(String raw) {
  var value = raw
      // Le deux-points separe generalement un titre de son sous-titre : le
      // remplacer par un tiret conserve la lisibilite.
      .replaceAll(':', ' -')
      .replaceAll(RegExp(r'[/\\*?"<>|]'), ' ')
      // Caracteres de controle.
      .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  if (value.length > _maxTitleLength) {
    value = value.substring(0, _maxTitleLength).trim();
  }

  // Windows refuse les noms finissant par un point ou une espace, et Samba
  // propage la contrainte depuis un partage Linux.
  value = value.replaceAll(RegExp(r'[. ]+$'), '');

  return value.isEmpty ? 'Sans titre' : value;
}
