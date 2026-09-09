import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:i_zerak_app/l10n/app_localizations.dart';
import 'package:i_zerak_app/models/gas_station_dao.dart';
import 'package:i_zerak_app/pages/gas_stations/gas_station_page.dart';
import 'package:i_zerak_app/services/gas_service.dart';
import 'package:i_zerak_app/services/maps_launcher.dart';
import 'package:i_zerak_app/services/repositories/interfaces/i_gas_stations.dart';
import 'package:mockito/mockito.dart';

import '../../__mocks__/http_client_mock.dart' as mocks;

/// Depot en memoire : le comportement Hive est verifie ailleurs, ici seule la
/// page est en cause.
class _FakeFavorites implements IGasStations {
  _FakeFavorites([List<SavedGasStation>? initial, this._fuel = FuelType.gazole])
      : _stations = [...?initial];

  final List<SavedGasStation> _stations;
  FuelType _fuel;

  @override
  Future<List<SavedGasStation>> getAll() async => [..._stations];

  @override
  Future<void> add(SavedGasStation station) async {
    _stations.removeWhere((s) => s.id == station.id);
    _stations.add(station);
  }

  @override
  Future<void> delete(int id) async => _stations.removeWhere((s) => s.id == id);

  @override
  Future<void> rename(int id, String? name) async {
    final trimmed = name?.trim() ?? '';
    final index = _stations.indexWhere((s) => s.id == id);
    if (index < 0) {
      return;
    }
    final station = _stations[index];
    _stations[index] =
        (id: id, label: station.label, customName: trimmed.isEmpty ? null : trimmed);
  }

  @override
  Future<FuelType> readFuel() async => _fuel;

  @override
  Future<void> saveFuel(FuelType fuel) async => _fuel = fuel;
}

/// Retient l'itineraire demande plutot que d'ouvrir quoi que ce soit.
class _FakeMaps implements MapsLauncher {
  _FakeMaps({this.succeeds = true});

  final bool succeeds;
  final List<({double latitude, double longitude})> calls = [];

  @override
  Future<bool> navigateTo({required double latitude, required double longitude}) async {
    calls.add((latitude: latitude, longitude: longitude));
    return succeeds;
  }
}

Widget wrap(Widget child) => MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );

