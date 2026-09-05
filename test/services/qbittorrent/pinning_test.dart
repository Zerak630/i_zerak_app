import 'package:i_zerak_app/services/qbittorrent/qb_http_client_factory.dart';
import 'package:test/test.dart';

void main() {
  const fingerprint = 'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';

  group('normalizeFingerprint', () {
    test('accepte la sortie brute de openssl', () {
      // openssl produit des paires majuscules separees par des deux-points,
      // precedees d'un libelle.
      const openssl =
          'SHA256 Fingerprint=A1:B2:C3:D4:E5:F6:07:18:29:3A:4B:5C:6D:7E:8F:90:'
          'A1:B2:C3:D4:E5:F6:07:18:29:3A:4B:5C:6D:7E:8F:90';
      expect(normalizeFingerprint(openssl), fingerprint);
    });

    test('laisse une empreinte deja normalisee inchangee', () {
      expect(normalizeFingerprint(fingerprint), fingerprint);
    });
  });

  group('fingerprintsMatch', () {
    test('deux empreintes identiques correspondent, quelle que soit la forme', () {
      expect(fingerprintsMatch(fingerprint, fingerprint.toUpperCase()), isTrue);
      expect(
        fingerprintsMatch(fingerprint, 'A1:B2:C3:D4:E5:F6:07:18:29:3A:4B:5C:6D:7E:8F:90:'
            'A1:B2:C3:D4:E5:F6:07:18:29:3A:4B:5C:6D:7E:8F:90'),
        isTrue,
      );
    });

    test('un seul caractere different suffit a refuser', () {
      final altered = 'b${fingerprint.substring(1)}';
      expect(fingerprintsMatch(fingerprint, altered), isFalse);
    });

    test('une empreinte vide ne correspond jamais', () {
      // Le cas dangereux : sans ce garde-fou, une empreinte absente pourrait
      // etre acceptee et l'epinglage deviendrait sans effet.
      expect(fingerprintsMatch('', ''), isFalse);
      expect(fingerprintsMatch(fingerprint, ''), isFalse);
      expect(fingerprintsMatch('', fingerprint), isFalse);
    });

    test('des longueurs differentes ne correspondent pas', () {
      expect(fingerprintsMatch(fingerprint, fingerprint.substring(0, 40)), isFalse);
    });

    test('un prefixe correct ne suffit pas', () {
      final prefix = '${fingerprint.substring(0, 60)}0000';
      expect(fingerprintsMatch(fingerprint, prefix), isFalse);
    });
  });
}
