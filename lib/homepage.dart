import 'package:flutter/material.dart';
import 'package:google_nav_bar/google_nav_bar.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/app_tab.dart';
import 'package:i_zerak_app/pages/app_tab_ui.dart';
import 'package:i_zerak_app/pages/commute/commute_page.dart';
import 'package:i_zerak_app/pages/dashboard/dashboard_page.dart';
import 'package:i_zerak_app/pages/gas_stations/gas_station_page.dart';
import 'package:i_zerak_app/pages/more_sheet.dart';
import 'package:i_zerak_app/pages/settings/settings_page.dart';
import 'package:i_zerak_app/pages/subscriptions/subscriptions.dart';
import 'package:i_zerak_app/pages/system/system_page.dart';
import 'package:i_zerak_app/pages/torrents/torrents_page.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_app_preferences.dart';
import 'package:i_zerak_app/services/service_locator.dart';

class HomePage extends StatefulWidget {
  HomePage({super.key, IAppPreferences? preferences})
      : preferences = preferences ?? getIt<IAppPreferences>();

  final IAppPreferences preferences;

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  TabLayout _layout = TabLayout.initial;
  AppTab _current = TabLayout.initial.pinned.first;

  @override
  void initState() {
    super.initState();
    _loadTabs();
  }

  Future<void> _loadTabs() async {
    final layout = await widget.preferences.readTabs();
    if (mounted) {
      setState(() {
        _layout = layout;
        _current = layout.pinned.first;
      });
    }
  }

  /// L'onglet actif dans la barre, ou le bouton « Plus » quand il n'y figure
  /// pas : sans cela, aucun bouton ne serait allume.
  int get _selectedIndex {
    final index = _layout.pinned.indexOf(_current);
    return index < 0 ? _layout.pinned.length : index;
  }

  Future<void> _onTabChange(int index) async {
    if (index < _layout.pinned.length) {
      setState(() => _current = _layout.pinned[index]);
      return;
    }
    final chosen = await showMoreSheet(
      context,
      layout: _layout,
      current: _current,
      onLayoutChanged: (layout) {
        setState(() => _layout = layout);
        widget.preferences.saveTabs(layout);
      },
    );
    if (chosen != null && mounted) {
      setState(() => _current = chosen);
    } else {
      // Refermee sans choix : le bouton « Plus » ne doit pas rester allume si
      // l'onglet courant est, lui, epingle.
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final pinnedCurrent = _layout.isPinned(_current);

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Column(
              children: [
                SizedBox(
                  height: constraints.maxHeight * 0.1,
                  child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Image(
                                    image: AssetImage('assets/images/iZerak_logo.png'),
                                    width: 50,
                                    height: 50),
                                SizedBox(width: 12.0),
                                Text(
                                  'iZerak',
                                  style: TextStyle(fontSize: 24),
                                ),
                              ],
                            ),
                            // Les reglages sont pousses sur la pile plutot que
                            // d'occuper un onglet : la barre du bas se serre
                            // deja, et cet ecran est consulte rarement.
                            IconButton(
                              icon: const Icon(Icons.settings),
                              tooltip: AppLocalizations.of(context)!.settings_title,
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const SettingsPage()),
                              ),
                            ),
                          ])),
                ),
                // Seul l'onglet actif est construit. C'est deliberé : les pages
                // Torrents et Systeme interrogent le serveur auto-heberge, et
                // un onglet quitte doit cesser de le faire. Le remplacer un
                // jour par un IndexedStack les garderait toutes vivantes — et
                // toutes bavardes — derriere celle qu'on regarde.
                Expanded(flex: 1, child: _pageFor(_current)),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: Container(
        color: Theme.of(context).colorScheme.scrim,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
          child: GNav(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              gap: 8,
              iconSize: 26,
              // Quatre boutons au plus : les marges peuvent rester larges, et
              // la barre redevient facile a viser du pouce.
              padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 16.0),
              onTabChange: _onTabChange,
              selectedIndex: _selectedIndex,
              tabs: [
                for (final tab in _layout.pinned)
                  GButton(
                    icon: tabIcon(tab),
                    text: tabLabel(l10n, tab),
                    iconActiveColor: scheme.primary,
                  ),
                GButton(
                  icon: Icons.more_horiz,
                  // Quand l'onglet courant n'est pas epingle, c'est ce bouton
                  // qui est allume : il porte alors le nom de la page ouverte,
                  // plutot qu'un « Plus » qui ne dirait pas ou l'on est.
                  text: pinnedCurrent ? l10n.bb_more : tabLabel(l10n, _current),
                  iconActiveColor: scheme.primary,
                ),
              ]),
        ),
      ),
    );
  }
}

Widget _pageFor(AppTab tab) => switch (tab) {
      AppTab.home => DashboardPage(),
      AppTab.subscriptions => SubscriptionsPage(),
      AppTab.torrents => const TorrentsPage(),
      AppTab.system => const SystemPage(),
      AppTab.gas => GasStationPage(),
      AppTab.commute => CommutePage(),
    };
