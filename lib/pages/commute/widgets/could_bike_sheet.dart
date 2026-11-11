import 'package:flutter/material.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/commute_dao.dart';
import 'package:i_zerak_app/pages/commute/widgets/commute_ui.dart';

/// Demande si le velo aurait pu remplacer la voiture, et renvoie la cagnotte
/// que le trajet alimente : oui, une economie loupee ; non, une depense
/// obligatoire.
///
/// Le detail de la raison n'apporte rien au bilan : seule compte la question
/// de savoir si l'argent pouvait etre economise.
Future<CarBucket?> showCouldBikeSheet(BuildContext context, {required String subtitle}) =>
    showModalBottomSheet<CarBucket>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _CouldBikeSheet(subtitle: subtitle),
    );

class _CouldBikeSheet extends StatelessWidget {
  const _CouldBikeSheet({required this.subtitle});

  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return CommuteSheet(children: [
      Text(l10n.commute_could_bike, style: theme.textTheme.titleLarge),
      const SizedBox(height: 4),
      Text(subtitle, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
      const SizedBox(height: 16),
      // Rien n'est preselectionne, et chaque reponse se donne d'un seul appui :
      // pas de bouton « Enregistrer » a valider par reflexe.
      _AnswerTile(
        answer: l10n.commute_could_bike_yes,
        bucket: CarBucket.missed,
        onTap: () => Navigator.pop(context, CarBucket.missed),
      ),
      const SizedBox(height: 8),
      _AnswerTile(
        answer: l10n.commute_could_bike_no,
        bucket: CarBucket.essential,
        onTap: () => Navigator.pop(context, CarBucket.essential),
      ),
      const SizedBox(height: 8),
      TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
    ]);
  }
}

class _AnswerTile extends StatelessWidget {
  const _AnswerTile({required this.answer, required this.bucket, required this.onTap});

  final String answer;
  final CarBucket bucket;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final missed = bucket == CarBucket.missed;

    return Material(
      color: scheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(answer, style: theme.textTheme.titleMedium),
                Text(
                  missed ? l10n.commute_bucket_missed_hint : l10n.commute_bucket_essential_hint,
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ]),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: missed ? scheme.tertiaryContainer : scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                bucketLabel(l10n, bucket),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: missed ? scheme.onTertiaryContainer : scheme.onSecondaryContainer,
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
