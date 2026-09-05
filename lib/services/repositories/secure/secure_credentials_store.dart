import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_credentials.dart';

/// Stocke les secrets dans le Keystore Android / le Trousseau iOS.
///
/// Une boite Hive est un fichier en clair dans le bac a sable de
/// l'application : lisible sur un appareil deverrouille en root et extractible
/// par sauvegarde. Seul le magasin materiel de la plateforme convient ici.
class SecureCredentialsStore implements ICredentials {
  static const AndroidOptions _android = AndroidOptions(
    // Depuis la version 11 du paquet, le chiffrement adosse au Keystore est le
    // comportement par defaut : AES-GCM pour les donnees, cle enveloppee en
    // RSA-OAEP. L'ancien drapeau encryptedSharedPreferences n'existe plus.
    //
    // resetOnError purge le stock lorsque la cle du Keystore a ete invalidee,
    // ce qui arrive au changement de code de deverrouillage et apres
    // restauration sur un autre appareil. Sans cela le dechiffrement echouerait
    // definitivement. android:allowBackup="false" reste indispensable pour la
    // meme raison.
    resetOnError: true,
  );

  static const IOSOptions _ios = IOSOptions(
    // Lisible apres redemarrage sans deverrouillage prealable, ce qui reste
    // necessaire si un rafraichissement en arriere-plan est ajoute plus tard.
    accessibility: KeychainAccessibility.first_unlock,
  );

  final FlutterSecureStorage _storage;

  const SecureCredentialsStore({FlutterSecureStorage storage = const FlutterSecureStorage()})
      : _storage = storage;

  @override
  Future<String?> read(SecretKey key) async {
    try {
      return await _storage.read(key: key.storageKey, aOptions: _android, iOptions: _ios);
    } on PlatformException catch (_) {
      // La cle du Keystore est invalidee lorsque le code de deverrouillage ou
      // la biometrie changent, et apres restauration sur un autre appareil. Le
      // dechiffrement leve alors definitivement : on purge pour sortir de
      // l'impasse, l'application redemandera le secret.
      await _deleteQuietly(key);
      return null;
    }
  }

  @override
  Future<void> write(SecretKey key, String value) =>
      _storage.write(key: key.storageKey, value: value, aOptions: _android, iOptions: _ios);

  @override
  Future<void> delete(SecretKey key) =>
      _storage.delete(key: key.storageKey, aOptions: _android, iOptions: _ios);

  Future<void> _deleteQuietly(SecretKey key) async {
    try {
      await delete(key);
    } on PlatformException catch (_) {
      // Rien de plus a tenter : le secret restera illisible jusqu'a
      // reinstallation. Le corps est explicite pour satisfaire empty_catches.
    }
  }
}
