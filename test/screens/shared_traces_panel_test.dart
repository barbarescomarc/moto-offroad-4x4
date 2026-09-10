import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:moto_offroad/models/shared_trace.dart';
import 'package:moto_offroad/providers/rides_provider.dart';
import 'package:moto_offroad/providers/shared_traces_provider.dart';
import 'package:moto_offroad/screens/rides/rides_screen.dart';
import 'package:moto_offroad/screens/rides/shared_traces_panel.dart';
import 'package:moto_offroad/services/location_service.dart';
import 'package:moto_offroad/services/ride_database.dart';
import 'package:moto_offroad/services/ride_repository.dart';
import 'package:moto_offroad/services/shared_traces_api_client.dart';
import 'package:moto_offroad/widgets/map_search_bar.dart';

// Fiche minimale, avec les seuls champs que ces tests font varier.
SharedTraceSummary resume(
  String id, {
  String? nom,
  double? distanceFromRefM,
  int downloadCount = 0,
}) =>
    SharedTraceSummary(
      id: id,
      name: nom ?? 'Trace $id',
      authorName: 'Un rider',
      vehicle: TraceVehicle.moto,
      difficulty: TraceDifficulty.moyen,
      distanceM: 12400,
      publishedAt: DateTime(2026, 1, 1),
      downloadCount: downloadCount,
      startLat: 43.6,
      startLng: 1.44,
      distanceFromRefM: distanceFromRefM,
    );

// Même double que le test du provider (Tâche 18) : capture les appels,
// laisse le test choisir la réponse ou l'échec.
class _ApiFactice extends SharedTracesApiClient {
  _ApiFactice()
      : super(
          client: MockClient((_) async => http.Response('', 200)),
          readToken: () async => 'jeton',
        );

  final List<Map<String, Object?>> appels = [];
  List<SharedTraceSummary> reponse = [];
  Object? erreur;

  // Laisse un test geler la réponse en plein vol, pour observer un état de
  // chargement précis (pump() seul ne le garantit pas : un Future sans
  // aucun await réel peut se résoudre dans le même passage de microtâches
  // qu'un pump()).
  Completer<List<SharedTraceSummary>>? enAttente;

  @override
  Future<List<SharedTraceSummary>> list({
    double? lat,
    double? lng,
    double? radiusKm,
    TraceVehicle? vehicle,
    TraceDifficulty? difficulty,
    String? query,
    int? offset,
  }) async {
    appels.add({'lat': lat, 'rayon': radiusKm, 'engin': vehicle, 'depuis': offset});
    if (enAttente != null) return enAttente!.future;
    if (erreur != null) throw erreur!;
    return reponse;
  }
}

// Écran Sorties complet, avec une base de sorties locale vide en mémoire —
// suffisant pour vérifier la bascule entre les deux volets. La base doit
// être ouverte avant l'appel (via `tester.runAsync`, voir le test) : sqflite
// ffi passe par un isolate réel, incompatible avec l'horloge simulée d'un
// simple `pumpWidget`. Le provider du catalogue partagé est fourni par
// l'appelant, pour pouvoir observer ensuite les appels de son double API.
Widget appDeTest(RideRepository repository, SharedTracesProvider sharedTraces) => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => RidesProvider(repository: repository)),
        ChangeNotifierProvider.value(value: sharedTraces),
      ],
      child: const MaterialApp(home: RidesScreen()),
    );

Future<RideRepository> ouvrirDepotDeTest() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: RideDatabase.schemaVersion,
      onCreate: RideDatabase.onCreate,
    ),
  );
  return RideRepository(db);
}

