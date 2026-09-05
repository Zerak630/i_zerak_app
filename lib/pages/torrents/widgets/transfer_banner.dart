import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:i_zerak_app/models/transfer_info_dao.dart';
import 'package:i_zerak_app/utils/formatters.dart';

/// Bandeau de vitesses globales et d'etat de connexion.
class TransferBanner extends StatelessWidget {
  const TransferBanner({super.key, required this.transfer});

  final TransferInfoDao transfer;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _speed(context, Icons.south, formatSpeed(transfer.dlInfoSpeed),
                l10n.download_speed),
            _speed(context, Icons.north, formatSpeed(transfer.upInfoSpeed), l10n.upload_speed),
            _status(context, l10n),
          ],
        ),
      ),
    );
  }

  Widget _speed(BuildContext context, IconData icon, String value, String semantics) => Semantics(
        label: semantics,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 4),
            Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      );

  Widget _status(BuildContext context, AppLocalizations l10n) {
    // Un serveur derriere un pare-feu se connecte, mais ne recoit aucune
    // connexion entrante : les vitesses s'en trouvent fortement degradees, ce
    // qui merite d'etre visible.
    final (Color color, String label) = switch (transfer.connectionStatus) {
      ConnectionStatus.connected => (Colors.green, l10n.status_connected),
      ConnectionStatus.firewalled => (Colors.orange, l10n.status_firewalled),
      ConnectionStatus.disconnected => (
          Theme.of(context).colorScheme.error,
          l10n.status_disconnected
        ),
      ConnectionStatus.unknown => (
          Theme.of(context).colorScheme.onSurfaceVariant,
          l10n.state_unknown
        ),
    };

    return Tooltip(
      message: label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 10, color: color),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
