import 'package:i_zerak_app/models/torrent_dao.dart';
import 'package:i_zerak_app/models/torrent_state.dart';
import 'package:i_zerak_app/models/transfer_info_dao.dart';
import 'package:i_zerak_app/utils/formatters.dart';
import 'package:test/test.dart';

void main() {
  group('TorrentState.fromApi', () {
    test('reconnait les etats classiques', () {
      expect(TorrentState.fromApi('downloading'), TorrentState.downloading);
      expect(TorrentState.fromApi('stalledUP'), TorrentState.stalledUp);
      expect(TorrentState.fromApi('checkingResumeData'), TorrentState.checkingResumeData);
    });

    test('accepte les graphies de qBittorrent 5', () {
      // La version 5 a renomme les etats en pause : les deux graphies doivent
      // aboutir au meme etat tant que la version du serveur n'est pas garantie.
      expect(TorrentState.fromApi('stoppedDL'), TorrentState.fromApi('pausedDL'));
      expect(TorrentState.fromApi('stoppedUP'), TorrentState.fromApi('pausedUP'));
      expect(TorrentState.fromApi('stoppedDL'), TorrentState.pausedDl);
    });

    test('un etat inconnu ne fait pas echouer le parsing', () {
      // Une version future peut introduire de nouveaux etats : la liste
      // entiere ne doit pas tomber pour autant.
      expect(TorrentState.fromApi('etatInedit'), TorrentState.unknown);
      expect(TorrentState.fromApi(''), TorrentState.unknown);
      expect(TorrentState.fromApi(null), TorrentState.unknown);
    });

    test('predicats', () {
      expect(TorrentState.pausedDl.isPaused, isTrue);
      expect(TorrentState.stalledUp.isCompleted, isTrue);
      expect(TorrentState.downloading.isCompleted, isFalse);
      expect(TorrentState.missingFiles.isError, isTrue);
      expect(TorrentState.moving.isChecking, isTrue);
      expect(TorrentState.unknown.isActive, isFalse);
    });
  });

  group('TorrentDao.fromJson', () {
    test('parse un enregistrement complet', () {
      final torrent = TorrentDao.fromJson(const {
        'hash': 'abc123',
        'name': 'Un film',
        'progress': 0.42,
        'dlspeed': 1024,
        'upspeed': 0,
        'size': 1073741824,
        'eta': 3600,
        'ratio': 1.5,
        'state': 'downloading',
        'category': 'movies',
        'save_path': '/mnt/media/films',
        'tags': 'vo,hd',
        'added_on': 1700000000,
      });

      expect(torrent.hash, 'abc123');
      expect(torrent.progress, 0.42);
      expect(torrent.state, TorrentState.downloading);
      expect(torrent.tags, ['vo', 'hd']);
      expect(torrent.savePath, '/mnt/media/films');
    });

    test('progress et ratio peuvent arriver en entier', () {
      // Regression classique : un cast direct en double leverait ici.
      final torrent = TorrentDao.fromJson(const {'progress': 1, 'ratio': 0});
      expect(torrent.progress, 1.0);
      expect(torrent.ratio, 0.0);
    });

    test('eta sentinelle', () {
      final torrent = TorrentDao.fromJson(const {'eta': kInfiniteEta});
      expect(formatEta(torrent.eta), '∞');
    });

    test('tags est une chaine, pas un tableau', () {
      expect(TorrentDao.fromJson(const {'tags': ''}).tags, isEmpty);
      expect(TorrentDao.fromJson(const {'tags': 'un, deux ,trois'}).tags,
          ['un', 'deux', 'trois']);
      expect(TorrentDao.fromJson(const {}).tags, isEmpty);
    });

    test('les champs absents prennent une valeur de repli', () {
      final torrent = TorrentDao.fromJson(const {});
      expect(torrent.hash, '');
      expect(torrent.name, '');
      expect(torrent.progress, 0.0);
      expect(torrent.state, TorrentState.unknown);
      expect(torrent.eta, -1);
    });

    test('supporte une taille au-dela de 2^31', () {
      final torrent = TorrentDao.fromJson(const {'size': 5000000000});
      expect(torrent.size, 5000000000);
    });

    test('listFromBody tolere un corps inattendu', () {
      expect(TorrentDao.listFromBody('[]'), isEmpty);
      expect(TorrentDao.listFromBody('{"erreur":"x"}'), isEmpty);
      expect(TorrentDao.listFromBody('[{"hash":"a"},{"hash":"b"}]').length, 2);
    });
  });

  group('TransferInfoDao', () {
    test('parse un corps nominal', () {
      final info = TransferInfoDao.fromBody(
          '{"dl_info_speed":1000,"up_info_speed":50,"connection_status":"firewalled"}');
      expect(info.dlInfoSpeed, 1000);
      expect(info.upInfoSpeed, 50);
      expect(info.connectionStatus, ConnectionStatus.firewalled);
    });

    test('un statut inconnu ne leve pas', () {
      expect(TransferInfoDao.fromBody('{"connection_status":"???"}').connectionStatus,
          ConnectionStatus.unknown);
      expect(TransferInfoDao.fromBody('[]').connectionStatus, ConnectionStatus.unknown);
    });
  });
}
