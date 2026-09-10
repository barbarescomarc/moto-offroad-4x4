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
    final points = <RidePoint>[];
    // Un GPX qui mélange des points horodatés et non horodatés peut, avec le
    // seul repli ci-dessus, produire un horodatage antérieur au point
    // précédent (le décalage utilise l'index global, pas le dernier
    // horodatage réellement posé). RideStats.fromPoints soustrait des
    // horodatages consécutifs sans jamais clamper : un seul pas en arrière
    // suffit à rendre le temps de déplacement négatif et la sortie
    // silencieusement corrompue. La séquence est donc forcée strictement
    // croissante ici, quitte à s'écarter d'une seconde du repli initial.
    DateTime? dernierHorodatage;
    for (var i = 0; i < trace.points.length; i++) {
      final point = trace.points[i];
      var horodatage = point.time ?? horodatageDepart.add(Duration(seconds: i));
      if (dernierHorodatage != null && !horodatage.isAfter(dernierHorodatage)) {
        horodatage = dernierHorodatage.add(const Duration(seconds: 1));
      }
      dernierHorodatage = horodatage;
      points.add(RidePoint(
        rideId: rideId,
        seq: i,
        segment: 0,
        lat: point.position.latitude,
        lng: point.position.longitude,
        altitude: point.elevation,
        speedKmh: point.speed ?? 0,
        timestamp: horodatage,
      ));
    }
    // Trouvaille mineure de la revue finale : GpxService rend aujourd'hui
    // toujours `null` pour un GPX analysé mais sans le moindre point (déjà
    // intercepté par le FormatException plus haut), mais rien ici ne le
    // garantit dans ce fichier — `points.first`/`points.last` ci-dessous
    // lèveraient alors un StateError, pas la FormatException documentée.
    // Cette garde rend le contrat vrai localement, indépendamment de ce que
    // fait GpxService de son côté.
    if (points.isEmpty) {
      throw const FormatException('GPX illisible');
    }

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
