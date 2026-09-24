import 'package:flutter/material.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/app_tab.dart';
import 'package:i_zerak_app/pages/app_tab_ui.dart';

/// Le menu « Plus » : les onglets absents de la barre, et le choix de ceux
/// qui y restent.
///
/// Une seule liste plutot que deux : chaque ligne mene a son onglet, et son
/// epingle decide de sa presence en bas. Les repeter dans deux sections aurait
/// fait lire six noms pour six onglets.
///
/// Renvoie l'onglet choisi, ou `null` si la feuille est refermee sans choix.
/// Les changements d'epingle, eux, sont annonces au fil de l'eau : ils valent
/// meme quand on ne change pas d'onglet.
Future<AppTab?> showMoreSheet(
  BuildContext context, {
  required TabLayout layout,
  required AppTab current,
  required ValueChanged<TabLayout> onLayoutChanged,
}) =>
    showModalBottomSheet<AppTab>(
      context: context,
      showDragHandle: true,
      builder: (_) => _MoreSheet(
        layout: layout,
        current: current,
        onLayoutChanged: onLayoutChanged,
      ),
    );

class _MoreSheet extends StatefulWidget {
  const _MoreSheet({
    required this.layout,
    required this.current,
    required this.onLayoutChanged,
  });

  final TabLayout layout;
  final AppTab current;
  final ValueChanged<TabLayout> onLayoutChanged;

  @override
  State<_MoreSheet> createState() => _MoreSheetState();
}

class _MoreSheetState extends State<_MoreSheet> {
  late TabLayout _layout = widget.layout;

  void _toggle(AppTab tab) {
    final changed = _layout.isPinned(tab) ? _layout.unpin(tab) : _layout.pin(tab);
    // `pin` et `unpin` renvoient l'instance courante quand ils ne peuvent
    // rien faire : rien a enregistrer dans ce cas.
    if (identical(changed, _layout)) {
      return;
    }
    setState(() => _layout = changed);
    widget.onLayoutChanged(changed);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SafeArea(
      // Defilante : six lignes plus l'en-tete depassent la hauteur qu'une
      // feuille du bas s'accorde par defaut, et davantage encore en paysage.
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l10n.bb_more, style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                l10n.more_hint,
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ]),
          ),
          for (final tab in AppTab.values)
            ListTile(
              selected: tab == widget.current,
              leading: Icon(tabIcon(tab)),
              title: Text(tabLabel(l10n, tab)),
              onTap: () => Navigator.pop(context, tab),
              trailing: IconButton(
                // Grise quand la barre est pleine : mieux vaut le dire que de
                // chasser un onglet deja epingle sans prevenir.
                onPressed: !_layout.isPinned(tab) && !_layout.canPinMore
                    ? null
                    : () => _toggle(tab),
                icon: Icon(
                  _layout.isPinned(tab) ? Icons.push_pin : Icons.push_pin_outlined,
                  color: _layout.isPinned(tab) ? scheme.primary : null,
                ),
                tooltip: _layout.isPinned(tab) ? l10n.more_unpin : l10n.more_pin,
              ),
            ),
          if (!_layout.canPinMore)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
              child: Text(
                l10n.more_full,
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
              ),
            ),
        ]),
      ),
    );
  }
}
