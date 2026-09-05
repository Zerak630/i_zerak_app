import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

/// Confirmation de suppression.
///
/// Renvoie `null` si l'utilisateur annule, sinon le booleen indiquant s'il faut
/// aussi effacer les fichiers deja telecharges.
Future<bool?> showDeleteTorrentDialog(BuildContext context, String torrentName) =>
    showDialog<bool>(context: context, builder: (context) => _DeleteTorrentDialog(torrentName));

class _DeleteTorrentDialog extends StatefulWidget {
  const _DeleteTorrentDialog(this.torrentName);

  final String torrentName;

  @override
  State<_DeleteTorrentDialog> createState() => _DeleteTorrentDialogState();
}

class _DeleteTorrentDialogState extends State<_DeleteTorrentDialog> {
  /// Decoche par defaut : la case detruit des donnees, elle ne doit jamais etre
  /// activee par inadvertance.
  bool _deleteFiles = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(l10n.delete_torrent),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.torrentName, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 12),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _deleteFiles,
            onChanged: (value) => setState(() => _deleteFiles = value ?? false),
            title: Text(l10n.delete_files_too),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        TextButton(
          onPressed: () => Navigator.pop(context, _deleteFiles),
          style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
          child: Text(l10n.delete),
        ),
      ],
    );
  }
}
