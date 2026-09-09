/// Les carburants publies par le jeu de donnees, dans l'ordre d'affichage.
///
/// Le nom de la constante sert de cle de persistance : le renommer invaliderait
/// le choix enregistre sur les telephones deja installes, qui retomberaient
/// silencieusement sur le gazole.
enum FuelType {
  gazole,
  sp95,
  sp98,
  e10,
  e85,
  gplc;

  /// Colonne correspondante cote API. Les six suivent la meme convention, d'ou
  /// la derivation depuis le nom plutot qu'une seconde liste a tenir a jour.
  String get priceField => '${name}_prix';

  /// Repli explicite sur le gazole : une valeur enregistree par une version
  /// ulterieure, ou une boite corrompue, ne doit pas empecher la page de
  /// s'ouvrir.
  static FuelType fromName(String? raw) =>
      values.firstWhere((fuel) => fuel.name == raw, orElse: () => gazole);
}

/// Une station-service telle que la renvoie l'API des prix des carburants.
///
/// Dart pur, sans import Flutter : le modele et le service qui le construit
/// sont testes avec `package:test`, sans machinerie de widgets.
class GasStationDao {
  const GasStationDao({
    required this.id,
    required this.address,
    required this.city,
    required this.postalCode,
    required this.prices,
  });

  /// Identifiant national de la station, stable dans le temps : c'est lui, et
  /// lui seul, qui est enregistre dans les favoris.
  final int id;
  final String address;
  final String city;
  final String postalCode;

  /// Uniquement les carburants effectivement vendus, et cotes du jour.
  ///
  /// Un carburant absent de cette table n'est pas a zero euro : il n'est pas
  /// vendu ici, ou la station est en rupture. La distinction compte — la
  /// version precedente typait le prix du gazole `double` non nullable, et
  /// toute station qui n'en vendait pas disparaissait de la liste sur une
  /// erreur de type, sans message.
  final Map<FuelType, double> prices;

  double? priceOf(FuelType fuel) => prices[fuel];

  /// Libelle affiche, et valeur mise en cache par le depot des favoris.
  String get location => '$address, $city';

  factory GasStationDao.fromJson(Map<String, dynamic> json) => GasStationDao(
        id: json['id'] as int,
        address: (json['adresse'] as String?)?.trim() ?? '',
        city: (json['ville'] as String?)?.trim() ?? '',
        postalCode: (json['cp'] as String?)?.trim() ?? '',
        prices: {
          for (final fuel in FuelType.values)
            if ((json[fuel.priceField] as num?)?.toDouble() case final double price) fuel: price,
        },
      );
}

/// Une station retenue en favori.
///
/// Le libelle est conserve a cote de l'identifiant pour que la liste s'affiche
/// avant la reponse du reseau, et reste lisible quand l'API est injoignable.
/// Les prix, eux, ne sont jamais mis en cache : ils changent plusieurs fois par
/// jour, et un prix perime affiche sans reserve serait pire que pas de prix du
/// tout.
typedef SavedGasStation = ({int id, String label});
