import 'package:flutter/material.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/gas_station_dao.dart';
import 'package:i_zerak_app/pages/gas_stations/widgets/add_gas_station_sheet.dart';
import 'package:i_zerak_app/pages/gas_stations/widgets/fuel_label.dart';
import 'package:i_zerak_app/pages/gas_stations/widgets/rename_station_dialog.dart';
import 'package:i_zerak_app/services/gas_service.dart';
import 'package:i_zerak_app/services/maps_launcher.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_gas_stations.dart';
import 'package:i_zerak_app/services/service_locator.dart';

class GasStationPage extends StatefulWidget {
  GasStationPage({
    super.key,
    GasService? service,
    IGasStations? favorites,
    this.maps = const MapsLauncher(),
  })  : service = service ?? GasService(),
        favorites = favorites ?? getIt<IGasStations>();

  final GasService service;
  final IGasStations favorites;
  final MapsLauncher maps;

  @override
  State<GasStationPage> createState() => _GasStationPageState();
}

class _GasStationPageState extends State<GasStationPage> {
  /// Les favoris tels qu'ils sont enregistres : identifiant et libelle.
  List<SavedGasStation> _saved = const [];

  /// Les prix rapportes par l'API, indexes par identifiant. Une station absente
  /// de cette table n'a pas encore de prix connu ; une station presente avec un
  /// prix nul n'en vend pas.
  Map<int, GasStationDao> _live = const {};

  /// Carburant suivi. Relu du disque au demarrage, reecrit a chaque changement.
  /// Il ne declenche aucune requete : les six prix sont deja dans la reponse.
  FuelType _fuel = FuelType.gazole;

  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Les libelles enregistres s'affichent immediatement, les prix arrivent
  /// ensuite. La page n'est donc jamais vide en attendant le reseau, et elle
  /// reste lisible quand l'API est injoignable.
  Future<void> _load() async {
    final saved = await widget.favorites.getAll();
    final fuel = await widget.favorites.readFuel();
    if (!mounted) {
      return;
    }
    setState(() {
      _saved = saved;
      _fuel = fuel;
      _loading = false;
    });
    await _refresh();
  }

  /// Change le carburant affiche sans repasser par le reseau.
  Future<void> _selectFuel(FuelType fuel) async {
    setState(() => _fuel = fuel);
    await widget.favorites.saveFuel(fuel);
  }

