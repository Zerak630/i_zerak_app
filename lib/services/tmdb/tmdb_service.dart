import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:i_zerak_app/models/media_match_dao.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_credentials.dart';

/// Erreurs de la recherche de metadonnees. Volontairement distinctes de celles
/// de qBittorrent : une panne TMDB ne doit jamais empecher l'ajout d'un
/// telechargement, elle degrade seulement le nommage.
sealed class TmdbException implements Exception {
  const TmdbException(this.message);
  final String message;
  @override
  String toString() => '$runtimeType: $message';
}

class TmdbNotConfiguredException extends TmdbException {
  const TmdbNotConfiguredException([super.message = 'Jeton TMDB absent']);
}

class TmdbAuthException extends TmdbException {
  const TmdbAuthException([super.message = 'Jeton TMDB refuse']);
}

class TmdbNetworkException extends TmdbException {
  const TmdbNetworkException([super.message = 'TMDB injoignable']);
}

/// Recherche de titres sur TMDB.
///
/// TMDB plutot que l'API IMDb : cette derniere n'a pas d'acces public, elle
/// n'est distribuee qu'aux entreprises via AWS Data Exchange. TMDB fournit une
/// cle gratuite pour un usage personnel et expose l'identifiant IMDb via
/// `/external_ids`, ce qui suffit a nommer les dossiers pour Emby.
///
/// La licence impose d'afficher une attribution TMDB dans l'application.
class TmdbService {
  TmdbService({
    required ICredentials credentials,
    http.Client? client,
    this.timeout = const Duration(seconds: 8),
    this.language = 'fr-FR',
  })  : _credentials = credentials,
        _client = client ?? http.Client();

  static const String _host = 'api.themoviedb.org';
  static const String imageBaseUrl = 'https://image.tmdb.org/t/p/w92';

  final ICredentials _credentials;
  final http.Client _client;
  final Duration timeout;
  final String language;

  Future<String> _token() async {
    final token = await _credentials.read(SecretKey.tmdbToken);
    if (token == null || token.trim().isEmpty) {
      throw const TmdbNotConfiguredException();
    }
    return token.trim();
  }

  Future<Map<String, dynamic>> _get(String path, Map<String, String> query) async {
    final token = await _token();
    final uri = Uri.https(_host, path, query);

    final http.Response response;
    try {
      response = await _client.get(uri, headers: {
        // TMDB accepte le jeton v4 en Bearer ; c'est la forme recommandee.
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      }).timeout(timeout);
    } on TimeoutException {
      throw const TmdbNetworkException('Delai depasse');
    } on SocketException catch (error) {
      throw TmdbNetworkException(error.message);
    } on http.ClientException catch (error) {
      throw TmdbNetworkException(error.message);
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const TmdbAuthException();
    }
    if (response.statusCode != 200) {
      throw TmdbNetworkException('Reponse ${response.statusCode}');
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }

  /// Films et series correspondant a la recherche. Les personnes renvoyees par
  /// `/search/multi` sont ecartees.
  Future<List<MediaMatch>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return const [];
    }

    final body = await _get('/3/search/multi', {
      'query': trimmed,
      'language': language,
      'include_adult': 'false',
    });

    final results = body['results'];
    if (results is! List) {
      return const [];
    }
    return results
        .whereType<Map<String, dynamic>>()
        .map(MediaMatch.fromSearchJson)
        .whereType<MediaMatch>()
        .toList(growable: false);
  }

  /// Complete la correspondance avec son identifiant IMDb.
  Future<MediaMatch> withImdbId(MediaMatch match) async {
    final body = await _get('/3/${match.kind.apiPath}/${match.tmdbId}/external_ids', const {});
    final imdbId = body['imdb_id'] as String?;
    if (imdbId == null || imdbId.isEmpty) {
      return match;
    }
    return match.copyWith(imdbId: imdbId);
  }
}
