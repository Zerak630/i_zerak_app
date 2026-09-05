/// Erreurs du dialogue avec le serveur auto-heberge.
///
/// `sealed` permet a l'interface d'exhausser les cas dans un `switch` et de
/// choisir un message traduit pour chacun : aucun `toString()` d'exception
/// technique ne doit atteindre l'utilisateur.
sealed class QbException implements Exception {
  const QbException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Aucune configuration serveur enregistree, ou incomplete.
class QbNotConfiguredException extends QbException {
  const QbNotConfiguredException([super.message = 'Serveur non configure']);
}

/// Identifiants refuses par le serveur.
class QbAuthException extends QbException {
  const QbAuthException([super.message = 'Identifiants invalides']);
}

/// qBittorrent bannit l'adresse apres plusieurs echecs d'authentification
/// consecutifs. Distinct de [QbAuthException] car la conduite a tenir differe :
/// il faut attendre, pas ressaisir le mot de passe.
class QbBannedException extends QbException {
  const QbBannedException([super.message = 'Adresse temporairement bannie par le serveur']);
}

/// Le certificat presente ne correspond pas a l'empreinte approuvee, ou aucune
/// empreinte n'a encore ete approuvee.
class QbCertificateException extends QbException {
  const QbCertificateException(super.message, {this.presentedFingerprint});

  /// Empreinte effectivement presentee, a soumettre a l'utilisateur.
  final String? presentedFingerprint;
}

/// Serveur injoignable : hote inconnu, port ferme, reseau absent.
class QbNetworkException extends QbException {
  const QbNetworkException([super.message = 'Serveur injoignable']);
}

class QbTimeoutException extends QbException {
  const QbTimeoutException([super.message = 'Delai depasse']);
}

/// Reponse HTTP inattendue.
class QbHttpException extends QbException {
  const QbHttpException(this.statusCode, [super.message = 'Reponse inattendue du serveur']);

  final int statusCode;

  // Volontairement sans le corps de la reponse : celui de /auth/login
  // contiendrait des elements sensibles, et ce toString finit dans les journaux.
  @override
  String toString() => 'QbHttpException($statusCode): $message';
}

/// Endpoint absent de cette version du serveur. Sert a basculer entre les noms
/// historiques et modernes (pause/stop, resume/start).
class QbUnsupportedEndpointException extends QbException {
  const QbUnsupportedEndpointException([super.message = 'Endpoint absent de cette version']);
}
