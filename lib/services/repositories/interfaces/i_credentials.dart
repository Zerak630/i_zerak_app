/// Les secrets manipules par l'application. Un enum plutot qu'une methode par
/// secret : ajouter un service ne change plus l'interface.
enum SecretKey {
  qbPassword('qb_password'),
  agentToken('agent_token'),
  tmdbToken('tmdb_token');

  const SecretKey(this.storageKey);

  final String storageKey;
}

abstract class ICredentials {
  /// Nul si le secret n'a jamais ete enregistre, ou s'il est devenu illisible
  /// (cle du trousseau invalidee), auquel cas l'implementation purge le stock.
  Future<String?> read(SecretKey key);

  Future<void> write(SecretKey key, String value);

  Future<void> delete(SecretKey key);
}