// Le volet seul, branché sur un provider déjà préparé par le test — toujours
// le volet visible : ces tests portent sur son contenu, pas sur l'amorçage
// paresseux (couvert séparément via appDeTest + RidesScreen).
Widget panneauDeTest(SharedTracesProvider provider) => ChangeNotifierProvider.value(
      value: provider,
      child: const MaterialApp(home: Scaffold(body: SharedTracesPanel(estVisible: true))),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('l onglet Sorties propose les deux volets et bascule', (tester) async {
    // pumpAndSettle n'est pas utilisable ici : MyRidesPanel lance un
    // rafraîchissement réel (isolate sqflite ffi) à l'ouverture, dont
    // l'indicateur de chargement tournerait en boucle tant qu'il n'a pas
    // répondu. runAsync laisse ce rafraîchissement réellement se terminer
    // avant la fin du test, sinon il notifierait un provider déjà jeté une
    // fois le test suivant démarré.
    await tester.runAsync(() async {
      final repository = await ouvrirDepotDeTest();
      await tester.pumpWidget(appDeTest(repository, SharedTracesProvider(_ApiFactice())));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();

      expect(find.text('Mes sorties'), findsOneWidget);
      expect(find.text('Partagées'), findsOneWidget);

      await tester.tap(find.text('Partagées'));
      await tester.pump();

      expect(find.byType(SharedTracesPanel), findsOneWidget);
    });
  });

  testWidgets('le volet partage affiche les traces avec leur distance et leur compteur', (tester) async {
    final provider = SharedTracesProvider(
      _ApiFactice()
        ..reponse = [
          resume('t1', nom: 'Boucle du Sidobre', distanceFromRefM: 11000, downloadCount: 7),
        ],
    );
    await provider.setReference(const LatLng(43.6, 1.44));

    await tester.pumpWidget(panneauDeTest(provider));
    await tester.pumpAndSettle();

    expect(find.text('Boucle du Sidobre'), findsOneWidget);
    expect(find.textContaining('11 km'), findsOneWidget);
    expect(find.textContaining('7'), findsWidgets);
  });

  testWidgets('changer le rayon relance la recherche', (tester) async {
    final api = _ApiFactice()..reponse = [];
    final provider = SharedTracesProvider(api);
    await provider.setReference(const LatLng(43.6, 1.44));

    await tester.pumpWidget(panneauDeTest(provider));
    await tester.pumpAndSettle();

    await tester.tap(find.text('50 km'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('25 km').last);
    await tester.pumpAndSettle();

    expect(api.appels.last['rayon'], 25);
  });

  testWidgets('sans resultat, le volet le dit au lieu de rester vide', (tester) async {
    final provider = SharedTracesProvider(_ApiFactice()..reponse = []);
    await provider.setReference(const LatLng(43.6, 1.44));

    await tester.pumpWidget(panneauDeTest(provider));
    await tester.pumpAndSettle();

    expect(find.textContaining('Aucune trace'), findsOneWidget);
  });

  testWidgets('une erreur apres un chargement reussi garde les resultats et affiche le message', (tester) async {
    final api = _ApiFactice()..reponse = [resume('t1', nom: 'Boucle du Sidobre')];
    final provider = SharedTracesProvider(api);
    await provider.setReference(const LatLng(43.6, 1.44));

    await tester.pumpWidget(panneauDeTest(provider));
    await tester.pumpAndSettle();
    expect(find.text('Boucle du Sidobre'), findsOneWidget);

    api.erreur = const SharedTracesException(503, 'Le serveur ne repond pas');
    await provider.setRadius(25);
    await tester.pumpAndSettle();

    expect(find.text('Boucle du Sidobre'), findsOneWidget);
    expect(find.textContaining('Le serveur ne repond pas'), findsOneWidget);
  });

  testWidgets('un rechargement affiche un indicateur sans vider la liste', (tester) async {
    final api = _ApiFactice()..reponse = [resume('t1', nom: 'Boucle du Sidobre')];
    final provider = SharedTracesProvider(api);
    await provider.setReference(const LatLng(43.6, 1.44));

    await tester.pumpWidget(panneauDeTest(provider));
    await tester.pumpAndSettle();
    expect(find.text('Boucle du Sidobre'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    final porte = Completer<List<SharedTraceSummary>>();
    api.enAttente = porte;
    final rechargement = provider.setRadius(25);
    await tester.pump();

    expect(find.text('Boucle du Sidobre'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    porte.complete([resume('t1', nom: 'Boucle du Sidobre')]);
    await rechargement;
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('choisir un lieu propose une recherche et les favoris', (tester) async {
    final provider = SharedTracesProvider(_ApiFactice());

    await tester.pumpWidget(panneauDeTest(provider));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Choisir un lieu'));
    await tester.pumpAndSettle();

    expect(find.text('Rechercher un lieu'), findsOneWidget);
    expect(find.text('Mes favoris'), findsOneWidget);

    await tester.tap(find.text('Rechercher un lieu'));
    await tester.pumpAndSettle();

    expect(find.byType(MapSearchBar), findsOneWidget);
  });

  testWidgets('le catalogue partage n est interroge qu apres bascule sur Partagees', (tester) async {
    // LocationService est un singleton réel, sans plugin GPS en test : sans
    // une position connue, l'amorçage tombe systématiquement sur la voie
    // "Position inconnue" (aucun appel réseau, avec ou sans le correctif) —
    // ce qui ne prouverait rien. Le débogueur de position simule donc une
    // position déjà connue, pour que l'amorçage déclenche un vrai appel API
    // s'il se produit.
    addTearDown(() => LocationService().debugSetLastSnapshot(null));
    LocationService().debugSetLastSnapshot(
      GpsSnapshot(
        position: const LatLng(43.6, 1.44),
        accuracyMeters: 5,
        altitudeMeters: 200,
        speedKmh: 0,
        headingDeg: 0,
        timestamp: DateTime(2026, 1, 1),
      ),
    );

    final api = _ApiFactice()..reponse = [];
    final sharedTraces = SharedTracesProvider(api);

    await tester.runAsync(() async {
      final repository = await ouvrirDepotDeTest();
      await tester.pumpWidget(appDeTest(repository, sharedTraces));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();

      // Ouverture sur « Mes sorties » : aucun appel au catalogue partagé.
      expect(api.appels, isEmpty);

      await tester.tap(find.text('Partagées'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();

      expect(api.appels.length, 1);

      // Un aller-retour ne réamorce pas : l'IndexedStack garde l'état du
      // volet déjà activé, ce qui est tout le sens du correctif.
      await tester.tap(find.text('Mes sorties'));
      await tester.pump();
      await tester.tap(find.text('Partagées'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();

      expect(api.appels.length, 1);
    });
  });
}
