import 'dart:async';

import 'package:flutter/material.dart';
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/gas_station_dao.dart';
import 'package:i_zerak_app/pages/gas_stations/widgets/fuel_label.dart';
import 'package:i_zerak_app/services/gas_service.dart';

Future<GasStationDao?> showAddGasStationSheet(
  BuildContext context, {
  required GasService service,
  required FuelType fuel,
  required Set<int> alreadySaved,
}) =>
    showModalBottomSheet<GasStationDao>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        // Laisse la place au clavier, sans quoi le champ de recherche est
        // masque des la premiere frappe.
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _AddGasStationSheet(
            service: service, fuel: fuel, alreadySaved: alreadySaved),
      ),
    );

class _AddGasStationSheet extends StatefulWidget {
  const _AddGasStationSheet(
      {required this.service, required this.fuel, required this.alreadySaved});

  final GasService service;

  /// Reprend le choix de la page : les prix affiches ici et la, ainsi que le
  /// tri des resultats, portent sur le meme carburant.
  final FuelType fuel;

  /// Les stations deja suivies restent visibles dans les resultats, mais
  /// grisees : les faire disparaitre laisserait croire que la recherche les a
  /// manquees.
  final Set<int> alreadySaved;

  @override
  State<_AddGasStationSheet> createState() => _AddGasStationSheetState();
}

class _AddGasStationSheetState extends State<_AddGasStationSheet> {
  final _controller = TextEditingController();

  Timer? _debounce;
  List<GasStationDao> _results = const [];
  bool _searching = false;
  bool _searched = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    // Sans anti-rebond, chaque frappe declencherait une requete a l'API
    // publique.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(value));
  }

  Future<void> _search(String query) async {
    if (normalizeSearchTerm(query).length < 2) {
      setState(() {
        _results = const [];
        _searched = false;
        _error = null;
      });
      return;
    }

    setState(() {
      _searching = true;
      _error = null;
    });

    try {
      final results = await widget.service.search(query, fuel: widget.fuel);
      if (!mounted) {
        return;
      }
      setState(() {
        _results = results;
        _searching = false;
        _searched = true;
      });
    } on GasServiceException {
      if (!mounted) {
        return;
      }
      setState(() {
        _searching = false;
        _results = const [];
        _searched = true;
        _error = AppLocalizations.of(context)!.gas_unreachable;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.gas_add_station,
                style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              autocorrect: false,
              textInputAction: TextInputAction.search,
              onChanged: _onChanged,
              onSubmitted: _search,
              decoration: InputDecoration(
                labelText: l10n.gas_search_field,
                helperText: l10n.gas_search_hint,
                border: const OutlineInputBorder(),
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(12.0),
                        child: SizedBox(
                            width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : const Icon(Icons.search),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: Text(_error!,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Theme.of(context).colorScheme.error)),
              ),
            const SizedBox(height: 8),
            // Sans ce rappel, un tiret dans la colonne de droite se lit comme
            // « station sans prix » alors qu'il ne concerne que le carburant
            // choisi sur la page.
            Text(l10n.gas_prices_shown(fuelLabel(l10n, widget.fuel)),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            // Hauteur bornee : la feuille ne doit pas grandir sans fin quand la
            // recherche porte sur une grande ville.
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.4),
              child: _resultsView(context, l10n),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                  onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultsView(BuildContext context, AppLocalizations l10n) {
    if (_results.isEmpty) {
      // Le vide initial et le vide apres recherche ne disent pas la meme
      // chose : sans cette distinction, une recherche infructueuse ressemble a
      // une page qui n'a rien fait.
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: Text(
          _searched && _error == null ? l10n.gas_no_result : '',
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      itemCount: _results.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final station = _results[index];
        final saved = widget.alreadySaved.contains(station.id);
        final price = station.priceOf(widget.fuel);
        return ListTile(
          enabled: !saved,
          title: Text(station.address),
          subtitle: Text('${station.postalCode} ${station.city}'),
          trailing: Text(
            // Un tiret, et non « 0,000 € » : la station ne vend pas ce
            // carburant, ou en est en rupture.
            saved
                ? l10n.gas_already_saved
                : price == null
                    ? '—'
                    : '${price.toStringAsFixed(3)} €',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          onTap: saved ? null : () => Navigator.pop(context, station),
        );
      },
    );
  }
}
