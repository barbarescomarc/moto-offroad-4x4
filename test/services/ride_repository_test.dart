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

  test('une sortie telechargee retient l identifiant de la trace partagee', () async {
    await repo.insertRide(Ride(
      id: 'r1', name: 'Boucle du Sidobre', startedAt: DateTime(2026, 9, 1),
      source: RideSource.imported, status: RideStatus.finished,
      stats: RideStats.empty, sharedTraceId: 'abc123',
    ));

    final relue = await repo.findRide('r1');
    expect(relue!.sharedTraceId, 'abc123');
  });

  test('une sortie enregistree n a pas d origine partagee', () async {
    await repo.insertRide(Ride(
      id: 'r2', name: 'Sortie du dimanche', startedAt: DateTime(2026, 9, 1),
      source: RideSource.recorded, status: RideStatus.finished, stats: RideStats.empty,
    ));

    expect((await repo.findRide('r2'))!.sharedTraceId, isNull);
  });

  test('la migration v1 vers v2 ajoute la colonne sans perdre les sorties', () async {
    // Table v1 construite a la main, sans shared_trace_id : contrairement a
    // RideDatabase.onCreate (qui construit deja le schema v2 courant pour
    // une installation neuve), c'est la seule facon de faire vraiment
    // passer l'ALTER TABLE de onUpgrade dans ce test.
    final ancienne = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) => db.execute('''
          CREATE TABLE rides (
            id            TEXT PRIMARY KEY,
            name          TEXT    NOT NULL,
            notes         TEXT,
            started_at    INTEGER NOT NULL,
            ended_at      INTEGER,
            source        TEXT    NOT NULL,
            status        TEXT    NOT NULL,
            distance_m    REAL    NOT NULL DEFAULT 0,
            total_time_s  INTEGER NOT NULL DEFAULT 0,
            moving_time_s INTEGER NOT NULL DEFAULT 0,
            avg_speed_kmh REAL    NOT NULL DEFAULT 0,
            max_speed_kmh REAL    NOT NULL DEFAULT 0
          )
        '''),
      ),
    );
    await ancienne.insert('rides', {
      'id': 'ancienne', 'name': 'Avant migration', 'started_at': 1, 'source': 'recorded',
      'status': 'finished', 'distance_m': 0, 'total_time_s': 0, 'moving_time_s': 0,
      'avg_speed_kmh': 0, 'max_speed_kmh': 0,
    });

    await RideDatabase.onUpgrade(ancienne, 1, 2);

    final columns = await ancienne.rawQuery('PRAGMA table_info(rides)');
    expect(columns.any((c) => c['name'] == 'shared_trace_id'), isTrue);

    final rows = await ancienne.query('rides');
    expect(rows.length, 1);
    expect(rows.first['id'], 'ancienne');
    expect(rows.first['name'], 'Avant migration');
    expect(rows.first['shared_trace_id'], isNull);

    await ancienne.close();
  });

  test('rejouer la migration ne casse rien', () async {
    // Cas onCreate : une base neuve est deja au schema v2 quand onUpgrade
    // est rejoue dessus (ex. reinstallation). Ne doit ni jeter, ni dupliquer
    // la colonne.
    final dejaAJour = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 2, onCreate: RideDatabase.onCreate),
    );

    await RideDatabase.onUpgrade(dejaAJour, 1, 2);
    await RideDatabase.onUpgrade(dejaAJour, 1, 2);

    final columns = await dejaAJour.rawQuery('PRAGMA table_info(rides)');
    expect(columns.where((c) => c['name'] == 'shared_trace_id').length, 1);

    await dejaAJour.close();
  });
}
