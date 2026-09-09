import 'package:url_launcher/url_launcher.dart';

/// Ouvre une navigation vers un point.
///
/// Le calcul des URI est sorti dans `navigationUris`, Dart pur : c'est la
/// partie ou une erreur se paie — un signe inverse envoie a l'autre bout du
/// monde — et elle se teste sans plugin ni telephone.
class MapsLauncher {
  const MapsLauncher();

  /// Renvoie `false` si aucune application n'a accepte l'itineraire.
  Future<bool> navigateTo({required double latitude, required double longitude}) async {
    for (final uri in navigationUris(latitude: latitude, longitude: longitude)) {
      try {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          return true;
        }
      } on Exception {
        // Un schema qu'aucune application ne gere leve plutot que de renvoyer
        // false : on passe au suivant, l'echec ne vaut qu'apres la derniere.
        continue;
      }
    }
    return false;
  }
}

/// Les cibles a essayer dans l'ordre, de la plus directe a la plus universelle.
///
/// 1. `google.navigation:` demarre le guidage vocal immediatement, sans ecran
///    d'apercu — c'est ce que veut dire « commencer la navigation ».
/// 2. `geo:` laisse le systeme proposer les applications de cartographie
///    installees, Google Maps absent compris.
/// 3. L'URL universelle fonctionne partout, jusque dans un navigateur, mais
///    s'arrete sur l'apercu d'itineraire : il reste un bouton a presser.
///
/// Le point-virgule de `google.navigation:q=...` n'est pas une erreur de
/// frappe : ce schema attend ses parametres apres `:`, pas apres `://`, et
/// `Uri.parse` le traite donc comme un chemin opaque.
List<Uri> navigationUris({required double latitude, required double longitude}) {
  // Toujours le point decimal, jamais la virgule : une locale francaise
  // produirait « 47,277 » et couperait la coordonnee en deux parametres.
  final point = '${latitude.toStringAsFixed(6)},${longitude.toStringAsFixed(6)}';
  return [
    Uri.parse('google.navigation:q=$point&mode=d'),
    Uri.parse('geo:$point?q=$point'),
    Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': point,
      'travelmode': 'driving',
    }),
  ];
}
