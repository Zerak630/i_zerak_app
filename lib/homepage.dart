import 'package:flutter/material.dart';
import 'package:google_nav_bar/google_nav_bar.dart';
import 'package:i_zerak_app/pages/commute/commute_page.dart';
import 'package:i_zerak_app/pages/dashboard/dashboard_page.dart';
import 'package:i_zerak_app/pages/gas_stations/gas_station_page.dart';
import 'package:i_zerak_app/pages/settings/settings_page.dart';
import 'package:i_zerak_app/pages/torrents/torrents_page.dart';
import 'package:i_zerak_app/pages/subscriptions/subscriptions.dart';
import 'package:i_zerak_app/pages/system/system_page.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
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
                Expanded(flex: 1, child: _getActivePage(_selectedIndex)),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: Container(
        color: Theme.of(context).colorScheme.scrim,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: GNav(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              gap: 4,
              // Serre depuis le sixieme onglet : `GNav` ne nomme que l'onglet
              // actif, mais six icones aux marges d'origine debordaient des
              // que « Abonnements » etait selectionne.
              padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 14.0),
              onTabChange: (index) => setState(() => _selectedIndex = index),
              selectedIndex: _selectedIndex,
              tabs: [
                GButton(
                  icon: Icons.home_outlined,
                  text: AppLocalizations.of(context)!.bb_home,
                  iconActiveColor: Theme.of(context).colorScheme.primary,
                ),
                GButton(
                  icon: Icons.euro,
                  text: AppLocalizations.of(context)!.bb_subscriptions,
                  iconActiveColor: Theme.of(context).colorScheme.primary,
                ),
                GButton(
                  icon: Icons.download,
                  text: AppLocalizations.of(context)!.bb_torrents,
                  iconActiveColor: Theme.of(context).colorScheme.primary,
                ),
                GButton(
                  icon: Icons.developer_board,
                  text: AppLocalizations.of(context)!.bb_system,
                  iconActiveColor: Theme.of(context).colorScheme.primary,
                ),
                GButton(
                  icon: Icons.local_gas_station,
                  text: AppLocalizations.of(context)!.bb_gas_stations,
                  iconActiveColor: Theme.of(context).colorScheme.primary,
                ),
                GButton(
                  icon: Icons.pedal_bike,
                  text: AppLocalizations.of(context)!.bb_commute,
                  iconActiveColor: Theme.of(context).colorScheme.primary,
                ),
              ]),
        ),
      ),
    );
  }
}

Widget _getActivePage(int index) {
  switch (index) {
    case 0:
      return DashboardPage();
    case 1:
      return SubscriptionsPage();
    case 2:
      return const TorrentsPage();
    case 3:
      return const SystemPage();
    case 4:
      return GasStationPage();
    case 5:
      return CommutePage();
    default:
      throw Exception('Invalid index');
  }
}
