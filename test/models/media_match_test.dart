import 'package:i_zerak_app/models/media_match_dao.dart';
import 'package:test/test.dart';

MediaMatch match({String title = 'Un film', int? year = 2024, int tmdbId = 42}) => MediaMatch(
      tmdbId: tmdbId,
      kind: MediaKind.movie,
      title: title,
      year: year,
    );

void main() {
  group('embyFolderName', () {
    test('forme reconnue par Emby', () {
      expect(match().embyFolderName(), 'Un film (2024) [tmdbid=42]');
    });

    test('le tag utilise le signe egal, pas un tiret', () {
      // Emby documente `[tmdbid=36557]`. Jellyfin, lui, attend `[tmdbid-36557]`.
      // Un tiret ferait echouer l'identification par identifiant sous Emby, qui
      // retomberait silencieusement sur le titre et l'annee.
      final name = match().embyFolderName();
      expect(name.contains('[tmdbid=42]'), isTrue);
      expect(name.contains('[tmdbid-42]'), isFalse);
    });

    test('le tag est toujours present, l identifiant TMDB n etant jamais nul', () {
      // Contrairement a l'identifiant IMDb qu'il remplace, il vient du resultat
      // de recherche : il n'y a plus de cas « sans identifiant ».
      expect(match(tmdbId: 7).embyFolderName().endsWith('[tmdbid=7]'), isTrue);
    });

    test('sans annee, le tag suit directement le titre', () {
      expect(match(year: null).embyFolderName(), 'Un film [tmdbid=42]');
    });

    test('le deux-points devient un tiret', () {
      // Sans cela, torrents/add echoue cote serveur avec un message opaque.
      expect(match(title: 'Alien : le huitieme passager').embyFolderName(),
          'Alien - le huitieme passager (2024) [tmdbid=42]');
    });

    test('les caracteres interdits par les systemes de fichiers disparaissent', () {
      final name = match(title: r'A/B\C*D?E"F<G>H|I').embyFolderName();
      for (final forbidden in [r'/', r'\', '*', '?', '"', '<', '>', '|']) {
        expect(name.contains(forbidden), isFalse, reason: 'contient $forbidden');
      }
    });

    test('les accents et les emoji sont conserves', () {
      expect(match(title: 'Amélie 🎬').embyFolderName(), 'Amélie 🎬 (2024) [tmdbid=42]');
    });

    test('un titre tres long est tronque', () {
      final name = match(title: 'x' * 400).embyFolderName();
      // Le titre est plafonne pour laisser tenir l'annee et l'identifiant dans
      // la limite d'un composant de chemin.
      expect(name.length, lessThan(200));
      expect(name.endsWith('[tmdbid=42]'), isTrue);
    });

    test('un titre vide reste un nom de dossier valide', () {
      expect(match(title: '   ', year: null).embyFolderName(), 'Sans titre [tmdbid=42]');
    });

    test('pas de point ni d espace final, refuses par Windows et Samba', () {
      expect(sanitizeForFileSystem('Un film.'), 'Un film');
      expect(sanitizeForFileSystem('Un film  '), 'Un film');
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
