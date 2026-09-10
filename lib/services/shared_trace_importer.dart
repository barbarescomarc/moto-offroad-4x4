import 'package:uuid/uuid.dart';

import '../models/ride.dart';
import '../models/shared_trace.dart';
import 'gpx_service.dart';
import 'ride_repository.dart';

// ── Import d'une trace partagée en sortie locale ─────────────
//
// Le résultat est une copie définitive : masquer ou retirer la trace du
// catalogue ensuite ne touche plus à cette sortie (décision produit — voir
// la fiche de tâche). `sharedTraceId` reste posé pour afficher « téléchargée
// depuis le partage » et interdire de republier la trace d'un autre.
class SharedTraceImporter {
  SharedTraceImporter(this._repo);
  final RideRepository _repo;

  static const _uuid = Uuid();

  /// Crée la sortie et ses points à partir de [gpx], déjà téléchargé pour
  /// la fiche [fiche]. Lève une [FormatException] — avant toute écriture en
  /// base — quand [gpx] ne peut pas être analysé : un rider qui obtiendrait
  /// à la place une sortie vide et sans nom aurait perdu la trace et gagné
  /// un problème à nettoyer.
  Future<Ride> import(SharedTraceDetail fiche, String gpx) async {
    final trace = GpxService().loadFromString(gpx);
    if (trace == null) {
      throw const FormatException('GPX illisible');
    }

    final rideId = _uuid.v4();
    // Repli quand un point GPX ne porte pas d'horodatage : décalé d'une
    // seconde par point pour que RideStats (qui suppose le temps croissant
    // à l'intérieur d'un même segment) reste cohérent.
    final horodatageDepart = fiche.recordedAt ?? fiche.publishedAt;
    final points = <RidePoint>[
      for (var i = 0; i < trace.points.length; i++)
        RidePoint(
          rideId: rideId,
          seq: i,
          segment: 0,
          lat: trace.points[i].position.latitude,
          lng: trace.points[i].position.longitude,
          altitude: trace.points[i].elevation,
          speedKmh: trace.points[i].speed ?? 0,
          timestamp: trace.points[i].time ?? horodatageDepart.add(Duration(seconds: i)),
        ),
    ];

    final ride = Ride(
      id: rideId,
      name: fiche.name,
      startedAt: points.first.timestamp,
      endedAt: points.last.timestamp,
      source: RideSource.imported,
      status: RideStatus.finished,
      stats: RideStats.fromPoints(points),
      sharedTraceId: fiche.id,
    );

    await _repo.insertRide(ride);
    await _repo.appendPoints(points);
    return ride;
  }
}
