import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';
import '../models/ride.dart';
import '../models/trace.dart';
import '../services/gpx_service.dart';
import '../services/ride_repository.dart';

// ── Provider — Gestion de la trace active ────────────────────
class TraceProvider extends ChangeNotifier {
  final _gpxService = GpxService();

  TraceModel? _activeTrace;
  bool _isLoading = false;
  String? _error;
  int _currentPointIndex = 0;   // position du rider sur la trace

  TraceModel? get activeTrace     => _activeTrace;
  bool        get isLoading       => _isLoading;
  String?     get error           => _error;
  int         get currentIndex    => _currentPointIndex;
  bool        get hasTrace        => _activeTrace != null;

  // ── Import depuis un fichier GPX ─────────────────────────
  Future<bool> importFromFile(String filePath, {RideRepository? repository}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final trace = await _gpxService.loadFromFile(filePath);
    if (trace == null) {
      _error = 'Fichier GPX invalide ou illisible';
      _isLoading = false;
      notifyListeners();
      return false;
    }
    _activeTrace = trace;
    _currentPointIndex = 0;
    if (repository != null) await _persist(trace, repository);
    _isLoading = false;
    notifyListeners();
    return true;
  }

  // ── Import depuis une URL ────────────────────────────────
  Future<bool> importFromUrl(String url, {RideRepository? repository}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final trace = await _gpxService.loadFromUrl(url);
    if (trace == null) {
      _error = 'Impossible de charger la trace depuis cette URL';
      _isLoading = false;
      notifyListeners();
      return false;
    }
    _activeTrace = trace;
    _currentPointIndex = 0;
    if (repository != null) await _persist(trace, repository);
    _isLoading = false;
    notifyListeners();
    return true;
  }

  // ── Mettre à jour la position du rider sur la trace ──────
  void updatePosition(double lat, double lng) {
    if (_activeTrace == null) return;
    final pos = LatLng(lat, lng);
    final idx = _activeTrace!.nearestIndex(pos);
    if (idx != _currentPointIndex) {
      _currentPointIndex = idx;
      notifyListeners();
    }
  }

  // ── Distance restante depuis position actuelle ────────────
  double remainingKm(double lat, double lng) {
    if (_activeTrace == null) return 0;
    return _activeTrace!.remainingDistance(LatLng(lat, lng)) / 1000;
  }

  // ── Effacer la trace ─────────────────────────────────────
  void clearTrace() {
    _activeTrace = null;
    _currentPointIndex = 0;
    _error = null;
    notifyListeners();
  }

  // ── Sauvegarde d'une trace importée ──────────────────────
  // Une trace importée devient une sortie d'origine "imported" : elle
  // survit à la fermeture de l'app et devient éditable au lot 2.
  Future<void> _persist(TraceModel trace, RideRepository repo) async {
    final rideId = const Uuid().v4();
    final started = trace.date ?? DateTime.now();
    final points = <RidePoint>[];
    for (int i = 0; i < trace.points.length; i++) {
      final p = trace.points[i];
      points.add(RidePoint(
        rideId:    rideId,
        seq:       i,
        segment:   0,
        lat:       p.position.latitude,
        lng:       p.position.longitude,
        altitude:  p.elevation,
        speedKmh:  p.speed ?? 0,
        timestamp: p.time ?? started,
      ));
    }
    await repo.insertRide(Ride(
      id:        rideId,
      name:      trace.name,
      startedAt: started,
      endedAt:   started,
      source:    RideSource.imported,
      status:    RideStatus.finished,
      stats:     RideStats.fromPoints(points),
    ));
    await repo.appendPoints(points);
  }
}

