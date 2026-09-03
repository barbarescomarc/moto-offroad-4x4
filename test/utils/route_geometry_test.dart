// test/utils/route_geometry_test.dart
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:moto_offroad/utils/route_geometry.dart';

void main() {
  group('distanceToPolyline', () {
    test('un point sur le segment est à distance ~0', () {
      final polyline = [const LatLng(44.0, 6.0), const LatLng(44.01, 6.0)];
      final onSegment = const LatLng(44.005, 6.0);
      expect(distanceToPolyline(onSegment, polyline), lessThan(1));
    });

    test('un point décalé perpendiculairement donne la distance attendue', () {
      // Segment nord-sud à longitude 6.0. Un point à +0.001° de longitude
      // au même point milieu est décalé d'environ 111.32 km × cos(lat) × 0.001.
      final polyline = [const LatLng(44.0, 6.0), const LatLng(44.01, 6.0)];
      final offset = const LatLng(44.005, 6.001);
      const latRef = 44.005;
      final expectedMeters = 111320 * cos(latRef * pi / 180) * 0.001;
      expect(distanceToPolyline(offset, polyline), closeTo(expectedMeters, expectedMeters * 0.05));
    });

    test('un point au-delà d\'une extrémité donne la distance au point le plus proche', () {
      final polyline = [const LatLng(44.0, 6.0), const LatLng(44.01, 6.0)];
      final beyondEnd = const LatLng(44.02, 6.0);
      const calc = Distance();
      final expected = calc(beyondEnd, const LatLng(44.01, 6.0));
      expect(distanceToPolyline(beyondEnd, polyline), closeTo(expected, 1));
    });

    test('polyligne vide → distance infinie', () {
      expect(distanceToPolyline(const LatLng(44.0, 6.0), []), double.infinity);
    });
  });

  group('bearingDeltaDeg', () {
    test('aucun changement de cap → delta 0', () {
      expect(bearingDeltaDeg(90, 90), 0);
    });

    test('virage à droite de 45° → delta positif', () {
      expect(bearingDeltaDeg(0, 45), 45);
    });

    test('virage à gauche de 45° → delta négatif', () {
      expect(bearingDeltaDeg(45, 0), -45);
    });

    test('passage par le nord (350° → 10°) reste un petit delta positif', () {
      expect(bearingDeltaDeg(350, 10), 20);
    });
  });
}
