import 'package:latlong2/latlong.dart';

// ── Origine d'une sortie ─────────────────────────────────────
enum RideSource { recorded, imported }

// ── État d'une sortie ────────────────────────────────────────
enum RideStatus { recording, finished }

// ── Point enregistré ─────────────────────────────────────────
class RidePoint {
  final String rideId;
  final int seq;
  final int segment;      // incrémenté à chaque reprise après pause
  final double lat;
  final double lng;
  final double? altitude; // mètres, stockée mais non exploitée (lot 1)
  final double speedKmh;
  final DateTime timestamp;

  const RidePoint({
    required this.rideId,
    required this.seq,
    required this.segment,
    required this.lat,
    required this.lng,
    this.altitude,
    required this.speedKmh,
    required this.timestamp,
  });

  LatLng get position => LatLng(lat, lng);
}

// ── Statistiques d'une sortie ────────────────────────────────
class RideStats {
  final double distanceMeters;
  final Duration totalTime;
  final Duration movingTime;
  final double avgSpeedKmh;
  final double maxSpeedKmh;

  const RideStats({
    required this.distanceMeters,
    required this.totalTime,
    required this.movingTime,
    required this.avgSpeedKmh,
    required this.maxSpeedKmh,
  });

  static const empty = RideStats(
    distanceMeters: 0,
    totalTime:      Duration.zero,
    movingTime:     Duration.zero,
    avgSpeedKmh:    0,
    maxSpeedKmh:    0,
  );

  double get distanceKm => distanceMeters / 1000;

  // Distance et temps ne cumulent qu'à l'intérieur d'un même segment :
  // relier deux segments compterait le trajet fait pendant la pause.
  factory RideStats.fromPoints(List<RidePoint> points) {
    if (points.length < 2) return empty;

    const calc = Distance();
    double distance = 0;
    int movingSeconds = 0;
    double maxSpeed = points.first.speedKmh;

    for (int i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final curr = points[i];
      if (curr.speedKmh > maxSpeed) maxSpeed = curr.speedKmh;
      if (curr.segment != prev.segment) continue;
      distance += calc(prev.position, curr.position);
      movingSeconds += curr.timestamp.difference(prev.timestamp).inSeconds;
    }

    final moving = Duration(seconds: movingSeconds);
    final avg = movingSeconds == 0 ? 0.0 : (distance / movingSeconds) * 3.6;

    return RideStats(
      distanceMeters: distance,
      totalTime:      points.last.timestamp.difference(points.first.timestamp),
      movingTime:     moving,
      avgSpeedKmh:    avg,
      maxSpeedKmh:    maxSpeed,
    );
  }
}

// ── Sortie ───────────────────────────────────────────────────
class Ride {
  final String id;
  final String name;
  final String? notes;
  final DateTime startedAt;
  final DateTime? endedAt;
  final RideSource source;
  final RideStatus status;
  final RideStats stats;

  const Ride({
    required this.id,
    required this.name,
    this.notes,
    required this.startedAt,
    this.endedAt,
    required this.source,
    required this.status,
    required this.stats,
  });

  bool get isRecording => status == RideStatus.recording;

  Ride copyWith({
    String? name,
    String? notes,
    DateTime? endedAt,
    RideStatus? status,
    RideStats? stats,
  }) => Ride(
    id:        id,
    name:      name      ?? this.name,
    notes:     notes     ?? this.notes,
    startedAt: startedAt,
    endedAt:   endedAt   ?? this.endedAt,
    source:    source,
    status:    status    ?? this.status,
    stats:     stats     ?? this.stats,
  );
}
