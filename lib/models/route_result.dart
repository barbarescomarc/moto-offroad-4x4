import 'package:latlong2/latlong.dart';

enum ManeuverType {
  straight,
  turnLeft,
  turnRight,
  sharpLeft,
  sharpRight,
  uturn,
  arrive,
  depart,
}

class RouteStep {
  final String instruction;
  final double distanceMeters;
  final ManeuverType maneuver;
  final LatLng location;

  const RouteStep({
    required this.instruction,
    required this.distanceMeters,
    required this.maneuver,
    required this.location,
  });
}

// Contrat commun à un itinéraire calculé (OpenRouteService) et à un
// itinéraire dérivé d'une trace GPX : le reste du guidage ne sait pas
// d'où vient la donnée.
class RouteResult {
  final List<LatLng> polyline;
  final List<RouteStep> steps;
  final double totalDistanceMeters;
  final double totalDurationSeconds;

  const RouteResult({
    required this.polyline,
    required this.steps,
    required this.totalDistanceMeters,
    required this.totalDurationSeconds,
  });

  double get totalDistanceKm => totalDistanceMeters / 1000;
  Duration get totalDuration => Duration(seconds: totalDurationSeconds.round());
}
