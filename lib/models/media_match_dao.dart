/// Un film ou une serie identifie sur TMDB, et le nom de dossier qu'Emby en
/// deduira.
///
/// Dart pur, sans import Flutter, pour rester testable avec `package:test`.
enum MediaKind {
  movie('movie'),
  tv('tv');

  const MediaKind(this.apiPath);

  final String apiPath;

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
    this.imdbId,
  });

  final int tmdbId;
  final MediaKind kind;
  final String title;
  final int? year;
  final String? posterPath;

  /// Identifiant IMDb au format `tt1234567`, resolu via `/external_ids`.
  final String? imdbId;

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

  MediaMatch copyWith({String? imdbId}) => MediaMatch(
        tmdbId: tmdbId,
        kind: kind,
        title: title,
        year: year,
        posterPath: posterPath,
        imdbId: imdbId ?? this.imdbId,
      );

  String? get imdbUrl => imdbId == null ? null : 'https://www.imdb.com/title/$imdbId/';

  /// Nom de dossier reconnu par Emby et Jellyfin.
  ///
  /// La forme `Titre (Annee) [imdbid-tt1234567]` force la correspondance et
  /// evite les erreurs d'identification sur les titres ambigus, les remakes et
  /// les traductions. C'est le vrai interet d'associer un identifiant IMDb au
  /// telechargement.
  String embyFolderName() {
    final buffer = StringBuffer(sanitizeForFileSystem(title));
    if (year != null) {
      buffer.write(' ($year)');
    }
    if (imdbId != null && imdbId!.isNotEmpty) {
      buffer.write(' [imdbid-$imdbId]');
    }
    return buffer.toString();
  }

  @override
  String toString() => 'MediaMatch($tmdbId, ${kind.name}, $title, $year, $imdbId)';
}

/// Longueur retenue pour le seul titre : la plupart des systemes de fichiers
/// plafonnent un composant de chemin a 255 octets, et le suffixe annee plus
/// identifiant IMDb doit encore tenir.
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

/// Extrait un identifiant IMDb d'une URL complete, d'un identifiant nu, ou de
/// tout texte en contenant un.
String? extractImdbId(String raw) => RegExp(r'tt\d{7,8}').firstMatch(raw)?.group(0);
