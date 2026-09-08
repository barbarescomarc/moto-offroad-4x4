// lib/models/roadbook_entry.dart
import 'package:latlong2/latlong.dart';
import 'route_result.dart';

// Une ligne de roadbook — cap et distances façon carnet de rallye, plutôt
// que la phrase parlée d'une instruction de guidage classique.
class RoadbookEntry {
  final int index;
  final double partialDistanceMeters;    // depuis la ligne précédente
  final double cumulativeDistanceMeters; // depuis le départ
  final double capDeg;                   // cap boussole, 0-360°
  final ManeuverType maneuver;
  final LatLng location;
  final String? note;

  const RoadbookEntry({
    required this.index,
    required this.partialDistanceMeters,
    required this.cumulativeDistanceMeters,
    required this.capDeg,
    required this.maneuver,
    required this.location,
    this.note,
  });

  RoadbookEntry copyWith({String? note}) => RoadbookEntry(
    index: index,
    partialDistanceMeters: partialDistanceMeters,
    cumulativeDistanceMeters: cumulativeDistanceMeters,
    capDeg: capDeg,
    maneuver: maneuver,
    location: location,
    note: note ?? this.note,
  );
}
