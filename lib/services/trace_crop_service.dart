import 'package:latlong2/latlong.dart';
import '../models/ride.dart';
import '../models/trace.dart';
import 'gpx_service.dart';

// Une sortie enregistrée commence presque toujours devant chez son auteur.
// Le recadrage produit une copie publiée amputée de ce début, sans jamais
// toucher à la sortie d'origine, qui reste entière dans les Sorties.
class TraceCropService {
  static const _distance = Distance();

  static List<RidePoint> _intervalle(List<RidePoint> points, int startIndex, int endIndex) {
    if (startIndex < 0 || endIndex >= points.length || endIndex <= startIndex) {
      throw ArgumentError('bornes de recadrage invalides: $startIndex..$endIndex sur ${points.length} points');
    }
    return points.sublist(startIndex, endIndex + 1);
  }

  static String cropToGpx(
    Ride ride,
    List<RidePoint> points, {
    required int startIndex,
    required int endIndex,
    required String name,
    String? description,
  }) {
    final retenus = _intervalle(points, startIndex, endIndex);
    final trace = TraceModel(
      id: ride.id,
      name: name,
      description: description,
      date: retenus.first.timestamp,
      source: ride.source.name,
      points: retenus
          .map((p) => TracePoint(
                position: p.position,
                elevation: p.altitude,
                time: p.timestamp,
                speed: p.speedKmh,
              ))
          .toList(),
    );
    return GpxService().exportToGpx(trace);
  }

  static double distanceOf(List<RidePoint> points, int startIndex, int endIndex) {
    final retenus = _intervalle(points, startIndex, endIndex);
    double total = 0;
    for (int i = 1; i < retenus.length; i++) {
      total += _distance(retenus[i - 1].position, retenus[i].position);
    }
    return total;
  }
}
