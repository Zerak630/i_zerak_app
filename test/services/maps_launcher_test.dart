import 'package:i_zerak_app/services/maps_launcher.dart';
import 'package:test/test.dart';

void main() {
  group('navigationUris', () {
    test('la premiere cible demarre le guidage sans ecran d apercu', () {
      // google.navigation: lance directement le guidage vocal. L'URL
      // universelle, elle, s'arrete sur l'apercu d'itineraire : il resterait un
      // bouton a presser, ce qui n'est pas « commencer la navigation ».
      final first = navigationUris(latitude: 47.47738, longitude: -0.55225).first;
      expect(first.scheme, 'google.navigation');
      expect(first.toString(), 'google.navigation:q=47.477380,-0.552250&mode=d');
    });

    test('les trois cibles sont essayees, de la plus directe a la plus large', () {
      final uris = navigationUris(latitude: 47.0, longitude: -0.5);
      expect(uris.map((u) => u.scheme).toList(), ['google.navigation', 'geo', 'https']);
      expect(uris.last.host, 'www.google.com');
      expect(uris.last.queryParameters['destination'], '47.000000,-0.500000');
    });

    test('une longitude negative garde son signe', () {
      // La France metropolitaine est a l'ouest du meridien sur presque toute sa
      // largeur : un signe perdu deplace la station de plusieurs centaines de
      // kilometres, sans rien casser de visible.
      for (final uri in navigationUris(latitude: 47.47738, longitude: -0.55225)) {
        expect(uri.toString(), contains('-0.55225'));
      }
    });

    test('le separateur decimal est le point, jamais la virgule', () {
      // Sous une locale francaise, une virgule couperait la coordonnee en deux
      // parametres et Maps ouvrirait un itineraire vers nulle part.
      final uri = navigationUris(latitude: 47.5, longitude: 1.5).first;
      expect(uri.toString(), contains('47.500000,1.500000'));
      expect(uri.toString().split(',').length, 2);
    });

    test('l hemisphere sud et l est du meridien sont couverts', () {
      final uri = navigationUris(latitude: -33.8688, longitude: 151.2093).last;
      expect(uri.queryParameters['destination'], '-33.868800,151.209300');
    });
  });
}
