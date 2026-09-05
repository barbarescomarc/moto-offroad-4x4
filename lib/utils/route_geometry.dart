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

// Delta de cap signé, normalisé dans [-180, 180]. Positif = vers la droite.
double bearingDeltaDeg(double fromDeg, double toDeg) {
  var delta = (toDeg - fromDeg) % 360;
  if (delta > 180) delta -= 360;
  if (delta < -180) delta += 360;
  return delta;
}
