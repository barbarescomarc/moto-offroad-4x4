import 'package:latlong2/latlong.dart';

// ── Niveau de difficulté ─────────────────────────────────────
enum DifficultyLevel { debutant, confirme, expert }

extension DifficultyExt on DifficultyLevel {
  String get label {
    switch (this) {
      case DifficultyLevel.debutant:  return 'Débutant';
      case DifficultyLevel.confirme: return 'Confirmé';
      case DifficultyLevel.expert:   return 'Expert';
    }
  }

  int get color {
    switch (this) {
      case DifficultyLevel.debutant:  return 0xFF4CAF50;
      case DifficultyLevel.confirme: return 0xFFF57C00;
      case DifficultyLevel.expert:   return 0xFFEF5350;
    }
  }
}

// ── Point de trace GPX ───────────────────────────────────────
class TracePoint {
  final LatLng position;
  final double? elevation;      // altitude en mètres
  final DateTime? time;
  final double? speed;          // km/h
  final int? practicabilityScore; // 0-100 (0=praticable, 100=impraticable)

  const TracePoint({
    required this.position,
    this.elevation,
    this.time,
    this.speed,
    this.practicabilityScore,
  });

  bool get isImpracticable => (practicabilityScore ?? 0) > 70;
  bool get isDifficult     => (practicabilityScore ?? 0) > 30;
}

// ── Annotation sur la trace ──────────────────────────────────
enum AnnotationType { note, danger, photo, bivouac, gasStation }

class TraceAnnotation {
  final String id;
  final LatLng position;
  final AnnotationType type;
  final String? text;
  final String? photoPath;
  final DateTime createdAt;

  const TraceAnnotation({
    required this.id,
    required this.position,
    required this.type,
    this.text,
    this.photoPath,
    required this.createdAt,
  });
}

// ── Modèle Trace principal ───────────────────────────────────
class TraceModel {
  final String id;
  final String name;
  final String? description;
  final List<TracePoint> points;
  final List<TraceAnnotation> annotations;
  final DateTime? date;
  final String? source;         // 'gpx_file', 'url', 'created', 'tet', 'imarod'

  // Calculés
  double? _distance;
  double? _elevationGain;
  double? _elevationLoss;
  DifficultyLevel? _difficulty;

  TraceModel({
    required this.id,
    required this.name,
    this.description,
    required this.points,
    this.annotations = const [],
    this.date,
    this.source,
  });

  // ── Distance totale (mètres) ─────────────────────────────
  double get distanceMeters {
    if (_distance != null) return _distance!;
    if (points.length < 2) return 0;
    const calc = Distance();
    double total = 0;
    for (int i = 1; i < points.length; i++) {
      total += calc(points[i - 1].position, points[i].position);
    }
    return _distance = total;
  }

  double get distanceKm => distanceMeters / 1000;

  // ── Dénivelé positif / négatif ───────────────────────────
  double get elevationGain {
    if (_elevationGain != null) return _elevationGain!;
    double gain = 0;
    for (int i = 1; i < points.length; i++) {
      final prev = points[i - 1].elevation ?? 0;
      final curr = points[i].elevation ?? 0;
      if (curr > prev) gain += curr - prev;
    }
    return _elevationGain = gain;
  }

  double get elevationLoss {
    if (_elevationLoss != null) return _elevationLoss!;
    double loss = 0;
    for (int i = 1; i < points.length; i++) {
      final prev = points[i - 1].elevation ?? 0;
      final curr = points[i].elevation ?? 0;
      if (curr < prev) loss += prev - curr;
    }
    return _elevationLoss = loss;
  }

  // ── Altitude min/max ─────────────────────────────────────
  double get altMin => points
      .where((p) => p.elevation != null)
      .fold(double.infinity, (m, p) => p.elevation! < m ? p.elevation! : m);

  double get altMax => points
      .where((p) => p.elevation != null)
      .fold(double.negativeInfinity, (m, p) => p.elevation! > m ? p.elevation! : m);

  // ── Centre de la trace ───────────────────────────────────
  LatLng get center {
    if (points.isEmpty) return const LatLng(44.0, 6.0);
    final latAvg = points.map((p) => p.position.latitude).reduce((a, b) => a + b) / points.length;
    final lngAvg = points.map((p) => p.position.longitude).reduce((a, b) => a + b) / points.length;
    return LatLng(latAvg, lngAvg);
  }

  // ── Segments impraticables ───────────────────────────────
  List<List<LatLng>> get impracticableSegments {
    final segments = <List<LatLng>>[];
    List<LatLng>? current;
    for (final p in points) {
      if (p.isImpracticable) {
        current ??= [];
        current.add(p.position);
      } else if (current != null) {
        segments.add(current);
        current = null;
      }
    }
    if (current != null) segments.add(current);
    return segments;
  }

  // ── Point le plus proche de la position ──────────────────
  TracePoint? nearestPoint(LatLng pos) {
    if (points.isEmpty) return null;
    const calc = Distance();
    TracePoint? nearest;
    double minDist = double.infinity;
    for (final p in points) {
      final d = calc(pos, p.position);
      if (d < minDist) {
        minDist = d;
        nearest = p;
      }
    }
    return nearest;
  }

  // ── Index du point le plus proche ────────────────────────
  int nearestIndex(LatLng pos) {
    if (points.isEmpty) return -1;
    const calc = Distance();
    int idx = 0;
    double minDist = double.infinity;
    for (int i = 0; i < points.length; i++) {
      final d = calc(pos, points[i].position);
      if (d < minDist) {
        minDist = d;
        idx = i;
      }
    }
    return idx;
  }

  // ── Distance restante depuis une position ─────────────────
  double remainingDistance(LatLng pos) {
    final idx = nearestIndex(pos);
    if (idx < 0 || idx >= points.length - 1) return 0;
    const calc = Distance();
    double total = 0;
    for (int i = idx + 1; i < points.length; i++) {
      total += calc(points[i - 1].position, points[i].position);
    }
    return total;
  }
}
