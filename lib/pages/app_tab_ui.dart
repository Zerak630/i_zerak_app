import 'package:flutter/material.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/app_tab.dart';

/// Le nom et l'icone d'un onglet, partages par la barre du bas et le menu.
String tabLabel(AppLocalizations l10n, AppTab tab) => switch (tab) {
      AppTab.home => l10n.bb_home,
      AppTab.subscriptions => l10n.bb_subscriptions,
      AppTab.commute => l10n.bb_commute,
      AppTab.goals => l10n.bb_goals,
      AppTab.torrents => l10n.bb_torrents,
      AppTab.system => l10n.bb_system,
      AppTab.gas => l10n.bb_gas_stations,
    };

IconData tabIcon(AppTab tab) => switch (tab) {
      AppTab.home => Icons.home_outlined,
      AppTab.subscriptions => Icons.euro,
      AppTab.commute => Icons.pedal_bike,
      AppTab.goals => Icons.flag_outlined,
      AppTab.torrents => Icons.download,
      AppTab.system => Icons.developer_board,
      AppTab.gas => Icons.local_gas_station,
    };
