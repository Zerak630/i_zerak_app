import 'package:flutter/material.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/app_tab.dart';
import 'package:i_zerak_app/pages/app_tab_ui.dart';
import 'package:i_zerak_app/pages/settings/widgets/settings_ui.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_app_preferences.dart';

/// La categorie « Affichage » : les onglets epingles a la barre du bas.
///
/// Le menu « Plus » garde ses epingles, a portee de pouce : les deux ecrivent
/// la meme `TabLayout`, et l'accueil la relit au retour des reglages.
class DisplaySection extends StatefulWidget {
  const DisplaySection({super.key, required this.preferences});

  final IAppPreferences preferences;

  @override
  State<DisplaySection> createState() => _DisplaySectionState();
}

class _DisplaySectionState extends State<DisplaySection> {
  TabLayout? _layout;

  @override
  void initState() {
    super.initState();
    widget.preferences.readTabs().then((layout) {
      if (mounted) {
        setState(() => _layout = layout);
      }
    });
  }

  Future<void> _toggle(TabLayout layout, AppTab tab) async {
    final changed = layout.isPinned(tab) ? layout.unpin(tab) : layout.pin(tab);
    // Meme regle que le menu « Plus » : une barre pleine ou reduite a un seul
    // onglet renvoie la meme instance, et il n'y a rien a enregistrer.
    if (identical(changed, layout)) {
      return;
    }
    setState(() => _layout = changed);
    await widget.preferences.saveTabs(changed);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final layout = _layout;
    if (layout == null) {
      return const SettingsLoading();
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SettingsSubtitle(l10n.settings_display_tabs, first: true),
      Text(
        l10n.settings_display_tabs_hint(TabLayout.maxPinned),
        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      ),
      const SizedBox(height: 4),
      for (final tab in AppTab.values)
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          secondary: Icon(tabIcon(tab)),
          title: Text(tabLabel(l10n, tab)),
          value: layout.isPinned(tab),
          // Grise quand la barre est pleine, ou pour le dernier epingle.
          onChanged: (layout.isPinned(tab) && layout.pinned.length <= 1) ||
                  (!layout.isPinned(tab) && !layout.canPinMore)
              ? null
              : (_) => _toggle(layout, tab),
        ),
    ]);
  }
}
