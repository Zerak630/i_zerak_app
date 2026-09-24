import 'package:flutter/material.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';

/// Duree d'affichage d'un accuse de reception.
///
/// Assez pour lire une ligne, assez court pour ne pas suivre l'utilisateur d'un
/// ecran a l'autre.
const Duration kConfirmationDuration = Duration(seconds: 3);

/// Accuse de reception bref, qui s'efface seul.
///
/// **`persist: false` n'est pas superflu.** Une `SnackBar` dotee d'une action
/// est persistante par defaut (`persist ??= action != null`) : sans lui, le
/// bandeau attend qu'on le touche. Son bouton dit « OK » pour la meme raison :
/// il ferme le bandeau, il n'annule rien — l'annulation, quand elle existe,
/// reste sur l'ecran d'ou vient le geste.
void showConfirmation(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      duration: kConfirmationDuration,
      persist: false,
      action: SnackBarAction(
        label: AppLocalizations.of(context)!.ok,
        onPressed: messenger.hideCurrentSnackBar,
      ),
    ));
}
