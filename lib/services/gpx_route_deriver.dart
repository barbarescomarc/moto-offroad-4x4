// lib/services/gpx_route_deriver.dart
import 'package:latlong2/latlong.dart';
import '../models/route_result.dart';
import '../models/trace.dart';
import '../utils/route_geometry.dart';

// Transforme une trace GPX déjà importée en RouteResult, sans appel réseau —
// utilisé par les deux modes de guidage sur trace GPX (alerte de déviation
// et virage par virage).
class GpxRouteDeriver {
  // Changement de cap (°) au-delà duquel un point est considéré comme un virage.
  static const double turnThresholdDeg = 25;
  // Changement de cap (°) au-delà duquel le virage est qualifié de serré.
  static const double sharpTurnThresholdDeg = 70;
  // Distance minimale (m) entre deux points comparés — lisse le bruit GPS
  // des traces enregistrées à haute fréquence.
  static const double minSegmentMeters = 15;

  static const _calc = Distance();

  static RouteResult deriveForAlert(TraceModel trace) {
    final points = trace.points.map((p) => p.position).toList();
    return RouteResult(
      polyline: points,
      steps: const [],
      totalDistanceMeters: trace.distanceMeters,
      totalDurationSeconds: 0,
    );
  }

  static RouteResult deriveTurnByTurn(TraceModel trace) {
    final points = trace.points.map((p) => p.position).toList();
    if (points.length < 3) {
      return RouteResult(
        polyline: points,
        steps: const [],
        totalDistanceMeters: trace.distanceMeters,
        totalDurationSeconds: 0,
      );
    }

    final anchors = _sampleAnchors(points);
    final steps = <RouteStep>[];

    if (anchors.length >= 3) {
      for (var i = 1; i < anchors.length - 1; i++) {
        final prev = points[anchors[i - 1]];
        final curr = points[anchors[i]];
        final next = points[anchors[i + 1]];

        final bearingIn = _calc.bearing(prev, curr);
        final bearingOut = _calc.bearing(curr, next);
        final delta = bearingDeltaDeg(bearingIn, bearingOut);

        if (delta.abs() < turnThresholdDeg) continue;

        final maneuver = _maneuverFor(delta);
        steps.add(RouteStep(
          instruction: _instructionFor(maneuver),
          distanceMeters: _calc(points[anchors[i - 1]], curr),
          maneuver: maneuver,
          location: curr,
        ));
      }
    }

    steps.add(RouteStep(
      instruction: 'Destination atteinte',
      distanceMeters: _calc(points[anchors.last], points.last),
      maneuver: ManeuverType.arrive,
      location: points.last,
    ));

    return RouteResult(
      polyline: points,
      steps: steps,
      totalDistanceMeters: trace.distanceMeters,
      totalDurationSeconds: 0,
    );
  }

  static List<int> _sampleAnchors(List<LatLng> points) {
    final anchors = <int>[0];
    var lastIdx = 0;
    for (var i = 1; i < points.length; i++) {
      if (_calc(points[lastIdx], points[i]) >= minSegmentMeters) {
        anchors.add(i);
        lastIdx = i;
      }
    }
    if (anchors.last != points.length - 1) anchors.add(points.length - 1);
    return anchors;
  }

  static ManeuverType _maneuverFor(double deltaDeg) {
    final abs = deltaDeg.abs();
    if (abs >= 150) return ManeuverType.uturn;
    if (deltaDeg > 0) {
      return abs >= sharpTurnThresholdDeg ? ManeuverType.sharpRight : ManeuverType.turnRight;
    }
    return abs >= sharpTurnThresholdDeg ? ManeuverType.sharpLeft : ManeuverType.turnLeft;
  }

  static String _instructionFor(ManeuverType m) {
    switch (m) {
      case ManeuverType.turnLeft:   return 'Tournez à gauche';
      case ManeuverType.turnRight:  return 'Tournez à droite';
      case ManeuverType.sharpLeft:  return 'Virage serré à gauche';
      case ManeuverType.sharpRight: return 'Virage serré à droite';
      case ManeuverType.uturn:      return 'Faites demi-tour';
      case ManeuverType.arrive:     return 'Destination atteinte';
      case ManeuverType.depart:     return 'Départ';
      case ManeuverType.straight:   return 'Continuez tout droit';
    }
  }
}
