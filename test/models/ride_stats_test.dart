import 'package:flutter_test/flutter_test.dart';
import 'package:moto_offroad/models/ride.dart';

RidePoint _pt(int seq, double lat, double lng, int secondsFromStart,
    {int segment = 0, double speed = 0}) {
  return RidePoint(
    rideId:    'r1',
    seq:       seq,
    segment:   segment,
    lat:       lat,
    lng:       lng,
    altitude:  120,
    speedKmh:  speed,
    timestamp: DateTime(2026, 9, 2, 10, 0, 0).add(Duration(seconds: secondsFromStart)),
  );
}

void main() {
  group('RideStats.fromPoints', () {
    test('liste vide donne des statistiques nulles', () {
      final stats = RideStats.fromPoints([]);
      expect(stats.distanceMeters, 0);
      expect(stats.movingTime, Duration.zero);
      expect(stats.avgSpeedKmh, 0);
    });

    test('un seul point donne des statistiques nulles', () {
      final stats = RideStats.fromPoints([_pt(0, 44.0, 6.0, 0)]);
      expect(stats.distanceMeters, 0);
    });

    test('deux points espacés de 100 m en 10 s', () {
      // 0.000899° de latitude ≈ 100 m
      final stats = RideStats.fromPoints([
        _pt(0, 44.000000, 6.0, 0),
        _pt(1, 44.000899, 6.0, 10),
      ]);
      expect(stats.distanceMeters, closeTo(100, 2));
      expect(stats.totalTime, const Duration(seconds: 10));
      expect(stats.movingTime, const Duration(seconds: 10));
      expect(stats.avgSpeedKmh, closeTo(36, 1));
    });

    test('la distance ignore le saut entre deux segments', () {
      final stats = RideStats.fromPoints([
        _pt(0, 44.000000, 6.0, 0),
        _pt(1, 44.000899, 6.0, 10),
        // reprise 10 km plus loin, segment 1 : le saut ne doit pas compter
        _pt(2, 44.090000, 6.0, 3600, segment: 1),
        _pt(3, 44.090899, 6.0, 3610, segment: 1),
      ]);
      expect(stats.distanceMeters, closeTo(200, 4));
    });

    test('le temps en mouvement exclut la pause entre segments', () {
      final stats = RideStats.fromPoints([
        _pt(0, 44.000000, 6.0, 0),
        _pt(1, 44.000899, 6.0, 10),
        _pt(2, 44.090000, 6.0, 3600, segment: 1),
        _pt(3, 44.090899, 6.0, 3610, segment: 1),
      ]);
      expect(stats.movingTime, const Duration(seconds: 20));
      expect(stats.totalTime, const Duration(seconds: 3610));
    });

    test('la vitesse maximale est celle du point le plus rapide', () {
      final stats = RideStats.fromPoints([
        _pt(0, 44.000000, 6.0, 0, speed: 12),
        _pt(1, 44.000899, 6.0, 10, speed: 87.5),
        _pt(2, 44.001798, 6.0, 20, speed: 40),
      ]);
      expect(stats.maxSpeedKmh, 87.5);
    });
  });
}
