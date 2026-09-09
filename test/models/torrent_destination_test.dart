import 'package:i_zerak_app/models/media_match_dao.dart';
import 'package:i_zerak_app/models/torrent_destination.dart';
import 'package:test/test.dart';

void main() {
  group('fromKind', () {
    test('un film va dans Films, une serie dans Series', () {
      expect(TorrentDestination.fromKind(MediaKind.movie), TorrentDestination.films);
      expect(TorrentDestination.fromKind(MediaKind.tv), TorrentDestination.series);
    });

    test('sans resultat TMDB, la destination est Autres', () {
      // C'est le cas qui justifie ce type : MediaKind ne connait que deux
      // valeurs, il ne peut pas exprimer « ni film ni serie ».
      expect(TorrentDestination.fromKind(null), TorrentDestination.autres);
    });
  });

  group('folder et category', () {
    test('les deux sont identiques', () {
      for (final d in TorrentDestination.values) {
        expect(d.category, d.folder);
      }
    });

    test('toujours en ASCII, jamais accentue', () {
      // qBittorrent cree a la volee, sans erreur, toute categorie inconnue,
      // avec un chemin vide : une categorie « Series » accentuee cote serveur
      // enverrait les fichiers ailleurs, en silence.
      for (final d in TorrentDestination.values) {
        expect(RegExp(r'^[A-Za-z]+$').hasMatch(d.folder), isTrue, reason: d.folder);
      }
    });
  });

  group('destinationPath', () {
    test('ajoute le segment de la destination a la racine', () {
      expect(
        destinationPath(libraryRoot: '/srv/nas1/Emby', destination: TorrentDestination.films),
        '/srv/nas1/Emby/Films',
      );
    });

    test('une barre oblique finale ne produit pas de double barre', () {
      expect(
        destinationPath(libraryRoot: '/srv/nas1/Emby///', destination: TorrentDestination.series),
        '/srv/nas1/Emby/Series',
      );
    });

    test('racine nulle ou blanche : pas de chemin', () {
      // Les reglages enregistrent une chaine vide, pas null, quand le champ est
      // laisse en blanc : tester `!= null` ne suffirait pas.
      expect(destinationPath(libraryRoot: null, destination: TorrentDestination.films), isNull);
      expect(destinationPath(libraryRoot: '   ', destination: TorrentDestination.films), isNull);
    });
  });

  group('resolveAddOptions', () {
    test('avec une racine, l application impose le chemin et coupe la gestion auto', () {
      // Sans autoTMM=false, un serveur en gestion automatique ignore savepath
      // en silence et le dossier Emby est perdu.
      final options = resolveAddOptions(
        destination: TorrentDestination.films,
        basePath: '/srv/nas1/Emby/Films',
        folderName: 'Un film (2024) [tmdbid=42]',
      );
      expect(options.savePath, '/srv/nas1/Emby/Films/Un film (2024) [tmdbid=42]');
      expect(options.category, 'Films');
      expect(options.autoTmm, isFalse);
      expect(options.createSubfolder, isFalse);
    });

    test('sans nom de dossier, on depose a la racine de la destination', () {
      final options = resolveAddOptions(
        destination: TorrentDestination.autres,
        basePath: '/srv/nas1/Emby/Autres/',
        folderName: '   ',
      );
      expect(options.savePath, '/srv/nas1/Emby/Autres');
    });

    test('sans racine, on rend la main au serveur plutot que de casser', () {
      // Envoyer autoTMM=false avec un chemin nul serait le pire des deux
      // mondes : ni chemin impose, ni routage par categorie.
      final options = resolveAddOptions(
        destination: TorrentDestination.series,
        basePath: null,
        folderName: 'Une serie (2020) [tmdbid=7]',
      );
      expect(options.savePath, isNull);
      expect(options.category, 'Series');
      expect(options.autoTmm, isTrue);
      expect(options.createSubfolder, isNull);
    });

    test('une racine blanche est traitee comme absente', () {
      final options = resolveAddOptions(
        destination: TorrentDestination.films,
        basePath: '  ',
        folderName: 'X',
      );
      expect(options.savePath, isNull);
      expect(options.autoTmm, isTrue);
    });
  });
}
