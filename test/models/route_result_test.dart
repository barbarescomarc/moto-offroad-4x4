// test/models/route_result_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:moto_offroad/models/route_result.dart';

void main() {
  test('totalDistanceKm convertit les mètres en kilomètres', () {
    const r = RouteResult(
      polyline: [],
      steps: [],
      totalDistanceMeters: 4200,
      totalDurationSeconds: 600,
    );
    expect(r.totalDistanceKm, closeTo(4.2, 0.001));
  });

  test('totalDuration convertit les secondes en Duration', () {
    const r = RouteResult(
      polyline: [],
      steps: [],
      totalDistanceMeters: 0,
      totalDurationSeconds: 125,
    );
    expect(r.totalDuration, const Duration(seconds: 125));
  });

  test('RouteStep porte instruction, distance, manœuvre et position', () {
    const step = RouteStep(
      instruction: 'Tournez à gauche',
      distanceMeters: 150,
      maneuver: ManeuverType.turnLeft,
      location: LatLng(44.0, 6.0),
    );
    expect(step.instruction, 'Tournez à gauche');
    expect(step.maneuver, ManeuverType.turnLeft);
  });
}
