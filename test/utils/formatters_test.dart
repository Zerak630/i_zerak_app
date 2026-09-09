import 'package:i_zerak_app/utils/formatters.dart';
import 'package:test/test.dart';

void main() {
  group('formatBytes', () {
    test('les octets bruts s affichent sans decimale', () {
      expect(formatBytes(0), '0 o');
      expect(formatBytes(512), '512 o');
      expect(formatBytes(1023), '1023 o');
    });

    test('bascule en base 1024', () {
      expect(formatBytes(1024), '1.0 Ko');
      expect(formatBytes(1536), '1.5 Ko');
      expect(formatBytes(1024 * 1024), '1.0 Mo');
      expect(formatBytes(1024 * 1024 * 1024), '1.0 Go');
    });

    test('supporte les tailles au-dela de 2^32', () {
      // 4 To : un disque externe depasse couramment cette borne.
      expect(formatBytes(4 * 1024 * 1024 * 1024 * 1024), '4.0 To');
    });

    test('une taille negative est inconnue, pas nulle', () {
      expect(formatBytes(-1), '—');
    });
  });

  group('formatSpeed', () {
    test('une vitesse nulle reste lisible', () {
      expect(formatSpeed(0), '0 o/s');
      expect(formatSpeed(-5), '0 o/s');
    });

    test('reprend le formatage des octets', () {
      expect(formatSpeed(2048), '2.0 Ko/s');
    });
  });

  group('formatEta', () {
    test('la sentinelle de qBittorrent vaut l infini', () {
      // 8640000 secondes, soit cent jours : c'est la valeur que le serveur
      // renvoie pour un temps restant indetermine, pas une vraie duree.
      expect(formatEta(kInfiniteEta), '∞');
      expect(formatEta(kInfiniteEta + 1), '∞');
      expect(formatEta(-1), '∞');
    });

    test('durees courtes', () {
      expect(formatEta(0), '0s');
      expect(formatEta(45), '45s');
      expect(formatEta(60), '1min');
      expect(formatEta(750), '12min 30s');
    });

    test('durees longues', () {
      expect(formatEta(3600), '1h');
      expect(formatEta(8000), '2h 13min');
      expect(formatEta(90000), '1j 1h');
      expect(formatEta(172800), '2j');
    });
  });

  group('formatUptime', () {
    test('ne subit pas la sentinelle de l eta', () {
      // Un Raspberry Pi peut tourner plus de cent jours : cette duree doit
      // rester lisible et non basculer en infini.
      expect(formatUptime(kInfiniteEta), '100j');
      expect(formatUptime(kInfiniteEta * 2), '200j');
    });

    test('une valeur negative est inconnue', () {
      expect(formatUptime(-1), '—');
    });
  });

  group('formatProgress', () {
    test('borne et arrondit', () {
      expect(formatProgress(0), '0.0 %');
      expect(formatProgress(0.5), '50.0 %');
      expect(formatProgress(0.12345), '12.3 %');
      // 0.5555 n'est pas representable exactement : le double vaut un peu
      // moins que 55,55, l'arrondi descend donc a 55,5. Comportement correct,
      // fige ici pour eviter qu'on le prenne un jour pour une regression.
      expect(formatProgress(0.5555), '55.5 %');
      expect(formatProgress(1), '100 %');
      expect(formatProgress(1.4), '100 %');
      expect(formatProgress(-0.2), '0.0 %');
    });
  });

  group('formatRatio', () {
    test('un ratio indefini vaut l infini', () {
      // qBittorrent renvoie -1 tant qu'aucun partage n'a eu lieu.
      expect(formatRatio(-1), '∞');
    });

    test('deux decimales', () {
      expect(formatRatio(0), '0.00');
      expect(formatRatio(1.2345), '1.23');
    });
  });

  group('formatUptimeSince', () {
    final fetchedAt = DateTime(2026, 9, 9, 10, 0, 0);

    test('la duree avance avec l horloge, sans nouvel appel', () {
      // La page Systeme ne se rafraichit qu'a la demande : entre deux releves,
      // c'est ce calcul seul qui fait vivre la duree de fonctionnement.
      expect(formatUptimeSince(30, fetchedAt, fetchedAt), '30s');
      expect(formatUptimeSince(30, fetchedAt, fetchedAt.add(const Duration(seconds: 45))),
          '1min 15s');
      expect(formatUptimeSince(3600, fetchedAt, fetchedAt.add(const Duration(minutes: 30))),
          '1h 30min');
    });

    test('une longue absence est rattrapee d un coup', () {
      // Le point du calcul a l'horloge murale : un compteur incremente par
      // minuteur aurait pris tout ce retard pendant que l'application dormait.
      expect(
        formatUptimeSince(86400, fetchedAt, fetchedAt.add(const Duration(hours: 5))),
        '1j 5h',
      );
    });

    test('une horloge qui recule ne fait pas reculer la duree', () {
      expect(
        formatUptimeSince(120, fetchedAt, fetchedAt.subtract(const Duration(hours: 1))),
        '2min',
      );
    });

    test('une duree inconnue le reste', () {
      expect(formatUptimeSince(-1, fetchedAt, fetchedAt.add(const Duration(hours: 3))), '—');
    });
  });
}
