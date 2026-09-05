import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Appele lorsqu'un certificat inconnu est presente, pour que l'interface
/// puisse proposer son adoption. Recoit l'empreinte normalisee.
typedef CertificateInspector = void Function(String sha256Fingerprint);

/// Empreinte SHA-256 de la forme DER du certificat, en hexadecimal minuscule.
/// Correspond a la sortie de `openssl x509 -noout -fingerprint -sha256`, une
/// fois les deux-points retires et la casse abaissee.
String certificateFingerprint(X509Certificate certificate) =>
    sha256.convert(certificate.der).toString();

/// Accepte indifferemment `AB:CD:...`, `abcd...` et le prefixe
/// `SHA256 Fingerprint=` que colle `openssl`.
String normalizeFingerprint(String raw) =>
    raw.replaceAll(RegExp(r'[^0-9a-fA-F]'), '').toLowerCase();

/// Comparaison a duree constante : une comparaison naive divulgue, par son
/// temps d'execution, le nombre d'octets corrects en tete.
bool fingerprintsMatch(String a, String b) {
  final left = normalizeFingerprint(a);
  final right = normalizeFingerprint(b);
  if (left.length != right.length || left.isEmpty) {
    return false;
  }
  var diff = 0;
  for (var i = 0; i < left.length; i++) {
    diff |= left.codeUnitAt(i) ^ right.codeUnitAt(i);
  }
  return diff == 0;
}

/// Construit un client HTTP qui n'accepte qu'un certificat precis.
///
/// Le contexte est cree sans racines de confiance : toute chaine echoue donc a
/// la validation par defaut et `badCertificateCallback` est systematiquement
/// consulte. C'est ce qui garantit que l'epinglage s'applique reellement, y
/// compris si le serveur presentait un jour un certificat signe par une
/// autorite reconnue.
///
/// Ne jamais remplacer le corps du rappel par `return true` : cela reviendrait
/// a accepter n'importe quel certificat, donc n'importe quelle interception sur
/// le reseau local, et annulerait tout le benefice du HTTPS.
http.Client buildPinnedClient({
  String? pinnedSha256,
  CertificateInspector? onUntrustedCertificate,
  Duration connectionTimeout = const Duration(seconds: 8),
}) {
  final context = SecurityContext(withTrustedRoots: false);
  final ioClient = HttpClient(context: context)
    ..connectionTimeout = connectionTimeout
    ..badCertificateCallback = (X509Certificate certificate, String host, int port) {
      final actual = certificateFingerprint(certificate);
      if (pinnedSha256 == null || pinnedSha256.isEmpty) {
        // Premiere connexion : on refuse, mais on remonte l'empreinte pour que
        // l'utilisateur puisse la comparer a celle du serveur et l'adopter.
        onUntrustedCertificate?.call(actual);
        return false;
      }
      final trusted = fingerprintsMatch(actual, pinnedSha256);
      if (!trusted) {
        onUntrustedCertificate?.call(actual);
      }
      return trusted;
    };

  return IOClient(ioClient);
}

/// Client en clair, pour les rares cas ou l'utilisateur desactive HTTPS. Le
/// trafic n'est alors ni chiffre ni authentifie, et Android le bloquera en
/// dehors du profil de debogage.
http.Client buildPlainClient() => IOClient(HttpClient());
