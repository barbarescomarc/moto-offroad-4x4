// test/services/gpx_route_deriver_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:moto_offroad/models/route_result.dart';
import 'package:moto_offroad/models/trace.dart';
import 'package:moto_offroad/services/gpx_route_deriver.dart';

TraceModel _traceFrom(List<LatLng> points) => TraceModel(
      id: 't1',
      name: 'test',
      points: points.map((p) => TracePoint(position: p)).toList(),
    );

void main() {
  group('deriveForAlert', () {
    test('reprend la polyligne telle quelle', () {
      final trace = _traceFrom([const LatLng(44.0, 6.0), const LatLng(44.01, 6.0)]);
      final result = GpxRouteDeriver.deriveForAlert(trace);
      expect(result.polyline.length, 2);
    });

    test('pose une étape d\'arrivée en bout de trace', () {
      // Sans cette étape, GuidanceProvider n'a rien à quoi comparer la
      // position : le guidage ne s'arrêterait jamais tout seul.
      final trace = _traceFrom([const LatLng(44.0, 6.0), const LatLng(44.01, 6.0)]);
      final result = GpxRouteDeriver.deriveForAlert(trace);
      expect(result.steps.length, 1);
      expect(result.steps.single.maneuver, ManeuverType.arrive);
      expect(result.steps.single.location, const LatLng(44.01, 6.0));
    });

    test('une trace vide ne génère aucune étape', () {
      final result = GpxRouteDeriver.deriveForAlert(_traceFrom([]));
      expect(result.steps, isEmpty);
    });
  });

  group('deriveTurnByTurn', () {
    test('une ligne droite ne génère aucun virage', () {
      // 5 points alignés, espacés de ~1.1 km chacun (0.01° de latitude).
      final trace = _traceFrom([
        const LatLng(44.00, 6.0),
        const LatLng(44.01, 6.0),
        const LatLng(44.02, 6.0),
        const LatLng(44.03, 6.0),
        const LatLng(44.04, 6.0),
      ]);
      final result = GpxRouteDeriver.deriveTurnByTurn(trace);
      // Seule l'étape d'arrivée est attendue.
      expect(result.steps.length, 1);
      expect(result.steps.single.maneuver, ManeuverType.arrive);
    });

    test('un tracé en L génère un virage classé à droite', () {
      // Direction plein nord puis plein est : virage à droite.
      final trace = _traceFrom([
        const LatLng(44.00, 6.00),
        const LatLng(44.01, 6.00),
        const LatLng(44.02, 6.00),
        const LatLng(44.02, 6.01),
        const LatLng(44.02, 6.02),
      ]);
      final result = GpxRouteDeriver.deriveTurnByTurn(trace);
      final turns = result.steps.where((s) => s.maneuver != ManeuverType.arrive);
      expect(turns.length, 1);
      expect(
        turns.single.maneuver,
        anyOf(ManeuverType.turnRight, ManeuverType.sharpRight),
      );
    });

    test('un tracé en L inversé génère un virage classé à gauche', () {
      final trace = _traceFrom([
        const LatLng(44.00, 6.00),
        const LatLng(44.01, 6.00),
        const LatLng(44.02, 6.00),
        const LatLng(44.02, 5.99),
        const LatLng(44.02, 5.98),
      ]);
      final result = GpxRouteDeriver.deriveTurnByTurn(trace);
      final turns = result.steps.where((s) => s.maneuver != ManeuverType.arrive);
      expect(turns.length, 1);
      expect(
        turns.single.maneuver,
        anyOf(ManeuverType.turnLeft, ManeuverType.sharpLeft),
      );
    });

    test('des points rapprochés (bruit GPS) ne créent pas de faux virage', () {
      // Ligne droite mais avec des points tous les 2-3 mètres environ
      // (0.00002°) — bien en dessous du seuil d'échantillonnage.
      final trace = _traceFrom(List.generate(
        200,
        (i) => LatLng(44.0 + i * 0.00002, 6.0 + (i.isEven ? 0.0000005 : -0.0000005)),
      ));
      final result = GpxRouteDeriver.deriveTurnByTurn(trace);
      final turns = result.steps.where((s) => s.maneuver != ManeuverType.arrive);
      expect(turns, isEmpty);
    });

    test('une trace de moins de 3 points ne génère aucun virage', () {
      final trace = _traceFrom([const LatLng(44.0, 6.0), const LatLng(44.01, 6.0)]);
      final result = GpxRouteDeriver.deriveTurnByTurn(trace);
      expect(result.steps, isEmpty);
    });
  });
}
