import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:moto_offroad/models/shared_trace.dart';
import 'package:moto_offroad/providers/rides_provider.dart';
import 'package:moto_offroad/screens/rides/shared_trace_detail_screen.dart';
import 'package:moto_offroad/services/ride_database.dart';
import 'package:moto_offroad/services/ride_repository.dart';
import 'package:moto_offroad/services/shared_traces_api_client.dart';

// Fiche minimale, comme dans le test de l importeur (Tâche 20, service).
SharedTraceDetail ficheFactice({
  String id = 't1',
  String nom = 'Trace test',
  String description = 'Description test',
  int downloadCount = 0,
}) =>
    SharedTraceDetail(
      id: id,
      name: nom,
      authorName: 'Un rider',
      vehicle: TraceVehicle.moto,
      difficulty: TraceDifficulty.moyen,
      distanceM: 12400,
      publishedAt: DateTime(2026, 1, 1),
      downloadCount: downloadCount,
      startLat: 43.6,
      startLng: 1.44,
      description: description,
      preview: const [LatLng(43.60, 1.44), LatLng(43.62, 1.46)],
    );

String gpxFactice() => '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="test" xmlns="http://www.topografix.com/GPX/1/1">
  <trk>
    <name>Test</name>
    <trkseg>
      <trkpt lat="43.60" lon="1.44"><time>2026-01-01T10:00:00Z</time></trkpt>
      <trkpt lat="43.61" lon="1.45"><time>2026-01-01T10:01:00Z</time></trkpt>
      <trkpt lat="43.62" lon="1.46"><time>2026-01-01T10:02:00Z</time></trkpt>
    </trkseg>
  </trk>
</gpx>''';

// Double du client HTTP : rend la fiche demandée telle quelle, jamais de
// vraie requête réseau (le MockClient sous-jacent n'est là que pour
// satisfaire le constructeur de SharedTracesApiClient).
class _ApiFactice extends SharedTracesApiClient {
  _ApiFactice() : super(client: MockClient((_) async => http.Response('', 200)), readToken: () async => 'jeton');

  SharedTraceDetail? ficheReponse;
  String gpxReponse = gpxFactice();

  @override
  Future<SharedTraceDetail> detail(String id) async => ficheReponse!;

  @override
  Future<String> downloadGpx(String id) async => gpxReponse;
}

// Écran seul, avec une base de sorties locale (réelle, en mémoire) fournie
// par l appelant — nécessaire pour le bouton Télécharger, qui écrit via
// SharedTraceImporter.
Widget ficheDeTest(SharedTraceDetail fiche, RideRepository repo) => MultiProvider(
      providers: [
        Provider<RideRepository>.value(value: repo),
        ChangeNotifierProvider(create: (_) => RidesProvider(repository: repo)),
      ],
      child: MaterialApp(
        home: SharedTraceDetailScreen(traceId: fiche.id, api: _ApiFactice()..ficheReponse = fiche),
      ),
    );

void main() {
  sqfliteFfiInit();

  late Database db;
  late RideRepository repo;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: RideDatabase.schemaVersion, onCreate: RideDatabase.onCreate),
    );
    repo = RideRepository(db);
  });
  tearDown(() async => db.close());

  testWidgets('la fiche affiche description, auteur, compteur et les deux boutons', (tester) async {
    await tester.pumpWidget(
      ficheDeTest(ficheFactice(nom: 'Boucle', description: 'Deux gues', downloadCount: 7), repo),
    );
    await tester.pumpAndSettle();
    expect(find.text('Boucle'), findsOneWidget);
    expect(find.text('Deux gues'), findsOneWidget);
    expect(find.textContaining('7'), findsWidgets);
    expect(find.text('Télécharger'), findsOneWidget);
    expect(find.text('Signaler'), findsOneWidget);
  });

  testWidgets('apres telechargement, le bouton dit que la trace est dans les sorties', (tester) async {
    // L import écrit dans une base sqflite ffi réelle (isolate) : sa fin ne
    // programme pas de nouvelle frame tant que le setState final n a pas eu
    // lieu, donc pumpAndSettle seul peut rendre la main avant que l écriture
    // ne soit terminée — runAsync + une vraie attente laissent ce travail
    // réellement se terminer (même stratégie que shared_traces_panel_test).
    await tester.runAsync(() async {
      await tester.pumpWidget(ficheDeTest(ficheFactice(), repo));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Télécharger'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();
      expect(find.textContaining('Dans tes sorties'), findsOneWidget);
    });
  });
}
