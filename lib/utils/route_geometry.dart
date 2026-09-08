// lib/utils/route_geometry.dart
import 'dart:math';
import 'package:latlong2/latlong.dart';

class NearestPointResult {
  final LatLng point;
  final double distanceMeters;
  // Index i tel que le point le plus proche se trouve sur le segment [i, i+1].
  final int segmentIndex;

  const NearestPointResult({
    required this.point,
    required this.distanceMeters,
    required this.segmentIndex,
  });
}

const _metersPerDegLat = 111320.0;
double _metersPerDegLon(double latDeg) => 111320.0 * cos(latDeg * pi / 180);

// Projette [position] sur le segment [a, b] en mètres locaux (approximation
// équirectangulaire, suffisante à l'échelle d'un guidage routier/offroad).
LatLng _projectOnSegment(LatLng position, LatLng a, LatLng b) {
  final latRef = (a.latitude + b.latitude) / 2;
  final mLon = _metersPerDegLon(latRef);

  final bx = (b.longitude - a.longitude) * mLon;
  final by = (b.latitude - a.latitude) * _metersPerDegLat;
  final px = (position.longitude - a.longitude) * mLon;
  final py = (position.latitude - a.latitude) * _metersPerDegLat;

  final abLen2 = bx * bx + by * by;
  var t = abLen2 == 0 ? 0.0 : ((px * bx + py * by) / abLen2);
  t = t.clamp(0.0, 1.0);

  return LatLng(
    a.latitude + (t * by) / _metersPerDegLat,
    a.longitude + (t * bx) / mLon,
  );
}

// Parcourt les segments [fromSegment, toSegment] (bornes incluses) et retient
// la projection la plus proche de [position].
NearestPointResult _nearestInRange(
  LatLng position,
  List<LatLng> polyline,
  int fromSegment,
  int toSegment,
) {
  const calc = Distance();
  NearestPointResult? best;

  for (var i = fromSegment; i <= toSegment; i++) {
    final projected = _projectOnSegment(position, polyline[i], polyline[i + 1]);
    final d = calc(position, projected);
    if (best == null || d < best.distanceMeters) {
      best = NearestPointResult(point: projected, distanceMeters: d, segmentIndex: i);
    }
  }
  return best!;
}

NearestPointResult _degenerate(LatLng position, List<LatLng> polyline) {
  if (polyline.isEmpty) {
    return NearestPointResult(point: position, distanceMeters: double.infinity, segmentIndex: -1);
  }
  const calc = Distance();
  return NearestPointResult(
    point: polyline.first,
    distanceMeters: calc(position, polyline.first),
    segmentIndex: 0,
  );
}

// Projette [position] sur chaque segment de [polyline] et retient la
// projection la plus proche.
NearestPointResult nearestPointOnPolyline(LatLng position, List<LatLng> polyline) {
  if (polyline.length < 2) return _degenerate(position, polyline);
  return _nearestInRange(position, polyline, 0, polyline.length - 2);
}

// Variante fenêtrée : ne compare que les segments voisins de
// [centerSegmentIndex]. Sur une trace qui boucle ou fait un aller-retour, le
// balayage complet peut coller le rider à un segment physiquement proche mais
// très éloigné dans l'ordre du parcours — une vraie déviation près du brin
// retour passait alors pour un « sur la trace ». Restreindre la recherche au
// voisinage du dernier segment reconnu supprime cette confusion, et évite au
// passage un balayage O(n) à chaque relevé GPS.
NearestPointResult nearestPointOnPolylineWindowed(
  LatLng position,
  List<LatLng> polyline,
  int centerSegmentIndex, {
  int window = 5,
}) {
  if (polyline.length < 2) return _degenerate(position, polyline);
  final lastSegment = polyline.length - 2;
  final center = centerSegmentIndex.clamp(0, lastSegment);
  final from = max(0, center - window);
  final to = min(lastSegment, center + window);
  return _nearestInRange(position, polyline, from, to);
}

double distanceToPolyline(LatLng position, List<LatLng> polyline) =>
    nearestPointOnPolyline(position, polyline).distanceMeters;

// Distance le long de [polyline] entre deux projections déjà calculées, dans
// le sens de la progression (de [from] vers [to]). Renvoie null si [to] n'est
// pas en avant de [from] — segment antérieur, ou même segment mais plus près
// du départ de ce segment — utile pour ignorer tout point déjà dépassé
// (ex. un radar derrière le rider).
double? distanceAheadAlongPolyline(
  List<LatLng> polyline, {
  required NearestPointResult from,
  required NearestPointResult to,
}) {
  const calc = Distance();
  if (to.segmentIndex < from.segmentIndex) return null;

  if (to.segmentIndex == from.segmentIndex) {
    final segmentEnd = polyline[from.segmentIndex + 1];
    // Sur le même segment, [to] doit être plus proche de la fin de segment
    // que [from] pour être réellement devant — sinon il est derrière.
    if (calc(to.point, segmentEnd) > calc(from.point, segmentEnd)) return null;
    return calc(from.point, to.point);
  }

  double total = calc(from.point, polyline[from.segmentIndex + 1]);
  for (var i = from.segmentIndex + 1; i < to.segmentIndex; i++) {
    total += calc(polyline[i], polyline[i + 1]);
  }
  total += calc(polyline[to.segmentIndex], to.point);
  return total;
}

// Delta de cap signé, normalisé dans [-180, 180]. Positif = vers la droite.
double bearingDeltaDeg(double fromDeg, double toDeg) {
  var delta = (toDeg - fromDeg) % 360;
  if (delta > 180) delta -= 360;
  if (delta < -180) delta += 360;
  return delta;
}

// Degrés de virage cumulés par kilomètre — proxy de sinuosité d'un
// itinéraire déjà calculé (géométrie de route propre, pas une trace GPS
// brute). Une ligne droite vaut 0 ; plus les virages sont fréquents et
// serrés, plus la valeur monte. Sert à choisir, parmi plusieurs itinéraires
// alternatifs vers une même destination, celui qui tourne le plus (à
// défaut d'un véritable algorithme de recherche de routes sinueuses,
// absent d'ORS).
double routeSinuosityDegPerKm(List<LatLng> polyline) {
  if (polyline.length < 3) return 0;
  const calc = Distance();

  double totalTurningDeg = 0;
  double totalDistanceMeters = 0;
  double previousBearing = calc.bearing(polyline[0], polyline[1]);

  for (var i = 1; i < polyline.length - 1; i++) {
    totalDistanceMeters += calc(polyline[i - 1], polyline[i]);
    final bearing = calc.bearing(polyline[i], polyline[i + 1]);
    totalTurningDeg += bearingDeltaDeg(previousBearing, bearing).abs();
    previousBearing = bearing;
  }
  totalDistanceMeters += calc(polyline[polyline.length - 2], polyline.last);

  if (totalDistanceMeters == 0) return 0;
  return totalTurningDeg / (totalDistanceMeters / 1000);
}
