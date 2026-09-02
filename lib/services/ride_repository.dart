import 'package:sqflite/sqflite.dart';
import '../models/ride.dart';

// ── Dépôt — seule pièce qui lit et écrit les sorties ─────────
class RideRepository {
  RideRepository(this._db);
  final Database _db;

  // ── Sorties ──────────────────────────────────────────────
  Future<void> insertRide(Ride ride) =>
      _db.insert('rides', _toRow(ride),
          conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> updateRide(Ride ride) =>
      _db.update('rides', _toRow(ride), where: 'id = ?', whereArgs: [ride.id]);

  Future<void> deleteRide(String id) async {
    await _db.transaction((txn) async {
      await txn.delete('ride_points', where: 'ride_id = ?', whereArgs: [id]);
      await txn.delete('rides', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<Ride?> findRide(String id) async {
    final rows = await _db.query('rides', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : _toRide(rows.first);
  }

  Future<List<Ride>> listRides() async {
    final rows = await _db.query('rides', orderBy: 'started_at DESC');
    return rows.map(_toRide).toList();
  }

  Future<Ride?> findUnfinishedRide() async {
    final rows = await _db.query(
      'rides',
      where:    'status = ?',
      whereArgs: [RideStatus.recording.name],
      orderBy:  'started_at DESC',
      limit:    1,
    );
    return rows.isEmpty ? null : _toRide(rows.first);
  }

  // ── Points ───────────────────────────────────────────────
  Future<void> appendPoints(List<RidePoint> points) async {
    if (points.isEmpty) return;
    final batch = _db.batch();
    for (final p in points) {
      batch.insert('ride_points', _toPointRow(p));
    }
    await batch.commit(noResult: true);
  }

  Future<List<RidePoint>> pointsOf(String rideId) async {
    final rows = await _db.query(
      'ride_points',
      where:    'ride_id = ?',
      whereArgs: [rideId],
      orderBy:  'seq ASC',
    );
    return rows.map(_toPoint).toList();
  }

  // ── Conversions ──────────────────────────────────────────
  Map<String, Object?> _toRow(Ride r) => {
    'id':            r.id,
    'name':          r.name,
    'notes':         r.notes,
    'started_at':    r.startedAt.millisecondsSinceEpoch,
    'ended_at':      r.endedAt?.millisecondsSinceEpoch,
    'source':        r.source.name,
    'status':        r.status.name,
    'distance_m':    r.stats.distanceMeters,
    'total_time_s':  r.stats.totalTime.inSeconds,
    'moving_time_s': r.stats.movingTime.inSeconds,
    'avg_speed_kmh': r.stats.avgSpeedKmh,
    'max_speed_kmh': r.stats.maxSpeedKmh,
  };

  Ride _toRide(Map<String, Object?> row) => Ride(
    id:        row['id'] as String,
    name:      row['name'] as String,
    notes:     row['notes'] as String?,
    startedAt: DateTime.fromMillisecondsSinceEpoch(row['started_at'] as int),
    endedAt:   row['ended_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(row['ended_at'] as int),
    source:    RideSource.values.byName(row['source'] as String),
    status:    RideStatus.values.byName(row['status'] as String),
    stats:     RideStats(
      distanceMeters: (row['distance_m'] as num).toDouble(),
      totalTime:      Duration(seconds: row['total_time_s'] as int),
      movingTime:     Duration(seconds: row['moving_time_s'] as int),
      avgSpeedKmh:    (row['avg_speed_kmh'] as num).toDouble(),
      maxSpeedKmh:    (row['max_speed_kmh'] as num).toDouble(),
    ),
  );

  Map<String, Object?> _toPointRow(RidePoint p) => {
    'ride_id':   p.rideId,
    'seq':       p.seq,
    'segment':   p.segment,
    'lat':       p.lat,
    'lng':       p.lng,
    'altitude':  p.altitude,
    'speed_kmh': p.speedKmh,
    'timestamp': p.timestamp.millisecondsSinceEpoch,
  };

  RidePoint _toPoint(Map<String, Object?> row) => RidePoint(
    rideId:    row['ride_id'] as String,
    seq:       row['seq'] as int,
    segment:   row['segment'] as int,
    lat:       (row['lat'] as num).toDouble(),
    lng:       (row['lng'] as num).toDouble(),
    altitude:  (row['altitude'] as num?)?.toDouble(),
    speedKmh:  (row['speed_kmh'] as num).toDouble(),
    timestamp: DateTime.fromMillisecondsSinceEpoch(row['timestamp'] as int),
  );
}
