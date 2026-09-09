import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/gas_station_dao.dart';

/// Libelle affichable d'un carburant.
///
/// Isole ici, et non porte par `FuelType` : l'enumeration est Dart pur et
/// testee sans Flutter, alors que ces libelles passent par la localisation.
/// Un `switch` exhaustif, sans branche par defaut, pour qu'un carburant ajoute
/// un jour au jeu de donnees fasse echouer la compilation plutot que d'arriver
/// sans nom a l'ecran.
String fuelLabel(AppLocalizations l10n, FuelType fuel) => switch (fuel) {
      FuelType.gazole => l10n.fuel_gazole,
      FuelType.sp95 => l10n.fuel_sp95,
      FuelType.sp98 => l10n.fuel_sp98,
      FuelType.e10 => l10n.fuel_e10,
      FuelType.e85 => l10n.fuel_e85,
      FuelType.gplc => l10n.fuel_gplc,
    };
