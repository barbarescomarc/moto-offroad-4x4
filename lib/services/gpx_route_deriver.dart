// lib/services/gpx_route_deriver.dart
import 'package:latlong2/latlong.dart';
import '../models/roadbook_entry.dart';
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

  // Le mode alerte n'a pas de manœuvre à annoncer, mais il lui faut malgré
  // tout une étape terminale : c'est elle qui, via la machinerie d'étapes de
  // GuidanceProvider, détecte l'arrivée en bout de trace, annonce
  // « Destination atteinte » et libère le service d'avant-plan. Sans elle le
  // guidage — et son wake lock — tournaient jusqu'à un arrêt manuel.
  static RouteResult deriveForAlert(TraceModel trace) {
    final points = trace.points.map((p) => p.position).toList();
    return RouteResult(
      polyline: points,
      steps: points.isEmpty
          ? const []
          : [
              RouteStep(
                instruction: 'Destination atteinte',
                distanceMeters: 0,
                maneuver: ManeuverType.arrive,
                location: points.last,
              ),
            ],
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

  // Carnet de rallye : cap et distances partielle/cumulée à chaque
  // manœuvre, plutôt que les instructions parlées du guidage classique.
  // Distances recalculées entre lignes RETENUES (pas entre ancres brutes) :
  // deriveTurnByTurn ne porte que la distance depuis l'ancre précédente,
  // pas depuis la dernière manœuvre gardée — insuffisant pour un cumul.
  static List<RoadbookEntry> deriveRoadbook(TraceModel trace) {
    final points = trace.points.map((p) => p.position).toList();
    if (points.length < 2) return const [];

    final anchors = _sampleAnchors(points);
    final entries = <RoadbookEntry>[];
    double cumulative = 0;
    var lastKeptIdx = anchors.first;

    entries.add(RoadbookEntry(
      index: 0,
      partialDistanceMeters: 0,
      cumulativeDistanceMeters: 0,
      capDeg: _normalizedBearing(points, anchors, 0),
      maneuver: ManeuverType.depart,
      location: points[anchors.first],
    ));

    if (anchors.length >= 3) {
      for (var i = 1; i < anchors.length - 1; i++) {
        final prev = points[anchors[i - 1]];
        final curr = points[anchors[i]];
        final next = points[anchors[i + 1]];

        final bearingIn = _calc.bearing(prev, curr);
        final bearingOut = _calc.bearing(curr, next);
        final delta = bearingDeltaDeg(bearingIn, bearingOut);
        if (delta.abs() < turnThresholdDeg) continue;

        final segment = _sumDistance(points, lastKeptIdx, anchors[i]);
        cumulative += segment;
        entries.add(RoadbookEntry(
          index: entries.length,
          partialDistanceMeters: segment,
          cumulativeDistanceMeters: cumulative,
          capDeg: (bearingOut + 360) % 360,
          maneuver: _maneuverFor(delta),
          location: curr,
        ));
        lastKeptIdx = anchors[i];
      }
    }

    final finalSegment = _sumDistance(points, lastKeptIdx, points.length - 1);
    cumulative += finalSegment;
    entries.add(RoadbookEntry(
      index: entries.length,
      partialDistanceMeters: finalSegment,
      cumulativeDistanceMeters: cumulative,
      capDeg: entries.last.capDeg,
      maneuver: ManeuverType.arrive,
      location: points.last,
    ));

    return entries;
  }

  static double _sumDistance(List<LatLng> points, int fromIdx, int toIdx) {
    double total = 0;
    for (var i = fromIdx + 1; i <= toIdx; i++) {
      total += _calc(points[i - 1], points[i]);
    }
    return total;
  }

  static double _normalizedBearing(List<LatLng> points, List<int> anchors, int anchorIdx) {
    if (anchors.length < 2) return 0;
    final from = points[anchors[anchorIdx]];
    final to = points[anchors[anchorIdx + 1]];
    return (_calc.bearing(from, to) + 360) % 360;
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
