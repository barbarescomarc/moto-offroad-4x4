import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

// ── Snapshot de position GPS ─────────────────────────────────
class GpsSnapshot {
  final LatLng position;
  final double accuracyMeters;
  final double altitudeMeters;
  final double speedKmh;
  final double headingDeg;  // cap 0-360°
  final DateTime timestamp;

  const GpsSnapshot({
    required this.position,
    required this.accuracyMeters,
    required this.altitudeMeters,
    required this.speedKmh,
    required this.headingDeg,
    required this.timestamp,
  });

  factory GpsSnapshot.fromPosition(Position p) => GpsSnapshot(
    position:        LatLng(p.latitude, p.longitude),
    accuracyMeters:  p.accuracy,
    altitudeMeters:  p.altitude,
    speedKmh:        (p.speed * 3.6).clamp(0, 300),  // m/s → km/h
    headingDeg:      p.heading,
    timestamp:       p.timestamp,
  );

  // Texte GPS pour SOS
  String get sosText =>
      'Lat: ${position.latitude.toStringAsFixed(6)}° N\n'
      'Lon: ${position.longitude.toStringAsFixed(6)}° E\n'
      'Alt: ${altitudeMeters.toStringAsFixed(0)} m\n'
      'Précision: ±${accuracyMeters.toStringAsFixed(0)} m';

  // Lien Google Maps
  String get googleMapsUrl =>
      'https://maps.google.com/?q=${position.latitude.toStringAsFixed(6)},${position.longitude.toStringAsFixed(6)}';

  // Lien What3Words (optionnel)
  String get w3wUrl =>
      'https://what3words.com/map?lat=${position.latitude}&lng=${position.longitude}';

  // Message SOS complet
  String get sosMessage =>
      'URGENCE - Motard en détresse.\n'
      'Ma position GPS :\n$sosText\n\n'
      'Carte : $googleMapsUrl\n\n'
      'Heure : ${timestamp.toLocal()}';
}

// ── Service GPS ──────────────────────────────────────────────
class LocationService {
  static final LocationService _instance = LocationService._();
  factory LocationService() => _instance;
  LocationService._();

  StreamSubscription<Position>? _subscription;
  final _controller = StreamController<GpsSnapshot>.broadcast();

  GpsSnapshot? _lastSnapshot;
  GpsSnapshot? get lastSnapshot => _lastSnapshot;

  Stream<GpsSnapshot> get stream => _controller.stream;

  // ── Vérification et demande de permissions ───────────────
  Future<bool> requestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }
    if (permission == LocationPermission.deniedForever) return false;
    return true;
  }

  // ── Démarrer le suivi GPS ────────────────────────────────
  Future<void> startTracking() async {
    final hasPermission = await requestPermission();
    if (!hasPermission) return;

    const settings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 5,       // mise à jour tous les 5 mètres minimum
    );

    _subscription?.cancel();
    _subscription = Geolocator.getPositionStream(locationSettings: settings)
        .listen((position) {
      final snap = GpsSnapshot.fromPosition(position);
      _lastSnapshot = snap;
      _controller.add(snap);
    });
  }

  // ── Arrêter le suivi ─────────────────────────────────────
  void stopTracking() {
    _subscription?.cancel();
    _subscription = null;
  }

  // ── Position instantanée (one-shot) ─────────────────────
  Future<GpsSnapshot?> getCurrentPosition() async {
    final hasPermission = await requestPermission();
    if (!hasPermission) return null;

    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
        timeLimit: const Duration(seconds: 10),
      );
      final snap = GpsSnapshot.fromPosition(pos);
      _lastSnapshot = snap;
      return snap;
    } catch (_) {
      return null;
    }
  }

  // ── Distance entre deux positions ────────────────────────
  double distanceBetween(LatLng a, LatLng b) {
    return Geolocator.distanceBetween(
      a.latitude, a.longitude,
      b.latitude, b.longitude,
    );
  }

  void dispose() {
    _subscription?.cancel();
    _controller.close();
  }
}
