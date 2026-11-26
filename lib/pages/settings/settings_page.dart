import 'package:flutter/material.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/settings_category.dart';
import 'package:i_zerak_app/pages/settings/sections/commute_section.dart';
import 'package:i_zerak_app/pages/settings/sections/display_section.dart';
import 'package:i_zerak_app/pages/settings/sections/free_time_section.dart';
import 'package:i_zerak_app/pages/settings/sections/games_section.dart';
import 'package:i_zerak_app/pages/settings/sections/notifications_section.dart';
import 'package:i_zerak_app/pages/settings/sections/server_section.dart';
import 'package:i_zerak_app/pages/settings/sections/sync_section.dart';
import 'package:i_zerak_app/pages/settings/widgets/settings_ui.dart';
import 'package:i_zerak_app/services/commute_price_service.dart';
import 'package:i_zerak_app/services/gaming/gaming_service.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_app_preferences.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_commute.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_server_config.dart';
import 'package:i_zerak_app/services/screen_time/screen_time_service.dart';
import 'package:i_zerak_app/services/service_locator.dart';
import 'package:i_zerak_app/services/sync/sync_service.dart';

/// Ouvre les reglages, deplies sur [open] s'il est donne.
///
/// C'est par ici que passent les raccourcis des onglets : un seul ecran par
/// reglage, ou qu'on le cherche.
Future<void> openSettings(BuildContext context, {SettingsCategory? open}) =>
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => SettingsPage(open: open)));

/// Les reglages de toute l'application, ranges par categorie.
///
/// Chaque categorie se replie, et l'ecran se souvient de celles qu'on laisse
/// ouvertes : la plupart des visites reviennent au meme endroit. Chacune
/// s'enregistre a sa facon — tout de suite pour un interrupteur, par un
/// bouton pour un formulaire qu'on valide — et ne depend pas des autres.
class SettingsPage extends StatefulWidget {
  SettingsPage({
    super.key,
    this.open,
    IAppPreferences? preferences,
    Map<SettingsCategory, WidgetBuilder>? sections,
  })  : preferences = preferences ?? getIt<IAppPreferences>(),
        sections = sections ?? defaultSettingsSections(preferences ?? getIt<IAppPreferences>());

  /// La categorie a deplier et a amener a l'ecran en arrivant.
  final SettingsCategory? open;

  final IAppPreferences preferences;

  /// Le contenu de chaque categorie presente. Une categorie absente n'est
  /// pas affichee — son service n'existe pas sur cette plateforme.
  final Map<SettingsCategory, WidgetBuilder> sections;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

/// Les categories que les services enregistres permettent de regler.
Map<SettingsCategory, WidgetBuilder> defaultSettingsSections(IAppPreferences preferences) => {
      if (getIt.isRegistered<ICommute>() && getIt.isRegistered<CommutePriceService>())
        SettingsCategory.commute: (_) => CommuteSection(),
      if (getIt.isRegistered<ScreenTimeService>())
        SettingsCategory.freeTime: (_) => FreeTimeSection(),
      if (getIt.isRegistered<GamingService>()) SettingsCategory.games: (_) => GamesSection(),
      SettingsCategory.notifications: (_) => NotificationsSection(),
      if (getIt.isRegistered<IServerConfig>())
        SettingsCategory.server: (_) => const ServerSection(),
      if (getIt.isRegistered<SyncService>()) SettingsCategory.sync: (_) => SyncSection(),
      SettingsCategory.display: (_) => DisplaySection(preferences: preferences),
    };

class _SettingsPageState extends State<SettingsPage> {
  Set<SettingsCategory>? _expanded;
  final Map<SettingsCategory, GlobalKey> _keys = {
    for (final category in SettingsCategory.values) category: GlobalKey(),
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final expanded = await widget.preferences.readExpandedSettings();
    if (!mounted) {
      return;
    }
    final open = widget.open;
    // Un raccourci deplie sa categorie sans la retenir : seul un geste sur
    // l'en-tete change ce que l'ecran memorise.
    setState(() => _expanded = {...expanded, if (open != null) open});
    if (open != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = _keys[open]?.currentContext;
        if (target != null && target.mounted) {
          Scrollable.ensureVisible(target, duration: const Duration(milliseconds: 250));
        }
      });
    }
  }

  Future<void> _toggle(SettingsCategory category) async {
    final expanded = {..._expanded!};
    expanded.contains(category) ? expanded.remove(category) : expanded.add(category);
    setState(() => _expanded = expanded);
    // Une categorie depliee par un raccourci est retenue a ce moment-la avec
    // les autres : elle est a l'ecran, c'est ce qu'on voit.
    await widget.preferences.saveExpandedSettings(expanded);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final expanded = _expanded;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings_title)),
      body: expanded == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                for (final category in SettingsCategory.values)
                  if (widget.sections[category] case final WidgetBuilder builder) ...[
                    SettingsCategoryCard(
                      key: _keys[category],
                      icon: categoryIcon(category),
                      title: categoryTitle(l10n, category),
                      hint: categoryHint(l10n, category),
                      expanded: expanded.contains(category),
                      onToggle: () => _toggle(category),
                      builder: builder,
                    ),
                    const SizedBox(height: 12),
                  ],
              ],
            ),
    );
  }
}

IconData categoryIcon(SettingsCategory category) => switch (category) {
      SettingsCategory.commute => Icons.pedal_bike,
      SettingsCategory.freeTime => Icons.hourglass_bottom,
      SettingsCategory.games => Icons.sports_esports,
      SettingsCategory.notifications => Icons.notifications_active_outlined,
      SettingsCategory.server => Icons.developer_board,
      SettingsCategory.sync => Icons.sync,
      SettingsCategory.display => Icons.view_quilt_outlined,
    };

String categoryTitle(AppLocalizations l10n, SettingsCategory category) => switch (category) {
      SettingsCategory.commute => l10n.settings_commute,
      SettingsCategory.freeTime => l10n.settings_free_time,
      SettingsCategory.games => l10n.settings_games,
      SettingsCategory.notifications => l10n.settings_notifications,
      SettingsCategory.server => l10n.settings_server,
      SettingsCategory.sync => l10n.sync_section,
      SettingsCategory.display => l10n.settings_display,
    };

String categoryHint(AppLocalizations l10n, SettingsCategory category) => switch (category) {
      SettingsCategory.commute => l10n.settings_commute_hint,
      SettingsCategory.freeTime => l10n.settings_free_time_hint,
      SettingsCategory.games => l10n.settings_games_hint,
      SettingsCategory.notifications => l10n.settings_notifications_hint,
      SettingsCategory.server => l10n.settings_server_hint,
      SettingsCategory.sync => l10n.settings_sync_hint,
      SettingsCategory.display => l10n.settings_display_hint,
    };
