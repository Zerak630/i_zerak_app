import 'package:i_zerak_app/models/agent_dao.dart';
import 'package:test/test.dart';

void main() {
  group('StorageVolume', () {
    test('disque debranche : rien ne doit etre affiche comme disponible', () {
      // Le cas critique. Le point de montage subsiste sous la forme d'un
      // repertoire vide sur la carte SD, et laisser croire que le disque est
      // present ferait remplir la carte par les telechargements.
      final volumes = StorageVolume.listFromBody(
          '{"volumes":[{"path":"/mnt/media","label":"Disque Emby",'
          '"mounted":false,"reason":"not_mounted"}]}');

      expect(volumes.single.mounted, isFalse);
      expect(volumes.single.reason, 'not_mounted');
      expect(volumes.single.freeBytes, isNull);
      expect(volumes.single.blocksDownloads, isTrue);
    });

    test('disque en lecture seule : present mais inutilisable', () {
      final volumes = StorageVolume.listFromBody(
          '{"volumes":[{"path":"/mnt/media","mounted":true,"readonly":true,'
          '"total_bytes":100,"used_bytes":10,"free_bytes":90}]}');

      expect(volumes.single.mounted, isTrue);
      expect(volumes.single.readonly, isTrue);
      expect(volumes.single.blocksDownloads, isTrue);
    });

    test('disque sain sous le quota', () {
      final volumes = StorageVolume.listFromBody(
          '{"volumes":[{"path":"/mnt/media","mounted":true,"readonly":false,'
          '"total_bytes":2000,"used_bytes":750,"free_bytes":1250,'
          '"quota_bytes":1000,"quota_free_bytes":250,"quota_ratio":0.75}]}');

      final volume = volumes.single;
      expect(volume.blocksDownloads, isFalse);
      expect(volume.quotaRatio, 0.75);
      // Le quota est un plafond volontaire, distinct de la capacite reelle.
      expect(volume.quotaFreeBytes, 250);
      expect(volume.totalBytes, 2000);
    });

    test('quota atteint : l ajout doit etre bloque', () {
      final volumes = StorageVolume.listFromBody(
          '{"volumes":[{"path":"/mnt/media","mounted":true,"quota_ratio":1.0}]}');
      expect(volumes.single.blocksDownloads, isTrue);
    });

    test('un corps inattendu ne leve pas', () {
      expect(StorageVolume.listFromBody('{}'), isEmpty);
      expect(StorageVolume.listFromBody('[]'), isEmpty);
    });
  });

  group('SystemStats', () {
    test('parse un corps nominal', () {
      final stats = SystemStats.fromBody('{"hostname":"pi","model":"Raspberry Pi 4",'
          '"uptime_seconds":123456,"load_1":0.5,"load_5":0.4,"load_15":0.3,'
          '"cpu_temp_c":54.2,"mem_total_bytes":4000,"mem_available_bytes":1500,'
          '"throttled":{"available":true,"under_voltage_now":false,'
          '"under_voltage_occurred":true,"currently_throttled":false,'
          '"throttling_occurred":false}}');

      expect(stats.model, 'Raspberry Pi 4');
      expect(stats.cpuTempC, 54.2);
      expect(stats.memUsedBytes, 2500);
      expect(stats.throttled.underVoltageOccurred, isTrue);
      // Une sous-tension survenue merite un avertissement : elle explique
      // souvent des pannes deja constatees.
      expect(stats.throttled.hasWarning, isTrue);
    });

    test('hors Raspberry Pi, les drapeaux sont indisponibles et silencieux', () {
      final stats = SystemStats.fromBody('{"throttled":{"available":false}}');
      expect(stats.throttled.available, isFalse);
      expect(stats.throttled.hasWarning, isFalse);
    });

    test('memUsedBytes reste nul si une des deux valeurs manque', () {
      expect(SystemStats.fromBody('{"mem_total_bytes":100}').memUsedBytes, isNull);
    });

    test('un corps vide ne leve pas', () {
      expect(SystemStats.fromBody('{}').uptimeSeconds, 0);
      expect(SystemStats.fromBody('[]').hostname, '');
    });
  });

  group('ServiceStatus', () {
    test('parse la liste des services', () {
      final services = ServiceStatus.listFromBody(
          '{"services":[{"name":"emby","unit":"emby-server.service",'
          '"active_state":"active","sub_state":"running","enabled":true,'
          '"memory_bytes":123456}]}');

      expect(services.single.state, ServiceState.active);
      expect(services.single.state.isRunning, isTrue);
      expect(services.single.memoryBytes, 123456);
    });

    test("l'interface web se forme avec l'hote des reglages", () {
      final services = ServiceStatus.listFromBody(
          '{"services":[{"name":"cora","active_state":"active",'
          '"web":{"scheme":"http","port":5000,"path":"/"}},'
          '{"name":"emby","active_state":"active","web":null}]}');

      expect(services.first.web?.uriFor('192.168.1.110').toString(), 'http://192.168.1.110:5000/');
      expect(services.first.web?.uriFor('fd7a::1').toString(), 'http://[fd7a::1]:5000/');
      expect(services.last.web, isNull);
    });

    test('une interface web mal formee est ignoree', () {
      expect(ServiceWeb.fromJson({'port': 0}), isNull);
      expect(ServiceWeb.fromJson({'port': '5000'}), isNull);
      expect(ServiceWeb.fromJson({'port': 5000, 'scheme': 'javascript', 'path': 'x'})?.uriFor('pi').toString(),
          'http://pi:5000/');
    });

    test('les actions permises viennent de l\'agent', () {
      final services = ServiceStatus.listFromBody(
          '{"services":[{"name":"wireguard","actions":["start","restart","reboot"]},'
          '{"name":"emby"}]}');

      expect(services.first.actions, {'start', 'restart'});
      // Un agent plus ancien n'envoie pas le champ : rien n'est retire.
      expect(services.last.actions, ServiceStatus.allActions);
    });

    test('un etat inconnu retombe sur une valeur neutre', () {
      final services = ServiceStatus.listFromBody(
          '{"services":[{"name":"x","active_state":"reloading"}]}');
      expect(services.single.state, ServiceState.unknown);
    });

    test('les etats transitoires sont identifies', () {
      expect(ServiceState.fromApi('activating').isTransitioning, isTrue);
      expect(ServiceState.fromApi('deactivating').isTransitioning, isTrue);
      expect(ServiceState.fromApi('active').isTransitioning, isFalse);
    });
  });
}
