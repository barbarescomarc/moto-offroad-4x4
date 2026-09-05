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

  group('nearestPointOnPolylineWindowed', () {
    // Trace en aller-retour, typique de l'offroad : on monte le long de la
    // longitude 6.0 (segments 0 à 9), on bascule à l'est (segment 10) puis on
    // redescend un brin parallèle 80 m plus loin (segments 11 à 20). Les deux
    // brins sont voisins dans l'espace, opposés dans la séquence.
    List<LatLng> outAndBackTrace() => [
          for (var i = 0; i <= 10; i++) LatLng(44.0 + i * 0.001, 6.0),
          for (var i = 10; i >= 0; i--) LatLng(44.0 + i * 0.001, 6.001),
        ];

    test('trouve le point le plus proche dans la fenêtre', () {
      final polyline = [
        const LatLng(44.0, 6.0),
        const LatLng(44.01, 6.0),
        const LatLng(44.02, 6.0),
      ];
      final result =
          nearestPointOnPolylineWindowed(const LatLng(44.015, 6.0), polyline, 1);
      expect(result.segmentIndex, 1);
      expect(result.distanceMeters, lessThan(1));
    });

    test('une déviation vers un brin hors fenêtre reste une déviation', () {
      final polyline = outAndBackTrace();
      // Le rider redescend le brin retour (segment 18) puis s'écarte à
      // l'ouest, ce qui le pose pile sur le brin aller.
      const deviation = LatLng(44.0015, 6.0);

      // Le balayage complet le déclare « sur la trace » : il a trouvé le brin
      // aller, très loin dans la séquence. C'est le bug que la fenêtre corrige.
      expect(nearestPointOnPolyline(deviation, polyline).distanceMeters, lessThan(1));

      final windowed = nearestPointOnPolylineWindowed(deviation, polyline, 18);
      expect(windowed.segmentIndex, greaterThanOrEqualTo(11));
      expect(windowed.distanceMeters, greaterThan(60)); // au-delà du seuil offroad
    });

    test('reste sur le brin suivi quand le rider y est réellement', () {
      final polyline = outAndBackTrace();
      const onReturnLeg = LatLng(44.002, 6.001);
      final windowed = nearestPointOnPolylineWindowed(onReturnLeg, polyline, 18);
      expect(windowed.segmentIndex, greaterThanOrEqualTo(11));
      expect(windowed.distanceMeters, lessThan(1));
    });

    test('un index hors bornes est ramené dans la polyligne', () {
      final polyline = [const LatLng(44.0, 6.0), const LatLng(44.01, 6.0)];
      final result =
          nearestPointOnPolylineWindowed(const LatLng(44.005, 6.0), polyline, 99);
      expect(result.segmentIndex, 0);
      expect(result.distanceMeters, lessThan(1));
    });

    test('polyligne vide → distance infinie', () {
      final result = nearestPointOnPolylineWindowed(const LatLng(44.0, 6.0), [], 0);
      expect(result.distanceMeters, double.infinity);
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