void main() {
  late mocks.MockClient client;

  /// Repond a toute requete par les stations demandees, prix compris.
  void stubStations(List<Map<String, dynamic>> records) {
    when(client.get(any)).thenAnswer((_) async => http.Response.bytes(
        utf8.encode(json.encode({'total_count': records.length, 'results': records})), 200));
  }

  /// `prices` porte les carburants effectivement vendus ; les autres colonnes
  /// partent nulles, comme dans la vraie reponse.
  Map<String, dynamic> record(int id, String address, Map<FuelType, double?> prices,
          {Map<String, double>? geom = const {'lat': 47.277, 'lon': -0.075}}) =>
      {
        'id': id,
        'adresse': address,
        'ville': 'Angers',
        'cp': '49100',
        'geom': geom,
        for (final fuel in FuelType.values) fuel.priceField: prices[fuel],
      };

  Map<String, dynamic> diesel(int id, String address, double? price) =>
      record(id, address, {FuelType.gazole: price});

  setUp(() => client = mocks.MockClient());

  GasStationPage page(IGasStations favorites, {MapsLauncher? maps}) => GasStationPage(
        service: GasService(client: client),
        favorites: favorites,
        maps: maps ?? _FakeMaps(),
      );

  /// Ouvre le menu de la premiere carte et choisit une action.
  Future<void> chooseAction(WidgetTester tester, String action) async {
    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(action).last);
    await tester.pumpAndSettle();
  }

  testWidgets('sans favori, la page invite a en ajouter', (tester) async {
    stubStations(const []);
    await tester.pumpWidget(wrap(page(_FakeFavorites())));
    await tester.pumpAndSettle();

    expect(find.text('Aucune station suivie'), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('les libelles enregistres s affichent avant la reponse reseau',
      (tester) async {
    // C'est tout l'interet de conserver le libelle a cote de l'identifiant :
    // la liste ne reste pas vide le temps de l'aller-retour. La requete est
    // laissee volontairement en suspens, sans quoi elle se resoudrait dans la
    // meme micro-tache et l'etat intermediaire serait inobservable.
    when(client.get(any)).thenAnswer((_) => Completer<http.Response>().future);
    await tester
        .pumpWidget(wrap(page(_FakeFavorites([(id: 1, label: 'Libelle en cache', customName: null)]))));
    await tester.pump();
    await tester.pump();

    expect(find.text('Libelle en cache'), findsOneWidget);
    expect(find.textContaining('Prix inconnu'), findsOneWidget);
  });

  testWidgets('les prix remplacent le cache une fois recus', (tester) async {
    stubStations([diesel(1, 'Quai Felix Faure', 2.25)]);
    await tester
        .pumpWidget(wrap(page(_FakeFavorites([(id: 1, label: 'Libelle en cache', customName: null)]))));
    await tester.pumpAndSettle();

    expect(find.text('Quai Felix Faure, Angers'), findsOneWidget);
    expect(find.textContaining('2.250'), findsOneWidget);
  });

  testWidgets('la moins chere passe en tete, celle sans prix en queue',
      (tester) async {
    // Une station sans gazole doit finir derniere, et non premiere comme le
    // ferait un tri qui traiterait son prix nul comme zero euro.
    stubStations([
      diesel(1, 'Chere', 2.40),
      diesel(2, 'Sans gazole', null),
      diesel(3, 'Bon marche', 1.90),
    ]);
    await tester.pumpWidget(wrap(page(_FakeFavorites([
      (id: 1, label: 'Chere', customName: null),
      (id: 2, label: 'Sans gazole', customName: null),
      (id: 3, label: 'Bon marche', customName: null),
    ]))));
    await tester.pumpAndSettle();

    final titles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((tile) => (tile.title as Text).data)
        .toList();
    expect(titles, [
      'Bon marche, Angers',
      'Chere, Angers',
      'Sans gazole, Angers',
    ]);
  });

  testWidgets('une API injoignable laisse la liste en place et signale la panne',
      (tester) async {
    when(client.get(any)).thenThrow(http.ClientException('hors ligne'));
    await tester
        .pumpWidget(wrap(page(_FakeFavorites([(id: 1, label: 'Quai Felix Faure', customName: null)]))));
    await tester.pumpAndSettle();

    expect(find.text('Données carburants injoignables'), findsOneWidget);
    expect(find.text('Quai Felix Faure'), findsOneWidget);
  });

  testWidgets('la suppression demande confirmation avant d agir', (tester) async {
    stubStations([diesel(1, 'Quai Felix Faure', 2.25)]);
    final favorites = _FakeFavorites([(id: 1, label: 'Quai Felix Faure', customName: null)]);
    await tester.pumpWidget(wrap(page(favorites)));
    await tester.pumpAndSettle();

    await chooseAction(tester, 'Supprimer');
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();

    expect((await favorites.getAll()).length, 1);

    await chooseAction(tester, 'Supprimer');
    await tester.tap(find.text('Supprimer').last);
    await tester.pumpAndSettle();

    expect(await favorites.getAll(), isEmpty);
    expect(find.text('Aucune station suivie'), findsOneWidget);
  });

  testWidgets('la recherche par ville ajoute la station choisie', (tester) async {
    stubStations([diesel(49100003, 'Boulevard du Bon Pasteur', 2.19)]);
    final favorites = _FakeFavorites();
    await tester.pumpWidget(wrap(page(favorites)));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Angers');
    // L'anti-rebond de la feuille est de 400 ms.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Boulevard du Bon Pasteur'));
    await tester.pumpAndSettle();

    expect((await favorites.getAll()).single.id, 49100003);
    expect(find.text('Boulevard du Bon Pasteur, Angers'), findsOneWidget);
  });

  group('itineraire', () {
    testWidgets('le bouton transmet les coordonnees de la station', (tester) async {
      stubStations([
        record(1, 'Quai Felix Faure', const {FuelType.gazole: 2.25},
            geom: const {'lat': 47.47738, 'lon': -0.55225}),
      ]);
      final maps = _FakeMaps();
      await tester.pumpWidget(wrap(page(
          _FakeFavorites([(id: 1, label: 'Quai Felix Faure', customName: null)]),
          maps: maps)));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.directions));
      await tester.pumpAndSettle();

      expect(maps.calls.single.latitude, 47.47738);
      expect(maps.calls.single.longitude, -0.55225);
    });

    testWidgets('sans coordonnees, le bouton est inerte plutot que fautif',
        (tester) async {
      // `geom` absent existe dans le jeu de donnees. Sans ce garde-fou, la
      // page dereferencait une latitude nulle et plantait sur un appui.
      stubStations([record(1, 'Quai Felix Faure', const {FuelType.gazole: 2.25}, geom: null)]);
      await tester.pumpWidget(wrap(
          page(_FakeFavorites([(id: 1, label: 'Quai Felix Faure', customName: null)]))));
      await tester.pumpAndSettle();

      final button = tester.widget<IconButton>(find.ancestor(
          of: find.byIcon(Icons.directions), matching: find.byType(IconButton)));
      expect(button.onPressed, isNull);
    });

    testWidgets('un echec de lancement est signale, jamais silencieux',
        (tester) async {
      stubStations([diesel(1, 'Quai Felix Faure', 2.25)]);
      await tester.pumpWidget(wrap(page(
          _FakeFavorites([(id: 1, label: 'Quai Felix Faure', customName: null)]),
          maps: _FakeMaps(succeeds: false))));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.directions));
      await tester.pumpAndSettle();

      expect(find.text('Aucune application d’itinéraire trouvée'), findsOneWidget);
    });
  });

  group('renommage', () {
    testWidgets('le nom choisi remplace l adresse, qui reste en dessous',
        (tester) async {
      // Le jeu de donnees ne publie aucune enseigne : renommer est le seul
      // moyen d'obtenir « Intermarche » plutot qu'une adresse en capitales.
      stubStations([diesel(1, 'BD PORT GENTIL', 2.25)]);
      final favorites = _FakeFavorites([(id: 1, label: 'BD PORT GENTIL', customName: null)]);
      await tester.pumpWidget(wrap(page(favorites)));
      await tester.pumpAndSettle();

      await chooseAction(tester, 'Renommer');
      await tester.enterText(find.byType(TextField), 'Intermarche Thouars');
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();

      expect((await favorites.getAll()).single.customName, 'Intermarche Thouars');
      expect(find.text('Intermarche Thouars'), findsOneWidget);
      // L'adresse doit rester visible : un nom sans lieu ne dit pas laquelle.
      expect(find.text('BD PORT GENTIL, Angers'), findsOneWidget);
    });

    testWidgets('un champ vide rend la station a son adresse', (tester) async {
      stubStations([diesel(1, 'BD PORT GENTIL', 2.25)]);
      final favorites =
          _FakeFavorites([(id: 1, label: 'BD PORT GENTIL', customName: 'Ancien nom')]);
      await tester.pumpWidget(wrap(page(favorites)));
      await tester.pumpAndSettle();
      expect(find.text('Ancien nom'), findsOneWidget);

      await chooseAction(tester, 'Renommer');
      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();

      expect((await favorites.getAll()).single.customName, isNull);
      expect(find.text('BD PORT GENTIL, Angers'), findsOneWidget);
    });

    testWidgets('annuler ne touche a rien', (tester) async {
      stubStations([diesel(1, 'BD PORT GENTIL', 2.25)]);
      final favorites =
          _FakeFavorites([(id: 1, label: 'BD PORT GENTIL', customName: 'Ancien nom')]);
      await tester.pumpWidget(wrap(page(favorites)));
      await tester.pumpAndSettle();

      await chooseAction(tester, 'Renommer');
      await tester.enterText(find.byType(TextField), 'Autre chose');
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();

      expect((await favorites.getAll()).single.customName, 'Ancien nom');
    });

    testWidgets('la confirmation de suppression nomme ce qui est affiche',
        (tester) async {
      stubStations([diesel(1, 'BD PORT GENTIL', 2.25)]);
      await tester.pumpWidget(wrap(page(
          _FakeFavorites([(id: 1, label: 'BD PORT GENTIL', customName: 'Intermarche')]))));
      await tester.pumpAndSettle();

      await chooseAction(tester, 'Supprimer');

      expect(find.textContaining('Intermarche'), findsWidgets);
    });
  });

  group('selecteur de carburant', () {
    /// Une station qui vend les trois, a des prix distincts : c'est ce qui rend
    /// le changement de carburant observable a l'ecran.
    List<Map<String, dynamic>> threeFuels() => [
          record(1, 'Quai Felix Faure', const {
            FuelType.gazole: 2.250,
            FuelType.sp98: 2.190,
            FuelType.e85: 0.871,
          }),
        ];

    testWidgets('le choix enregistre est repris a l ouverture', (tester) async {
      stubStations(threeFuels());
      await tester.pumpWidget(wrap(page(
          _FakeFavorites([(id: 1, label: 'Quai Felix Faure', customName: null)], FuelType.e85))));
      await tester.pumpAndSettle();

      expect(find.textContaining('0.871'), findsOneWidget);
      expect(find.textContaining('2.250'), findsNothing);
    });

    testWidgets('changer de carburant change le prix affiche, sans requete',
        (tester) async {
      // Les six prix arrivent dans la meme reponse : basculer ne doit couter
      // aucun aller-retour reseau.
      stubStations(threeFuels());
      await tester
          .pumpWidget(wrap(page(_FakeFavorites([(id: 1, label: 'Quai Felix Faure', customName: null)]))));
      await tester.pumpAndSettle();
      expect(find.textContaining('2.250'), findsOneWidget);

      clearInteractions(client);
      await tester.tap(find.byType(DropdownButton<FuelType>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('SP98').last);
      await tester.pumpAndSettle();

      expect(find.textContaining('2.190'), findsOneWidget);
      verifyNever(client.get(any));
    });

    testWidgets('le choix est enregistre des le changement', (tester) async {
      stubStations(threeFuels());
      final favorites = _FakeFavorites([(id: 1, label: 'Quai Felix Faure', customName: null)]);
      await tester.pumpWidget(wrap(page(favorites)));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButton<FuelType>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('E85').last);
      await tester.pumpAndSettle();

      expect(await favorites.readFuel(), FuelType.e85);
    });

    testWidgets('un carburant non vendu affiche un prix inconnu, pas zero euro',
        (tester) async {
      stubStations(threeFuels());
      await tester.pumpWidget(wrap(page(
          _FakeFavorites([(id: 1, label: 'Quai Felix Faure', customName: null)], FuelType.sp95))));
      await tester.pumpAndSettle();

      expect(find.textContaining('Prix inconnu'), findsOneWidget);
      expect(find.textContaining('0.000'), findsNothing);
    });

    testWidgets('le tri suit le carburant choisi', (tester) async {
      // La station la moins chere au gazole est la plus chere au SP98 :
      // un tri fige sur le gazole les laisserait dans le meme ordre.
      stubStations([
        record(1, 'A', const {FuelType.gazole: 1.90, FuelType.sp98: 2.40}),
        record(2, 'B', const {FuelType.gazole: 2.40, FuelType.sp98: 1.90}),
      ]);
      await tester.pumpWidget(wrap(page(_FakeFavorites([
        (id: 1, label: 'A', customName: null),
        (id: 2, label: 'B', customName: null),
      ]))));
      await tester.pumpAndSettle();

      List<String?> order() => tester
          .widgetList<ListTile>(find.byType(ListTile))
          .map((tile) => (tile.title as Text).data)
          .toList();

      expect(order(), ['A, Angers', 'B, Angers']);

      await tester.tap(find.byType(DropdownButton<FuelType>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('SP98').last);
      await tester.pumpAndSettle();

      expect(order(), ['B, Angers', 'A, Angers']);
    });
  });
}