  Future<void> _refresh() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _error = null;
    });

    try {
      final stations = await widget.service.fetchByIds([for (final s in _saved) s.id]);
      if (!mounted) {
        return;
      }
      setState(() {
        _live = {for (final station in stations) station.id: station};
      });
    } on GasServiceException {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = AppLocalizations.of(context)!.gas_unreachable;
      });
    }
  }

  Future<void> _add() async {
    final station = await showAddGasStationSheet(
      context,
      service: widget.service,
      fuel: _fuel,
      alreadySaved: {for (final s in _saved) s.id},
    );
    if (station == null) {
      return;
    }
    await widget.favorites.add((id: station.id, label: station.location, customName: null));
    if (!mounted) {
      return;
    }
    // Le prix vient d'etre lu par la recherche : l'inscrire evite un
    // aller-retour reseau pour une valeur qu'on tient deja.
    setState(() => _live = {..._live, station.id: station});
    await _load();
  }

  /// Lance le guidage vers la station.
  ///
  /// L'echec est signale, jamais silencieux : sur un telephone sans
  /// application de cartographie, un bouton qui ne fait rien passerait pour un
  /// defaut de l'application.
  Future<void> _navigateTo(GasStationDao station) async {
    final l10n = AppLocalizations.of(context)!;
    final launched = await widget.maps.navigateTo(
      latitude: station.latitude!,
      longitude: station.longitude!,
    );
    if (!mounted || launched) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l10n.gas_maps_unavailable)));
  }

  Future<void> _rename(SavedGasStation station, String currentName) async {
    final name = await showRenameStationDialog(
      context,
      currentName: currentName,
      initialValue: station.customName,
    );
    if (name == null) {
      return;
    }
    await widget.favorites.rename(station.id, name);
    if (!mounted) {
      return;
    }
    setState(() => _saved = [
          for (final s in _saved)
            if (s.id == station.id)
              (id: s.id, label: s.label, customName: name.trim().isEmpty ? null : name.trim())
            else
              s
        ]);
  }

  Future<void> _confirmDelete(SavedGasStation station, String name) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        // Le nom affiche, pas le libelle stocke : la confirmation doit nommer
        // ce que l'utilisateur voit dans la liste.
        content: Text(l10n.delete_confirm(name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.delete)),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await widget.favorites.delete(station.id);
    if (!mounted) {
      return;
    }
    setState(() => _saved = [for (final s in _saved) if (s.id != station.id) s]);
  }

  /// Les moins cheres en tete, pour le carburant choisi. Une station sans prix
  /// connu — carburant non vendu, rupture, ou reponse pas encore arrivee —
  /// passe en fin de liste plutot que d'etre classee a zero euro.
  List<SavedGasStation> get _sorted {
    final sorted = [..._saved];
    sorted.sort((a, b) {
      final priceA = _live[a.id]?.priceOf(_fuel);
      final priceB = _live[b.id]?.priceOf(_fuel);
      if (priceA == null && priceB == null) {
        return a.label.compareTo(b.label);
      }
      if (priceA == null) {
        return 1;
      }
      if (priceB == null) {
        return -1;
      }
      return priceA.compareTo(priceB);
    });
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: Column(
                children: [
                  _fuelPicker(context, l10n),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: Text(_error!,
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Theme.of(context).colorScheme.error)),
                    ),
                  Expanded(child: _list(context, l10n)),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _add,
        tooltip: l10n.gas_add_station,
        child: const Icon(Icons.add),
      ),
    );
  }

  /// Une liste deroulante, et non un bouton segmente : six carburants a la
  /// suite deborderaient largement sur un ecran de 320 dp.
  Widget _fuelPicker(BuildContext context, AppLocalizations l10n) => Padding(
        padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 0.0),
        child: Row(
          children: [
            Icon(Icons.local_gas_station,
                size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButton<FuelType>(
                value: _fuel,
                isExpanded: true,
                underline: const SizedBox.shrink(),
                items: [
                  for (final fuel in FuelType.values)
                    DropdownMenuItem(value: fuel, child: Text(fuelLabel(l10n, fuel))),
                ],
                onChanged: (fuel) {
                  if (fuel != null) {
                    _selectFuel(fuel);
                  }
                },
              ),
            ),
          ],
        ),
      );

  Widget _list(BuildContext context, AppLocalizations l10n) {
    if (_saved.isEmpty) {
      // `ListView` et non `Center` : le tirer-pour-rafraichir a besoin d'une
      // zone defilable, y compris quand la liste est vide.
      return ListView(
        children: [
          const SizedBox(height: 64),
          Icon(Icons.local_gas_station,
              size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(l10n.gas_no_station, textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(l10n.gas_no_station_hint,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      );
    }

    final stations = _sorted;
    return ListView.builder(
      itemCount: stations.length,
      itemBuilder: (context, index) {
        final saved = stations[index];
        final live = _live[saved.id];
        final price = live?.priceOf(_fuel);
        final address = live?.location ?? saved.label;
        final name = displayNameOf(saved, fresh: live?.location);
        final renamed = name != address;
        return Card(
          child: ListTile(
            title: Text(name),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Le carburant est rappele sur chaque ligne : la liste se lit
                // souvent en un coup d'oeil, sans remonter jusqu'au selecteur.
                Text(price == null
                    ? '${l10n.gas_price_unknown} — ${fuelLabel(l10n, _fuel)}'
                    : '${price.toStringAsFixed(3)} € — ${fuelLabel(l10n, _fuel)}'),
                // Une station renommee garderait sinon un nom sans lieu, et
                // « Intermarche » ne dit pas lequel.
                if (renamed)
                  Text(address,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.directions),
                  tooltip: l10n.gas_navigate,
                  // Desactive tant que les coordonnees ne sont pas connues :
                  // la reponse n'est pas encore arrivee, ou la station n'est
                  // pas geolocalisee dans le jeu de donnees.
                  onPressed: live != null && live.hasCoordinates
                      ? () => _navigateTo(live)
                      : null,
                ),
                PopupMenuButton<String>(
                  itemBuilder: (context) => [
                    PopupMenuItem(value: 'rename', child: Text(l10n.gas_rename)),
                    PopupMenuItem(value: 'delete', child: Text(l10n.delete)),
                  ],
                  onSelected: (action) => switch (action) {
                    'rename' => _rename(saved, address),
                    _ => _confirmDelete(saved, name),
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
