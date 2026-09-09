import 'package:flutter/material.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';

/// Demande a l'utilisateur le nom qu'il veut donner a une station.
///
/// Renvoie la saisie, ou `null` si le dialogue a ete annule. Une chaine blanche
/// est une reponse valide : elle efface le nom et rend la station a son adresse.
Future<String?> showRenameStationDialog(
  BuildContext context, {
  required String currentName,
  required String? initialValue,
}) =>
    showDialog<String>(
      context: context,
      builder: (context) =>
          _RenameStationDialog(currentName: currentName, initialValue: initialValue),
    );

/// Widget a etat, et non un simple `AlertDialog` construit sur place : le
/// controleur doit vivre aussi longtemps que le champ. Libere juste apres le
/// retour de `showDialog`, il etait encore lu pendant l'animation de fermeture,
/// qui reconstruit le `TextField` une derniere fois — « A TextEditingController
/// was used after being disposed ».
class _RenameStationDialog extends StatefulWidget {
  const _RenameStationDialog({required this.currentName, required this.initialValue});

  final String currentName;
  final String? initialValue;

  @override
  State<_RenameStationDialog> createState() => _RenameStationDialogState();
}

class _RenameStationDialogState extends State<_RenameStationDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(l10n.gas_rename),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (value) => Navigator.pop(context, value),
        decoration: InputDecoration(
          labelText: l10n.gas_station_name,
          // L'adresse d'origine sert d'indication : c'est ce qui revient si le
          // champ est laisse vide.
          hintText: widget.currentName,
          helperText: l10n.gas_rename_hint,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        TextButton(
            onPressed: () => Navigator.pop(context, _controller.text),
            child: Text(l10n.save)),
      ],
    );
  }
}
