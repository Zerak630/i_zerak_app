import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// L'acces a tous les fichiers, que reclame Android pour lire le dossier
/// Syncthing.
///
/// Depuis Android 11, une application ne lit pas les fichiers qu'une autre a
/// deposes dans le stockage partage sans la permission « Acces a tous les
/// fichiers » (MANAGE_EXTERNAL_STORAGE) — celle-la meme qu'Obsidian demande
/// pour son coffre. Ailleurs, rien a demander.
///
/// Canal `izerak/storage`, methodes `isGranted` (-> bool) et `request`
/// (ouvre la page systeme de l'application), servies par `MainActivity.kt`.
///
/// La plateforme se lit par `defaultTargetPlatform`, jamais par `dart:io` :
/// `Platform` leve une exception sur le web, ou la synchro n'existe pas mais
/// ou les reglages s'affichent quand meme.
class StorageAccess {
  const StorageAccess({MethodChannel channel = const MethodChannel('izerak/storage')})
      : _channel = channel;

  final MethodChannel _channel;

  /// Vrai seulement sur Android : c'est la seule plateforme ou il faut agir.
  bool get isRequired => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Vrai si la permission est accordee, ou si elle n'est pas requise.
  ///
  /// Un canal muet compte pour un refus : mieux vaut proposer d'accorder
  /// l'acces une fois de trop que d'annoncer une synchro qui ne lira rien.
  Future<bool> isGranted() async {
    if (!isRequired) {
      return true;
    }
    try {
      return await _channel.invokeMethod<bool>('isGranted') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Ouvre la page systeme ou l'utilisateur accorde l'acces.
  ///
  /// Revient aussitot : la reponse arrive quand l'utilisateur revient dans
  /// l'application, et se relit alors par [isGranted].
  Future<void> request() async {
    if (!isRequired) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('request');
    } on PlatformException {
      // Rien a faire de plus : [isGranted] continuera de repondre non.
    } on MissingPluginException {
      // Idem.
    }
  }
}
