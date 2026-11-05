import 'package:flutter/material.dart';
import 'package:google_nav_bar/google_nav_bar.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/app_tab.dart';
import 'package:i_zerak_app/pages/app_tab_ui.dart';
import 'package:i_zerak_app/pages/commute/commute_page.dart';
import 'package:i_zerak_app/pages/dashboard/dashboard_page.dart';
import 'package:i_zerak_app/pages/free_time/free_time_page.dart';
import 'package:i_zerak_app/pages/gas_stations/gas_station_page.dart';
import 'package:i_zerak_app/pages/goals/goals_page.dart';
import 'package:i_zerak_app/pages/more_sheet.dart';
import 'package:i_zerak_app/pages/settings/settings_page.dart';
import 'package:i_zerak_app/pages/settings/sync_section.dart' show syncAgo;
import 'package:i_zerak_app/pages/subscriptions/subscriptions.dart';
import 'package:i_zerak_app/pages/system/system_page.dart';
import 'package:i_zerak_app/pages/torrents/torrents_page.dart';
import 'package:i_zerak_app/services/home_widgets/home_widgets_service.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_app_preferences.dart';
import 'package:i_zerak_app/services/service_locator.dart';
import 'package:i_zerak_app/services/sync/sync_service.dart';
import 'package:i_zerak_app/utils/wide_layout.dart';

class HomePage extends StatefulWidget {
  HomePage(
      {super.key, IAppPreferences? preferences, SyncService? sync, HomeWidgetsService? widgets})
      : preferences = preferences ?? getIt<IAppPreferences>(),
        sync = sync ?? (getIt.isRegistered<SyncService>() ? getIt<SyncService>() : null),
        widgets = widgets ??
            (getIt.isRegistered<HomeWidgetsService>() ? getIt<HomeWidgetsService>() : null);

  final IAppPreferences preferences;

  /// Absent dans les tests qui ne l'enregistrent pas : la page s'en passe.
  final SyncService? sync;

  /// Les widgets de l'ecran d'accueil. Nul dans les tests qui n'en ont pas
  /// besoin.
  final HomeWidgetsService? widgets;

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  TabLayout _layout = TabLayout.initial;
  AppTab _current = TabLayout.initial.pinned.first;

  late final AppLifecycleListener _lifecycle;

  /// Change quand un widget a modifie les donnees : l'onglet affiche est
  /// alors reconstruit, et relit ce qui a ete enregistre sans lui.
  int _generation = 0;

