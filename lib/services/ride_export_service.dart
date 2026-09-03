import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/ride.dart';
import '../models/trace.dart';
import 'gpx_service.dart';

// ── Export d'une sortie vers GPX ─────────────────────────────
class RideExportService {
  static final RideExportService _instance = RideExportService._();
  factory RideExportService() => _instance;
  RideExportService._();

  final _gpx = GpxService();

  TraceModel toTraceModel(Ride ride, List<RidePoint> points) => TraceModel(
        id:     ride.id,
        name:   ride.name,
        description: ride.notes,
        date:   ride.startedAt,
        source: ride.source.name,
        points: points
            .map((p) => TracePoint(
                  position:  p.position,
                  elevation: p.altitude,
                  time:      p.timestamp,
                  speed:     p.speedKmh,
                ))
            .toList(),
      );

  String toGpx(Ride ride, List<RidePoint> points) =>
      _gpx.exportToGpx(toTraceModel(ride, points));

  // ── Écriture d'un fichier puis menu de partage Android ────
  Future<void> shareGpx(Ride ride, List<RidePoint> points) async {
    final dir = await getTemporaryDirectory();
    final safeName = ride.name.replaceAll(RegExp(r'[^\w\s-]'), '').trim();
    final file = File('${dir.path}/$safeName.gpx');
    await file.writeAsString(toGpx(ride, points));
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: ride.name,
      text:    'Trace ${ride.name}',
    );
  }
}
