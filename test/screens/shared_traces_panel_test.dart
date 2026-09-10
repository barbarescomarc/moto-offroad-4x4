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
import 'package:moto_offroad/services/ride_database.dart';
import 'package:moto_offroad/services/ride_repository.dart';
import 'package:moto_offroad/services/shared_traces_api_client.dart';

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
    if (erreur != null) throw erreur!;
    return reponse;
  }
}

// Écran Sorties complet, avec une base de sorties locale vide en mémoire —
// suffisant pour vérifier la bascule entre les deux volets. La base doit
// être ouverte avant l'appel (via `tester.runAsync`, voir le test) : sqflite
// ffi passe par un isolate réel, incompatible avec l'horloge simulée d'un
// simple `pumpWidget`.
Widget appDeTest(RideRepository repository) => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => RidesProvider(repository: repository)),
        ChangeNotifierProvider(create: (_) => SharedTracesProvider(_ApiFactice())),
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

// Le volet seul, branché sur un provider déjà préparé par le test.
Widget panneauDeTest(SharedTracesProvider provider) => ChangeNotifierProvider.value(
      value: provider,
      child: const MaterialApp(home: Scaffold(body: SharedTracesPanel())),
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
      await tester.pumpWidget(appDeTest(repository));
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
}
