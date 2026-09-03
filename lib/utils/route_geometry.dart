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

// Projette [position] sur chaque segment de [polyline] en mètres locaux
// (approximation équirectangulaire, suffisante à l'échelle d'un guidage
// routier/offroad) et retient la projection la plus proche.
NearestPointResult nearestPointOnPolyline(LatLng position, List<LatLng> polyline) {
  if (polyline.isEmpty) {
    return NearestPointResult(point: position, distanceMeters: double.infinity, segmentIndex: -1);
  }
  if (polyline.length == 1) {
    const calc = Distance();
    return NearestPointResult(
      point: polyline.first,
      distanceMeters: calc(position, polyline.first),
      segmentIndex: 0,
    );
  }

  const calc = Distance();
  NearestPointResult? best;

  for (var i = 0; i < polyline.length - 1; i++) {
    final a = polyline[i];
    final b = polyline[i + 1];
    final latRef = (a.latitude + b.latitude) / 2;
    final mLon = _metersPerDegLon(latRef);

    final bx = (b.longitude - a.longitude) * mLon;
    final by = (b.latitude - a.latitude) * _metersPerDegLat;
    final px = (position.longitude - a.longitude) * mLon;
    final py = (position.latitude - a.latitude) * _metersPerDegLat;

    final abLen2 = bx * bx + by * by;
    var t = abLen2 == 0 ? 0.0 : ((px * bx + py * by) / abLen2);
    t = t.clamp(0.0, 1.0);

    final projX = t * bx;
    final projY = t * by;
    final projected = LatLng(
      a.latitude + projY / _metersPerDegLat,
      a.longitude + projX / mLon,
    );

    final d = calc(position, projected);
    if (best == null || d < best.distanceMeters) {
      best = NearestPointResult(point: projected, distanceMeters: d, segmentIndex: i);
    }
  }
  return best!;
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
