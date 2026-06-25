import 'dart:io';
import 'package:gpx/gpx.dart' as gpx_lib;
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../models/trace.dart';

// ── Parser GPX ───────────────────────────────────────────────
class GpxService {
  static final GpxService _instance = GpxService._();
  factory GpxService() => _instance;
  GpxService._();

  final _uuid = const Uuid();

  // ── Charger depuis un fichier local ─────────────────────
  Future<TraceModel?> loadFromFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;
      final content = await file.readAsString();
      return _parseGpxString(content, source: 'gpx_file');
    } catch (e) {
      return null;
    }
  }

  // ── Charger depuis une URL (Wikiloc, TET, Imarod…) ──────
  Future<TraceModel?> loadFromUrl(String url) async {
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'MotoOffroad/1.0'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return null;
      return _parseGpxString(response.body, source: _detectSource(url));
    } catch (e) {
      return null;
    }
  }

  // ── Charger depuis une chaîne GPX brute ─────────────────
  TraceModel? loadFromString(String gpxContent, {String? source}) {
    return _parseGpxString(gpxContent, source: source ?? 'string');
  }

  // ── Détecter la source depuis l'URL ─────────────────────
  String _detectSource(String url) {
    if (url.contains('wikiloc'))       return 'wikiloc';
    if (url.contains('thetrackmaster') || url.contains('transeurotrail')) return 'tet';
    if (url.contains('imarod'))        return 'imarod';
    return 'url';
  }

  // ── Parser le contenu GPX ────────────────────────────────
  TraceModel? _parseGpxString(String content, {required String source}) {
    try {
      final reader = gpx_lib.GpxReader();
      final gpxData = reader.fromString(content);

      // On prend en priorité les traces (tracks), sinon les routes, sinon les waypoints
      List<TracePoint> points = [];
      String name = 'Trace importée';
      String? description;

      if (gpxData.trks.isNotEmpty) {
        final trk = gpxData.trks.first;
        name = trk.name ?? name;
        description = trk.desc;
        for (final seg in trk.trksegs) {
          for (final wpt in seg.trkpts) {
            if (wpt.lat != null && wpt.lon != null) {
              points.add(TracePoint(
                position:  LatLng(wpt.lat!, wpt.lon!),
                elevation: wpt.ele?.toDouble(),
                time:      wpt.time,
              ));
            }
          }
        }
      } else if (gpxData.rtes.isNotEmpty) {
        final rte = gpxData.rtes.first;
        name = rte.name ?? name;
        description = rte.desc;
        for (final wpt in rte.rtepts) {
          if (wpt.lat != null && wpt.lon != null) {
            points.add(TracePoint(
              position:  LatLng(wpt.lat!, wpt.lon!),
              elevation: wpt.ele?.toDouble(),
              time:      wpt.time,
            ));
          }
        }
      }

      if (points.isEmpty) return null;

      // Métadonnées
      if (gpxData.metadata?.name != null) name = gpxData.metadata!.name!;

      return TraceModel(
        id:          _uuid.v4(),
        name:        name,
        description: description,
        points:      points,
        date:        gpxData.metadata?.time,
        source:      source,
      );
    } catch (e) {
      return null;
    }
  }

  // ── Exporter en GPX ─────────────────────────────────────
  String exportToGpx(TraceModel trace) {
    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln('<gpx version="1.1" creator="MotoOffroad4x4" '
        'xmlns="http://www.topografix.com/GPX/1/1">');
    buffer.writeln('  <metadata>');
    buffer.writeln('    <name>${_escapeXml(trace.name)}</name>');
    buffer.writeln('    <time>${DateTime.now().toUtc().toIso8601String()}</time>');
    buffer.writeln('  </metadata>');
    buffer.writeln('  <trk>');
    buffer.writeln('    <name>${_escapeXml(trace.name)}</name>');
    buffer.writeln('    <trkseg>');
    for (final p in trace.points) {
      final lat = p.position.latitude.toStringAsFixed(7);
      final lon = p.position.longitude.toStringAsFixed(7);
      buffer.write('      <trkpt lat="$lat" lon="$lon">');
      if (p.elevation != null) {
        buffer.write('<ele>${p.elevation!.toStringAsFixed(1)}</ele>');
      }
      if (p.time != null) {
        buffer.write('<time>${p.time!.toUtc().toIso8601String()}</time>');
      }
      buffer.writeln('</trkpt>');
    }
    buffer.writeln('    </trkseg>');
    buffer.writeln('  </trk>');
    buffer.writeln('</gpx>');
    return buffer.toString();
  }

  String _escapeXml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