  /// Le bouton « Voiture » d'un widget a ouvert l'application : l'onglet Velo
  /// demande la raison des son ouverture.
  bool _askCar = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () {
        // De retour au premier plan, l'autre appareil a pu ecrire entre-temps.
        widget.sync?.syncNow();
        _syncWidgets();
      },
      // Les widgets ne se voient que l'application quittee : c'est le moment
      // de leur transmettre ce qui a change.
      onHide: () => widget.widgets?.refresh(),
    );
    _loadTabs().then((_) => _syncWidgets());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  /// Rapatrie ce qui a ete fait depuis les widgets.
  Future<void> _syncWidgets() async {
    final widgets = widget.widgets;
    if (widgets == null) {
      return;
    }
    final imported = await widgets.importPendingBikeDays();
    final action = await widgets.takeLaunchAction();
    if (!mounted) {
      return;
    }
    if (imported > 0 || action == 'car') {
      setState(() {
        _generation++;
        if (action == 'car') {
          _current = AppTab.commute;
          _askCar = true;
        }
      });
    }
    await widgets.refresh();
  }

  /// La page ouverte, reconstruite de zero quand une importation ou un widget a
  /// change les donnees : chaque page lit son depot a l'ouverture, et n'aurait
  /// sinon aucune raison de le relire.
  Widget _currentPage() {
    final sync = widget.sync;
    if (sync == null) {
      return KeyedSubtree(key: ValueKey(_generation), child: _pageFor(_current));
    }
    return ValueListenableBuilder<SyncStatus>(
      valueListenable: sync.status,
      builder: (context, status, _) => KeyedSubtree(
        key: ValueKey((status.generation, _generation)),
        child: _pageFor(_current),
      ),
    );
  }

  /// L'etat de la synchro au pied du rail, comme le bloc « Synchronise » de la
  /// maquette : il dit de quand datent les chiffres affiches.
  Widget _syncIndicator(BuildContext context, {required bool extended}) {
    final sync = widget.sync;
    if (sync == null) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return ValueListenableBuilder<SyncStatus>(
      valueListenable: sync.status,
      builder: (context, status, _) {
        if (status.phase == SyncPhase.disabled) {
          return const SizedBox.shrink();
        }
        final (icon, color, label) = switch (status.phase) {
          SyncPhase.error => (Icons.sync_problem, theme.colorScheme.error, l10n.sync_rail_error),
          SyncPhase.syncing => (
              Icons.sync,
              theme.colorScheme.onSurfaceVariant,
              l10n.sync_rail_syncing
            ),
          _ => (Icons.cloud_done_outlined, theme.colorScheme.primary, l10n.sync_rail_ok),
        };
        final when =
            status.lastSync == null ? null : syncAgo(l10n, status.lastSync!, DateTime.now());
        final tooltip = when == null ? label : '$label · $when';
        if (!extended) {
          return Tooltip(message: tooltip, child: Icon(icon, size: 20, color: color));
        }
        return SizedBox(
          width: 190,
          child: Row(children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: theme.textTheme.labelLarge),
                if (when != null)
                  Text(when,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ]),
            ),
          ]),
        );
      },
    );
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

  /// Seul l'onglet actif est construit : voir le commentaire du `build`.
  ///
  /// Une page qui mene a une autre recoit de quoi changer d'onglet, et non de
  /// quoi pousser cette autre page : elle serait sinon joignable a deux
  /// endroits, avec deux etats.
  Widget _pageFor(AppTab tab) {
    // Consommee une seule fois : revenir plus tard sur l'onglet ne doit pas
    // reposer la question.
    final askCar = _askCar && tab == AppTab.commute;
    _askCar = false;
    return switch (tab) {
      AppTab.home => DashboardPage(),
      AppTab.subscriptions => SubscriptionsPage(),
      AppTab.commute =>
        CommutePage(onOpenGoals: () => _open(AppTab.goals), askCarOnOpen: askCar),
      AppTab.goals => GoalsPage(),
      AppTab.freeTime => FreeTimePage(),
      AppTab.torrents => const TorrentsPage(),
      AppTab.system => const SystemPage(),
      AppTab.gas => GasStationPage(),
    };
  }

  void _open(AppTab tab) => setState(() => _current = tab);

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

  void _openSettings() => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SettingsPage()),
      );

  @override
  Widget build(BuildContext context) {
    if (WideLayout.hasRail(context)) {
      return _wide(context);
    }

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
                              onPressed: _openSettings,
                            ),
                          ])),
                ),
                // Seul l'onglet actif est construit. C'est deliberé : les pages
                // Torrents et Systeme interrogent le serveur auto-heberge, et
                // un onglet quitte doit cesser de le faire. Le remplacer un
                // jour par un IndexedStack les garderait toutes vivantes — et
                // toutes bavardes — derriere celle qu'on regarde.
                Expanded(flex: 1, child: _currentPage()),
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

  /// Sur grand ecran : un rail a gauche qui montre tous les onglets.
  ///
  /// Le choix des epingles n'a plus cours ici — il repondait au manque de
  /// place de la barre du bas — mais il est conserve tel quel pour le jour ou
  /// la fenetre redevient etroite.
  Widget _wide(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final extended = MediaQuery.sizeOf(context).width >= WideLayout.extendedRail;

    final rail = NavigationRail(
      // Un ton au-dessus du fond, et non le noir de la barre du bas : sur un
      // grand ecran, une bande noire pleine hauteur ecrase la page.
      backgroundColor: scheme.surfaceContainerLow,
      extended: extended,
      minExtendedWidth: 220,
      selectedIndex: AppTab.values.indexOf(_current),
      onDestinationSelected: (index) => _open(AppTab.values[index]),
      labelType: extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
      leading: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 16),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Image(image: AssetImage('assets/images/iZerak_logo.png'), width: 44, height: 44),
          if (extended) ...[
            const SizedBox(width: 12),
            const Text('iZerak', style: TextStyle(fontSize: 20)),
          ],
        ]),
      ),
      trailing: Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _syncIndicator(context, extended: extended),
          const SizedBox(height: 8),
          if (extended)
            // Aligne sur les libelles du rail, plutot qu'une roue seule au
            // milieu de la colonne.
            SizedBox(
              width: 190,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  foregroundColor: scheme.onSurfaceVariant,
                ),
                icon: const Icon(Icons.settings),
                label: Text(l10n.settings_title),
                onPressed: _openSettings,
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: l10n.settings_title,
              onPressed: _openSettings,
            ),
        ]),
      ),
      destinations: [
        for (final tab in AppTab.values)
          NavigationRailDestination(
            icon: Icon(tabIcon(tab)),
            label: Text(tabLabel(l10n, tab)),
          ),
      ],
    );

    return Scaffold(
      body: SafeArea(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Huit onglets ne tiennent pas dans une fenetre basse : le rail
          // defile plutot que de deborder.
          LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(child: rail),
              ),
            ),
          ),
          Expanded(child: _widePage(context)),
        ]),
      ),
    );
  }

  /// La page ouverte, sous son titre, et bornee en largeur : sur un ecran de
  /// bureau, une ligne qui court sur toute la fenetre eloigne trop le montant
  /// de son libelle.
  Widget _widePage(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: WideLayout.maxContentWidth),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            // La barre du haut du telephone n'a pas d'equivalent ici : le
            // titre la remplace, et ecarte la premiere carte du bord.
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text(tabLabel(l10n, _current),
                style: Theme.of(context).textTheme.headlineSmall),
          ),
          Expanded(child: _currentPage()),
        ]),
      ),
    );
  }
}
