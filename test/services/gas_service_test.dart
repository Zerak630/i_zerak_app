import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:i_zerak_app/models/gas_station_dao.dart';
import 'package:i_zerak_app/services/gas_service.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../__mocks__/http_client_mock.dart' as mocks;

/// Reponse minimale de l'API, reduite aux colonnes demandees par `select`.
String body(List<Map<String, dynamic>> records) =>
    json.encode({'total_count': records.length, 'results': records});

/// Un enregistrement porte les six colonnes de prix, comme la vraie reponse :
/// c'est ce qui permet de changer de carburant sans requete supplementaire.
Map<String, dynamic> record({
  int id = 49400004,
  String address = 'ZI Ecoparc',
  String city = 'Saumur',
  String postalCode = '49400',
  Map<FuelType, double?> prices = const {FuelType.gazole: 1.5},
}) =>
    {
      'id': id,
      'adresse': address,
      'ville': city,
      'cp': postalCode,
      for (final fuel in FuelType.values) fuel.priceField: prices[fuel],
    };

void main() {
  late mocks.MockClient client;

  /// L'URI reellement construite par le service.
  Uri capturedUri() => verify(client.get(captureAny)).captured.single as Uri;

  void stub(String responseBody, {int status = 200}) {
    when(client.get(any)).thenAnswer(
        (_) async => http.Response.bytes(utf8.encode(responseBody), status));
  }

  setUp(() => client = mocks.MockClient());

  group('normalizeSearchTerm', () {
    test('les accents sont deposes', () {
      // L'index de l'API est sans diacritiques : « Saint-Barthélemy » ecrit tel
      // quel ne renvoie aucun resultat, verifie contre le service reel.
      expect(normalizeSearchTerm('Saint-Barthélemy'), 'saint barthelemy');
    });

    test('traits d union et apostrophes deviennent des separateurs', () {
      expect(normalizeSearchTerm('Les Ponts-de-Cé'), 'les ponts de ce');
      expect(normalizeSearchTerm("Saint-Barthélemy-d'Anjou"), 'saint barthelemy d anjou');
    });

    test('les chiffres d un code postal traversent intacts', () {
      expect(normalizeSearchTerm('49100'), '49100');
    });

    test('guillemets et antislashs disparaissent', () {
      // C'est ce qui empeche une saisie de s'echapper de la clause `where` :
      // la normalisation et l'assainissement sont la meme operation.
      expect(normalizeSearchTerm(r'a" or 1=1 \'), 'a or 1 1');
    });

    test('une saisie sans lettre ni chiffre se reduit au vide', () {
      expect(normalizeSearchTerm('  ---  '), '');
    });
  });

  group('search', () {
    test('interroge la ville et le code postal a la fois', () async {
      stub(body([record()]));
      await GasService(client: client).search('Angers');

      final uri = capturedUri();
      expect(uri.host, 'data.economie.gouv.fr');
      expect(uri.queryParameters['where'], 'ville like "angers" or cp like "angers"');
      // Sans `select`, chaque enregistrement transporte horaires et services en
      // JSON echappe, soit une reponse vingt fois plus lourde.
      expect(uri.queryParameters['select'],
          'id,adresse,ville,cp,geom,gazole_prix,sp95_prix,sp98_prix,e10_prix,e85_prix,gplc_prix');
    });

    test('une saisie vide ne declenche aucune requete', () async {
      await GasService(client: client).search('   ');
      verifyNever(client.get(any));
    });

    test('les accents sont normalises avant l envoi', () async {
      stub(body([]));
      await GasService(client: client).search('Les Ponts-de-Cé');

      expect(capturedUri().queryParameters['where'],
          'ville like "les ponts de ce" or cp like "les ponts de ce"');
    });

    test('une station sans gazole est conservee, avec un prix nul', () async {
      // Typer ce champ `double` non nullable levait une erreur de type et
      // faisait disparaitre la station de la liste, sans message.
      stub(body([record(prices: const {})]));
      final results = await GasService(client: client).search('Angers');

      expect(results.single.priceOf(FuelType.gazole), isNull);
    });

    test('les accents de la reponse sont relus en UTF-8', () async {
      // Sans decodage explicite, `response.body` retombe sur du latin-1 et
      // « Levées » arrive illisible.
      stub(body([record(address: 'Saint-Lambert-des-Levées')]));
      final results = await GasService(client: client).search('Saumur');

      expect(results.single.address, 'Saint-Lambert-des-Levées');
    });

    test('le tri suit le carburant demande', () async {
      // Sans cela, une recherche au SP98 restait classee par le prix du
      // gazole : les resultats paraissaient dans le desordre.
      stub(body([record()]));
      await GasService(client: client).search('Angers', fuel: FuelType.sp98);

      expect(capturedUri().queryParameters['order_by'], 'sp98_prix');
    });

    test('le gazole reste le tri par defaut', () async {
      stub(body([record()]));
      await GasService(client: client).search('Angers');

      expect(capturedUri().queryParameters['order_by'], 'gazole_prix');
    });
  });

  group('carburants', () {
    test('les six prix sont relus, pas seulement celui qui est affiche', () async {
      // C'est ce qui permet de changer de carburant sans repasser par le
      // reseau : tout arrive dans la meme reponse.
      stub(body([
        record(prices: const {
          FuelType.gazole: 2.25,
          FuelType.sp98: 2.19,
          FuelType.e85: 0.87,
        })
      ]));
      final station = (await GasService(client: client).search('Angers')).single;

      expect(station.priceOf(FuelType.gazole), 2.25);
      expect(station.priceOf(FuelType.sp98), 2.19);
      expect(station.priceOf(FuelType.e85), 0.87);
    });

    test('un carburant non vendu est absent, il ne vaut pas zero', () async {
      stub(body([record(prices: const {FuelType.gazole: 2.25})]));
      final station = (await GasService(client: client).search('Angers')).single;

      expect(station.prices.containsKey(FuelType.sp95), isFalse);
      expect(station.priceOf(FuelType.sp95), isNull);
    });

    test('le nom de colonne se derive du nom de la constante', () async {
      // Une seule liste a tenir a jour : renommer une constante renomme la
      // colonne, et le test le dit avant l'API.
      expect(FuelType.gazole.priceField, 'gazole_prix');
      expect(FuelType.gplc.priceField, 'gplc_prix');
    });

    test('un carburant inconnu retombe sur le gazole', () async {
      // Le nom est la cle de persistance : une valeur ecrite par une version
      // ulterieure ne doit pas empecher la page de s'ouvrir.
      expect(FuelType.fromName('diesel_de_demain'), FuelType.gazole);
      expect(FuelType.fromName(null), FuelType.gazole);
      expect(FuelType.fromName('sp98'), FuelType.sp98);
    });
  });

  group('fetchByIds', () {
    test('une seule requete pour toutes les stations', () async {
      stub(body([record(id: 1), record(id: 2), record(id: 3)]));
      final results = await GasService(client: client).fetchByIds([1, 2, 3]);

      expect(results.length, 3);
      // captured.single vaut assertion : plus d'un appel le ferait echouer.
      expect(capturedUri().queryParameters['where'], 'id in (1, 2, 3)');
    });

    test('une liste vide n atteint pas le reseau', () async {
      // Une clause `id in ()` est une erreur de syntaxe cote API : la sortie
      // anticipee n'est pas une optimisation, c'est une correction.
      expect(await GasService(client: client).fetchByIds(const []), isEmpty);
      verifyNever(client.get(any));
    });

    test('au-dela de cent stations, la requete est fractionnee', () async {
      stub(body([record()]));
      await GasService(client: client).fetchByIds(List.generate(150, (i) => i + 1));

      verify(client.get(any)).called(2);
    });
  });

  group('erreurs', () {
    test('un code HTTP non 200 leve une GasServiceException', () async {
      stub('{}', status: 503);
      expect(() => GasService(client: client).search('Angers'),
          throwsA(isA<GasServiceException>()));
    });

    test('une panne reseau est traduite, pas propagee telle quelle', () async {
      // La page distingue une API indisponible d'une erreur de programmation :
      // laisser filer une ClientException lui retirerait ce moyen.
      when(client.get(any)).thenThrow(http.ClientException('hors ligne'));
      expect(() => GasService(client: client).search('Angers'),
          throwsA(isA<GasServiceException>()));
    });
  });
}
