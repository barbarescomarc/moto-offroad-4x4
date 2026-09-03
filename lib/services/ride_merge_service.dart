import 'package:latlong2/latlong.dart';
import '../models/ride.dart';
import 'ride_repository.dart';

// ── Fusion des traces coupées par une perte de signal ────────
// Une sortie peut contenir plusieurs tronçons : ceux ouverts par une pause,
// et ceux ouverts par une perte de signal (forêt, tunnel, gorge). Seuls les
// seconds sont fusionnables : une pause est une coupure voulue, qu'il ne faut
// pas effacer.
class RideMergeService {
  static const _calc = Distance();

  /// Réunit les tronçons séparés par [gapSegments] en une trace continue.
  ///
  /// [interpolate] insère des points le long de la ligne droite qui comble le
  /// trou, espacés d'environ [spacingMeters]. Sans lui, les deux tronçons sont
  /// simplement reliés par un trait.
  ///
  /// Renvoie la sortie avec ses statistiques recalculées — la distance
  /// augmente, puisque les kilomètres parcourus sans signal comptent désormais.
  static Future<Ride> mergeGaps({
    required Ride ride,
    required RideRepository repo,
    required Set<int> gapSegments,
    required bool interpolate,
    double spacingMeters = 50,
  }) async {
    if (gapSegments.isEmpty) return ride;

    final points = await repo.pointsOf(ride.id);
    if (points.isEmpty) return ride;

    final merged = <RidePoint>[];
    for (int i = 0; i < points.length; i++) {
      final p = points[i];

      // Premier point d'un tronçon ouvert par une perte de signal : on comble.
      final ouvreUnTrou = i > 0 &&
          gapSegments.contains(p.segment) &&
          p.segment != points[i - 1].segment;
      if (ouvreUnTrou && interpolate) {
        merged.addAll(_bridge(points[i - 1], p, spacingMeters, ride.id));
      }

      merged.add(p);
    }

    // Renumérotation : les segments de trou disparaissent, les segments de
    // pause qui suivent se décalent, et la séquence est refaite d'un bloc.
    final renumbered = <RidePoint>[];
    for (int i = 0; i < merged.length; i++) {
      final p = merged[i];
      renumbered.add(_copy(p, seq: i, segment: _remap(p.segment, gapSegments)));
    }

    await repo.replacePoints(ride.id, renumbered);

    final updated = ride.copyWith(stats: RideStats.fromPoints(renumbered));
    await repo.updateRide(updated);
    return updated;
  }

  // Un segment de trou est absorbé par celui qui le précède ; tout segment
  // situé après recule d'autant de rangs qu'il y a de trous avant lui.
  static int _remap(int segment, Set<int> gaps) =>
      segment - gaps.where((g) => g <= segment).length;

  // Points synthétiques répartis en ligne droite entre les deux bords du trou,
  // horodatage et altitude interpolés linéairement.
  static List<RidePoint> _bridge(
      RidePoint from, RidePoint to, double spacing, String rideId) {
    final meters = _calc(from.position, to.position);
    final count = (meters / spacing).floor() - 1;
    if (count < 1) return const [];

    final seconds = to.timestamp.difference(from.timestamp).inSeconds;
    final speed = seconds == 0 ? 0.0 : (meters / seconds) * 3.6;

    return List.generate(count, (i) {
      final t = (i + 1) / (count + 1);
      return RidePoint(
        rideId:    rideId,
        seq:       0, // renumérotée juste après
        segment:   to.segment,
        lat:       from.lat + (to.lat - from.lat) * t,
        lng:       from.lng + (to.lng - from.lng) * t,
        altitude:  from.altitude == null || to.altitude == null
            ? null
            : from.altitude! + (to.altitude! - from.altitude!) * t,
        speedKmh:  speed,
        timestamp: from.timestamp
            .add(Duration(milliseconds: (seconds * 1000 * t).round())),
      );
    });
  }

  static RidePoint _copy(RidePoint p, {required int seq, required int segment}) =>
      RidePoint(
        rideId:    p.rideId,
        seq:       seq,
        segment:   segment,
        lat:       p.lat,
        lng:       p.lng,
        altitude:  p.altitude,
        speedKmh:  p.speedKmh,
        timestamp: p.timestamp,
      );
}
