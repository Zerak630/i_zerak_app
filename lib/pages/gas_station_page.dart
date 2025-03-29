import 'package:flutter/material.dart';
import 'package:i_zerak_app/models/gas_station_dao.dart';
import 'package:i_zerak_app/services/gas_service.dart';
//import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class GasStationPage extends StatefulWidget {
  final GasService service;

  GasStationPage({super.key, service}) : service = service ?? GasService();

  @override
  State<GasStationPage> createState() => _GasStationPageState();
}

class _GasStationPageState extends State<GasStationPage> {
  final List<GasStationDao> _gasStations = [];

  @override
  void initState() {
    widget.service.getSavedGasStations().then((savedGasStations) {
      for (int id in savedGasStations) {
        widget.service.getGasStationById(id).then((gasStation) {
          setState(() {
            _gasStations.add(gasStation);
            _gasStations.sort((a, b) => a.price.compareTo(b.price));
          });
        });
      }
    });

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        // Text(
        //   AppLocalizations.of(context)!.gas_title,
        //   style: Theme.of(context).textTheme.headlineSmall,
        // ),
        Expanded(
          child: ListView.builder(
            itemCount: _gasStations.length,
            itemBuilder: (context, index) {
              final gasStation = _gasStations[index];
              return Card(
                child: ListTile(
                  title: Text(gasStation.location),
                  subtitle: Text('${gasStation.price.toStringAsFixed(3)}€'),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
