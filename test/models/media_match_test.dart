import 'package:i_zerak_app/models/media_match_dao.dart';
import 'package:test/test.dart';

MediaMatch match({String title = 'Un film', int? year = 2024, String? imdbId}) => MediaMatch(
      tmdbId: 1,
      kind: MediaKind.movie,
      title: title,
      year: year,
      imdbId: imdbId,
    );

void main() {
  group('embyFolderName', () {
    test('forme reconnue par Emby', () {
      expect(match(imdbId: 'tt1234567').embyFolderName(), 'Un film (2024) [imdbid-tt1234567]');
    });

    test('sans identifiant IMDb, le titre et l annee suffisent', () {
      expect(match().embyFolderName(), 'Un film (2024)');
    });

    test('sans annee non plus', () {
      expect(match(year: null).embyFolderName(), 'Un film');
    });

    test('le deux-points devient un tiret', () {
      // Sans cela, torrents/add echoue cote serveur avec un message opaque.
      expect(match(title: 'Alien : le huitieme passager').embyFolderName(),
          'Alien - le huitieme passager (2024)');
    });

    test('les caracteres interdits par les systemes de fichiers disparaissent', () {
      final name = match(title: r'A/B\C*D?E"F<G>H|I').embyFolderName();
      for (final forbidden in [r'/', r'\', '*', '?', '"', '<', '>', '|']) {
        expect(name.contains(forbidden), isFalse, reason: 'contient $forbidden');
      }
    });

    test('les accents et les emoji sont conserves', () {
      expect(match(title: 'Amélie 🎬').embyFolderName(), 'Amélie 🎬 (2024)');
    });

    test('un titre tres long est tronque', () {
      final name = match(title: 'x' * 400, imdbId: 'tt1234567').embyFolderName();
      // Le titre est plafonne pour laisser tenir l'annee et l'identifiant dans
      // la limite d'un composant de chemin.
      expect(name.length, lessThan(200));
      expect(name.endsWith('[imdbid-tt1234567]'), isTrue);
    });

    test('un titre vide reste un nom de dossier valide', () {
      expect(match(title: '   ', year: null).embyFolderName(), 'Sans titre');
    });

    test('pas de point ni d espace final, refuses par Windows et Samba', () {
      expect(sanitizeForFileSystem('Un film.'), 'Un film');
      expect(sanitizeForFileSystem('Un film  '), 'Un film');
    });
  });

  group('extractImdbId', () {
    test('depuis une URL complete', () {
      expect(extractImdbId('https://www.imdb.com/title/tt0111161/'), 'tt0111161');
    });

    test('depuis un identifiant nu', () {
      expect(extractImdbId('tt12345678'), 'tt12345678');
    });

    test('depuis un texte quelconque', () {
      expect(extractImdbId('voir tt0111161 pour le detail'), 'tt0111161');
    });

    test('renvoie null quand il n y en a pas', () {
      expect(extractImdbId('rien ici'), isNull);
      expect(extractImdbId(''), isNull);
    });
  });

  group('fromSearchJson', () {
    test('un film', () {
      final result = MediaMatch.fromSearchJson(const {
        'media_type': 'movie',
        'id': 42,
        'title': 'Un film',
        'release_date': '2024-05-01',
        'poster_path': '/abc.jpg',
      });
      expect(result, isNotNull);
      expect(result!.year, 2024);
      expect(result.kind, MediaKind.movie);
    });

    test('une serie utilise name et first_air_date', () {
      final result = MediaMatch.fromSearchJson(const {
        'media_type': 'tv',
        'id': 7,
        'name': 'Une serie',
        'first_air_date': '2019-01-01',
      });
      expect(result!.title, 'Une serie');
      expect(result.year, 2019);
    });

    test('les personnes renvoyees par search/multi sont ecartees', () {
      expect(
        MediaMatch.fromSearchJson(const {'media_type': 'person', 'id': 3, 'name': 'Quelqu un'}),
        isNull,
      );
    });

    test('une entree sans titre est ecartee', () {
      expect(MediaMatch.fromSearchJson(const {'media_type': 'movie', 'id': 3}), isNull);
    });

    test('une date absente ou tronquee ne leve pas', () {
      final result = MediaMatch.fromSearchJson(
          const {'media_type': 'movie', 'id': 3, 'title': 'X', 'release_date': ''});
      expect(result!.year, isNull);
    });
  });
}
