import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:moto_offroad/models/ride.dart';
import 'package:moto_offroad/services/ride_database.dart';
import 'package:moto_offroad/services/ride_merge_service.dart';
import 'package:moto_offroad/services/ride_repository.dart';

final _t0 = DateTime(2026, 9, 3, 9, 0, 0);

RidePoint _p(int seq, int segment, double lat, int secs) => RidePoint(
  rideId:    'r1',
  seq:       seq,
  segment:   segment,
  lat:       lat,
  lng:       6.0,
  altitude:  300,
  speedKmh:  40,
  timestamp: _t0.add(Duration(seconds: secs)),
);

Ride _ride() => Ride(
  id:        'r1',
  name:      'Rando du Ventoux',
  startedAt: _t0,
  source:    RideSource.recorded,
  status:    RideStatus.finished,
  stats:     RideStats.empty,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Database db;
  late RideRepository repo;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version:  RideDatabase.schemaVersion,
        onCreate: RideDatabase.onCreate,
      ),
    );
    repo = RideRepository(db);
    await repo.insertRide(_ride());
  });

  tearDown(() async => db.close());

  // Deux traces séparées par un trou de signal : segment 0 puis segment 1,
  // avec environ 1,1 km de forêt entre les deux.
  Future<void> deuxTraces() => repo.appendPoints([
        _p(0, 0, 44.0000, 0),
        _p(1, 0, 44.0010, 10),
        _p(2, 1, 44.0110, 200),
        _p(3, 1, 44.0120, 210),
      ]);

  test('fusionner sans points intermédiaires réunit les deux segments', () async {
    await deuxTraces();

    await RideMergeService.mergeGaps(
      ride: _ride(), repo: repo, gapSegments: {1}, interpolate: false,
    );

    final points = await repo.pointsOf('r1');
    expect(points.length, 4, reason: 'aucun point ajouté');
    expect(points.map((p) => p.segment).toSet(), {0});
    expect(points.map((p) => p.seq).toList(), [0, 1, 2, 3]);
  });

  test('fusionner avec points intermédiaires comble le trou', () async {
    await deuxTraces();

    await RideMergeService.mergeGaps(
      ride: _ride(), repo: repo, gapSegments: {1},
      interpolate: true, spacingMeters: 50,
    );

    final points = await repo.pointsOf('r1');
    expect(points.length, greaterThan(4));
    expect(points.map((p) => p.segment).toSet(), {0});
    // Numérotation refaite sans trou ni doublon.
    expect(points.map((p) => p.seq).toList(),
        List.generate(points.length, (i) => i));
    // Les points ajoutés se placent entre les deux traces, dans l ordre.
    for (int i = 1; i < points.length; i++) {
      expect(points[i].timestamp.isBefore(points[i - 1].timestamp), isFalse,
          reason: 'horodatage croissant');
      expect(points[i].lat, greaterThanOrEqualTo(points[i - 1].lat));
    }
  });

  test('la fusion recalcule la distance en incluant le trou', () async {
    await deuxTraces();
    final avant = RideStats.fromPoints(await repo.pointsOf('r1'));

    final apres = await RideMergeService.mergeGaps(
      ride: _ride(), repo: repo, gapSegments: {1}, interpolate: false,
    );

    expect(apres.stats.distanceMeters, greaterThan(avant.distanceMeters));
  });

  test('une pause n est pas fusionnée : seuls les trous de signal le sont',
      () async {
    // Segment 1 = perte de signal, segment 2 = pause déjeuner.
    await repo.appendPoints([
      _p(0, 0, 44.0000, 0),
      _p(1, 1, 44.0110, 200),
      _p(2, 2, 44.0120, 4000),
    ]);

    await RideMergeService.mergeGaps(
      ride: _ride(), repo: repo, gapSegments: {1}, interpolate: false,
    );

    final points = await repo.pointsOf('r1');
    expect(points.map((p) => p.segment).toList(), [0, 0, 1],
        reason: 'la pause reste une coupure, le trou de signal disparaît');
  });

  test('sans trou de signal, la sortie est inchangée', () async {
    await deuxTraces();

    await RideMergeService.mergeGaps(
      ride: _ride(), repo: repo, gapSegments: {}, interpolate: false,
    );

    final points = await repo.pointsOf('r1');
    expect(points.map((p) => p.segment).toList(), [0, 0, 1, 1]);
  });
}
