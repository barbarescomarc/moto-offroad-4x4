import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:moto_offroad/models/ride.dart';
import 'package:moto_offroad/services/ride_database.dart';
import 'package:moto_offroad/services/ride_repository.dart';

Ride _ride(String id, {RideStatus status = RideStatus.finished, int day = 2}) => Ride(
  id:        id,
  name:      'Sortie $id',
  startedAt: DateTime(2026, 9, day, 10, 0),
  endedAt:   status == RideStatus.finished ? DateTime(2026, 9, day, 14, 0) : null,
  source:    RideSource.recorded,
  status:    status,
  stats:     RideStats.empty,
);

RidePoint _pt(String rideId, int seq, {int segment = 0}) => RidePoint(
  rideId:    rideId,
  seq:       seq,
  segment:   segment,
  lat:       44.0 + seq * 0.001,
  lng:       6.0,
  altitude:  300,
  speedKmh:  42,
  timestamp: DateTime(2026, 9, 2, 10, 0).add(Duration(seconds: seq)),
);

void main() {
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
  });

  tearDown(() async => db.close());

  test('une sortie insérée se relit à l identique', () async {
    await repo.insertRide(_ride('r1'));
    final found = await repo.findRide('r1');
    expect(found, isNotNull);
    expect(found!.name, 'Sortie r1');
    expect(found.source, RideSource.recorded);
    expect(found.status, RideStatus.finished);
  });

  test('les points se relisent dans l ordre de leur rang', () async {
    await repo.insertRide(_ride('r1'));
    await repo.appendPoints([_pt('r1', 2), _pt('r1', 0), _pt('r1', 1)]);
    final points = await repo.pointsOf('r1');
    expect(points.map((p) => p.seq).toList(), [0, 1, 2]);
    expect(points.first.altitude, 300);
  });

  test('les sorties sont listées de la plus récente à la plus ancienne', () async {
    await repo.insertRide(_ride('vieille', day: 1));
    await repo.insertRide(_ride('recente', day: 5));
    final rides = await repo.listRides();
    expect(rides.map((r) => r.id).toList(), ['recente', 'vieille']);
  });

  test('une sortie restée en cours est retrouvée', () async {
    await repo.insertRide(_ride('finie'));
    await repo.insertRide(_ride('en_cours', status: RideStatus.recording));
    final open = await repo.findUnfinishedRide();
    expect(open?.id, 'en_cours');
  });

  test('sans sortie en cours, la recherche ne renvoie rien', () async {
    await repo.insertRide(_ride('finie'));
    expect(await repo.findUnfinishedRide(), isNull);
  });

  test('la mise à jour enregistre les statistiques et l état', () async {
    await repo.insertRide(_ride('r1', status: RideStatus.recording));
    final updated = (await repo.findRide('r1'))!.copyWith(
      status: RideStatus.finished,
      stats: const RideStats(
        distanceMeters: 42000,
        totalTime:      Duration(hours: 2),
        movingTime:     Duration(minutes: 95),
        avgSpeedKmh:    26.5,
        maxSpeedKmh:    88,
      ),
    );
    await repo.updateRide(updated);
    final found = await repo.findRide('r1');
    expect(found!.status, RideStatus.finished);
    expect(found.stats.distanceMeters, 42000);
    expect(found.stats.maxSpeedKmh, 88);
    expect(found.stats.movingTime, const Duration(minutes: 95));
  });

  test('supprimer une sortie supprime aussi ses points', () async {
    await repo.insertRide(_ride('r1'));
    await repo.appendPoints([_pt('r1', 0), _pt('r1', 1)]);
    await repo.deleteRide('r1');
    expect(await repo.findRide('r1'), isNull);
    expect(await repo.pointsOf('r1'), isEmpty);
  });
}
