import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:moto_offroad/models/ride.dart';
import 'package:moto_offroad/models/shared_trace.dart';
import 'package:moto_offroad/services/ride_database.dart';
import 'package:moto_offroad/services/ride_repository.dart';
import 'package:moto_offroad/services/shared_trace_importer.dart';

// Fiche minimale : seuls les champs que les tests font varier sont
// paramétrables, le reste est une valeur plausible quelconque.
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

// Trois points, horodatés et déplacés, pour que la distance calculée soit
// non nulle et l'ordre chronologique garanti.
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

  test('l import cree une sortie importee, rattachee a la trace partagee', () async {
    final importer = SharedTraceImporter(repo);

    final ride = await importer.import(ficheFactice(id: 't42', nom: 'Boucle du Sidobre'), gpxFactice());

    expect(ride.source, RideSource.imported);
    expect(ride.status, RideStatus.finished);
    expect(ride.sharedTraceId, 't42');
    expect(ride.name, 'Boucle du Sidobre');
    final points = await repo.pointsOf(ride.id);
    expect(points.length, 3);
    expect(points.every((p) => p.segment == 0), isTrue);
    expect(ride.stats.distanceMeters, greaterThan(0));
  });

  test('deux imports de la meme trace font deux sorties distinctes', () async {
    final importer = SharedTraceImporter(repo);
    final a = await importer.import(ficheFactice(id: 't42'), gpxFactice());
    final b = await importer.import(ficheFactice(id: 't42'), gpxFactice());
    expect(a.id, isNot(b.id));
    expect((await repo.listRides()).length, 2);
  });

  test('un GPX illisible remonte une erreur au lieu de creer une sortie vide', () async {
    final importer = SharedTraceImporter(repo);
    await expectLater(() => importer.import(ficheFactice(), 'pas du xml <<<'), throwsA(isA<FormatException>()));
    expect(await repo.listRides(), isEmpty);
  });

  // Le premier point porte un horodatage réel tardif (10:00:10), le second
  // n'en porte aucun et retombe sur fiche.publishedAt (minuit) + 1s — très
  // antérieur au premier sans le clamp de l'importeur. Couvre la Trouvaille
  // 3 de la relecture : un GPX mélangeant points horodatés et non horodatés
  // ne doit jamais produire un temps de déplacement négatif.
  test('les horodatages restent strictement croissants meme si un point n a pas de time', () async {
    final importer = SharedTraceImporter(repo);
    const gpxMixte = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="test" xmlns="http://www.topografix.com/GPX/1/1">
  <trk>
    <name>Test</name>
    <trkseg>
      <trkpt lat="43.60" lon="1.44"><time>2026-01-01T10:00:10Z</time></trkpt>
      <trkpt lat="43.61" lon="1.45"></trkpt>
      <trkpt lat="43.62" lon="1.46"><time>2026-01-01T10:00:20Z</time></trkpt>
    </trkseg>
  </trk>
</gpx>''';

    final ride = await importer.import(ficheFactice(id: 't99'), gpxMixte);
    final points = await repo.pointsOf(ride.id);

    for (var i = 1; i < points.length; i++) {
      expect(
        points[i].timestamp.isAfter(points[i - 1].timestamp),
        isTrue,
        reason: 'point $i (${points[i].timestamp}) devrait suivre le point ${i - 1} (${points[i - 1].timestamp})',
      );
    }
    expect(ride.stats.movingTime.inSeconds, greaterThanOrEqualTo(0));
  });
}
