import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:i_zerak_app/models/gas_station_dao.dart';

/// Panne du cote de l'API des prix des carburants.
///
/// Nommee, plutot qu'un `Exception` generique, pour que la page puisse
/// distinguer un service indisponible d'une erreur de programmation.
class GasServiceException implements Exception {
  const GasServiceException(this.message);
  final String message;

  @override
  String toString() => 'GasServiceException: $message';
}

/// Acces en lecture au jeu de donnees public « prix des carburants en France ».
///
/// Ne connait pas les favoris : ceux-ci vivent dans `IGasStations`. Ce service
/// ne fait que traduire des identifiants et des recherches en requetes HTTP.
class GasService {
  GasService({http.Client? client}) : client = client ?? http.Client();

  final http.Client client;

  static const _host = 'data.economie.gouv.fr';
  static const _path =
      '/api/explore/v2.1/catalog/datasets/prix-des-carburants-en-france-flux-instantane-v2/records';

  /// Un enregistrement complet pese plusieurs kilo-octets — horaires et
  /// services y figurent en JSON echappe. Restreindre les colonnes divise la
  /// reponse par vingt, ce qui compte sur une liste de favoris.
  ///
  /// Les six carburants sont demandes ensemble, meme si un seul est affiche :
  /// ils arrivent dans la meme reponse, et changer de carburant ne declenche
  /// alors aucune requete.
  static final String _select =
      ['id', 'adresse', 'ville', 'cp', for (final fuel in FuelType.values) fuel.priceField]
          .join(',');

  /// Plafond impose par l'API sur une page de resultats.
  static const _pageSize = 100;

  /// Au-dela, la liste devient illisible et invite a preciser la recherche.
  static const searchLimit = 40;

  /// Recherche par nom de ville **ou** code postal, indifferemment.
  ///
  /// La requete part normalisee (cf. `normalizeSearchTerm`) : l'index de l'API
  /// est sans accents et sans traits d'union, et une recherche
  /// « Saint-Barthelemy » ecrite telle quelle ne renvoie rien du tout.
  ///
  /// `fuel` ne sert qu'au tri : les six prix sont ramenes dans tous les cas.
  Future<List<GasStationDao>> search(String query, {FuelType fuel = FuelType.gazole}) async {
    final term = normalizeSearchTerm(query);
    if (term.isEmpty) {
      return const [];
    }
    return _fetch({
      'where': 'ville like "$term" or cp like "$term"',
      'limit': '$searchLimit',
      'order_by': fuel.priceField,
    });
  }

  /// Recharge les prix des stations retenues, en une requete par centaine.
  ///
  /// Un appel par station — ce que faisait la page auparavant — ouvrait autant
  /// de connexions que de favoris et faisait apparaitre la liste par a-coups,
  /// dans l'ordre des reponses.
  Future<List<GasStationDao>> fetchByIds(List<int> ids) async {
    if (ids.isEmpty) {
      return const [];
    }
    final stations = <GasStationDao>[];
    for (var i = 0; i < ids.length; i += _pageSize) {
      final chunk = ids.sublist(i, min(i + _pageSize, ids.length));
      stations.addAll(await _fetch({
        'where': 'id in (${chunk.join(', ')})',
        'limit': '${chunk.length}',
      }));
    }
    return stations;
  }

  Future<List<GasStationDao>> _fetch(Map<String, String> params) async {
    final uri = Uri.https(_host, _path, {'select': _select, ...params});

    final http.Response response;
    try {
      response = await client.get(uri);
    } on Exception catch (error) {
      throw GasServiceException('$error');
    }

    if (response.statusCode != 200) {
      throw GasServiceException('HTTP ${response.statusCode}');
    }

    // Le corps est decode explicitement en UTF-8 : sans en-tete de charset,
    // `response.body` retombe sur du latin-1 et « Saint-Lambert-des-Levées »
    // arrive illisible.
    final data = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    return [
      for (final record in (data['results'] as List<dynamic>? ?? const []))
        GasStationDao.fromJson(record as Map<String, dynamic>),
    ];
  }
}

/// Rend une saisie libre comparable a l'index de l'API.
///
/// Trois roles en une seule passe :
///   - les accents sont deposes, `like` comparant a un index sans diacritiques ;
///   - traits d'union, apostrophes et ponctuation deviennent des espaces, que
///     `like` traite comme des separateurs de mots ;
///   - tout ce qui n'est ni lettre ni chiffre disparait, guillemets et
///     antislashs compris — ce qui rend au passage impossible toute injection
///     dans la clause `where`.
String normalizeSearchTerm(String raw) {
  final buffer = StringBuffer();
  for (final rune in raw.toLowerCase().runes) {
    buffer.write(_withoutDiacritic[String.fromCharCode(rune)] ?? String.fromCharCode(rune));
  }
  return buffer.toString().replaceAll(RegExp('[^a-z0-9]+'), ' ').trim();
}

const Map<String, String> _withoutDiacritic = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a', 'æ': 'ae',
  'ç': 'c',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
  'ñ': 'n',
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', 'œ': 'oe',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
  'ý': 'y', 'ÿ': 'y',
};
