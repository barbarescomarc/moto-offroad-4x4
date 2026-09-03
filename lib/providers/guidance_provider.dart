// lib/providers/guidance_provider.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../models/route_result.dart';
import '../models/trace.dart';
import '../services/gpx_route_deriver.dart';
import '../services/guidance_background_client.dart';
import '../services/guidance_voice_service.dart';
import '../services/location_service.dart';
import '../services/routing_service.dart';
import '../utils/route_geometry.dart';

enum GuidanceMode { destination, gpxAlert, gpxTurnByTurn }

class GuidanceProvider extends ChangeNotifier {
  GuidanceProvider({
    RoutingService? routingService,
    GuidanceVoiceService? voiceService,
    GuidanceBackgroundClient? backgroundClient,
    Stream<GpsSnapshot>? positionStream,
    DateTime Function()? clock,
  })  : _routing = routingService ?? RoutingService(),
        _voice = voiceService ?? GuidanceVoiceService(),
        _background = backgroundClient ?? GuidanceBackgroundClient(),
        _positionStream = positionStream ?? LocationService().stream,
        _clock = clock ?? DateTime.now;

  // Rayon (m) d'arrivée sur une manœuvre — au-delà, l'étape suivante démarre.
  static const double _stepArrivalRadiusMeters = 30;
  // Distances (m) de pré-annonce vocale avant une manœuvre.
  static const List<double> _announceThresholds = [300, 100];
  // Écarts (m) à la trace au-delà desquels on considère une déviation.
  static const double _offRouteThresholdRoute = 40;
  static const double _offRouteThresholdOffroad = 60;
  // Relevés consécutifs hors trace requis avant d'agir — filtre le bruit GPS.
  static const int _offRouteStreakThreshold = 2;
  // Fréquence minimale entre deux recalculs après déviation.
  static const Duration _rerouteCooldown = Duration(seconds: 20);
  // Silence GPS au-delà duquel le guidage se signale en perte de signal.
  static const Duration _gpsTimeout = Duration(seconds: 15);

  final RoutingService _routing;
  final GuidanceVoiceService _voice;
  final GuidanceBackgroundClient _background;
  final Stream<GpsSnapshot> _positionStream;
  final DateTime Function() _clock;

  StreamSubscription<GpsSnapshot>? _positionSub;
  Timer? _gpsTimeoutTimer;

  GuidanceMode? _mode;
  RouteResult? _route;
  int _currentStepIndex = 0;
  LatLng? _lastPosition;
  bool _isOffRoute = false;
  int _offRouteStreak = 0;
  DateTime? _lastRerouteAttempt;
  bool _gpsSignalLost = false;
  String? _error;
  final Set<double> _announcedThresholds = {};
  // Dernier segment de la polyligne reconnu sous le rider. Sert d'amorce à la
  // recherche fenêtrée : sur une trace qui boucle, un balayage complet peut
  // rattacher le rider au brin retour et masquer une vraie déviation.
  int _lastSegmentIndex = 0;

  // Contexte conservé pour un recalcul silencieux en mode destination.
  LatLng? _destination;
  RoutingProfile? _profile;
  Set<AvoidFeature> _avoid = const {};

  GuidanceMode? get mode => _mode;
  bool get isActive => _mode != null;
  RouteResult? get route => _route;
  bool get isOffRoute => _isOffRoute;
  bool get gpsSignalLost => _gpsSignalLost;
  bool get isMuted => _voice.isMuted;
  String? get error => _error;

  RouteStep? get currentStep {
    final r = _route;
    if (r == null || _currentStepIndex >= r.steps.length) return null;
    return r.steps[_currentStepIndex];
  }

  double get distanceToNextStepMeters {
    final step = currentStep;
    final pos = _lastPosition;
    if (step == null || pos == null) return 0;
    return const Distance()(pos, step.location);
  }

  double get remainingDistanceMeters {
    final r = _route;
    final pos = _lastPosition;
    if (r == null || pos == null || r.polyline.isEmpty) return 0;
    final nearest = nearestPointOnPolylineWindowed(pos, r.polyline, _lastSegmentIndex);
    const calc = Distance();
    double total = 0;
    for (var i = nearest.segmentIndex + 1; i < r.polyline.length; i++) {
      total += calc(r.polyline[i - 1], r.polyline[i]);
    }
    return total;
  }

  // Durée restante estimée, extrapolée de la durée totale de l'itinéraire au
  // prorata de la distance qu'il reste à parcourir. Les itinéraires dérivés
  // d'une trace GPX n'ont pas de durée (totalDurationSeconds == 0) : aucune
  // estimation n'est possible, on renvoie zéro et l'affichage s'en abstient.
  Duration get eta {
    final r = _route;
    if (r == null || r.totalDurationSeconds <= 0 || r.totalDistanceMeters <= 0) {
      return Duration.zero;
    }
    final ratio = (remainingDistanceMeters / r.totalDistanceMeters).clamp(0.0, 1.0);
    return Duration(seconds: (r.totalDurationSeconds * ratio).round());
  }

  // ── Démarrage : destination calculée ─────────────────────
  Future<bool> startToDestination({
    required LatLng origin,
    required LatLng destination,
    required RoutingProfile profile,
    Set<AvoidFeature> avoid = const {},
  }) async {
    _error = null;
    try {
      final result = await _routing.fetchRoute(
          origin: origin, destination: destination, profile: profile, avoid: avoid);
      _route = result;
      _mode = GuidanceMode.destination;
      _destination = destination;
      _profile = profile;
      _avoid = avoid;
      _resetProgress();
      _startListening();
      await _background.start('Guidage actif');
      notifyListeners();
      return true;
    } on RoutingException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    }
  }

  // ── Démarrage : trace GPX déjà chargée ───────────────────
  void startOnTrace(TraceModel trace, GuidanceMode mode) {
    assert(mode == GuidanceMode.gpxAlert || mode == GuidanceMode.gpxTurnByTurn);
    _error = null;
    _route = mode == GuidanceMode.gpxTurnByTurn
        ? GpxRouteDeriver.deriveTurnByTurn(trace)
        : GpxRouteDeriver.deriveForAlert(trace);
    _mode = mode;
    _destination = null;
    _profile = null;
    _avoid = const {};
    _resetProgress();
    _startListening();
    _background.start('Guidage actif');
    notifyListeners();
  }

  void _resetProgress() {
    _currentStepIndex = 0;
    _isOffRoute = false;
    _offRouteStreak = 0;
    _announcedThresholds.clear();
    _lastSegmentIndex = 0;
  }

  // Réinitialise uniquement les étapes lors d'un recalcul d'itinéraire.
  // Ne touche pas à _isOffRoute/_offRouteStreak : le prochain relevé GPS
  // les réévalue naturellement via _checkOffRoute une fois sur la nouvelle
  // route. Un reset complet ici effacerait le drapeau de déviation qui vient
  // de déclencher ce recalcul avant qu'aucun appelant n'ait pu l'observer.
  void _resetStepsForNewRoute() {
    _currentStepIndex = 0;
    _announcedThresholds.clear();
    // La polyligne vient d'être remplacée : l'index de segment mémorisé ne
    // désigne plus rien de comparable, la recherche fenêtrée repart du début.
    _lastSegmentIndex = 0;
  }

  void stop() {
    _mode = null;
    _route = null;
    _lastPosition = null;
    _positionSub?.cancel();
    _positionSub = null;
    _gpsTimeoutTimer?.cancel();
    _gpsTimeoutTimer = null;
    _gpsSignalLost = false;
    _background.stop();
    notifyListeners();
  }

  void toggleMute() {
    _voice.setMuted(!_voice.isMuted);
    notifyListeners();
  }

  void _startListening() {
    _positionSub?.cancel();
    _positionSub = _positionStream.listen(_onPosition);
    _resetGpsTimeout();
  }

  void _resetGpsTimeout() {
    _gpsTimeoutTimer?.cancel();
    _gpsSignalLost = false;
    _gpsTimeoutTimer = Timer(_gpsTimeout, () {
      _gpsSignalLost = true;
      notifyListeners();
    });
  }

  void _onPosition(GpsSnapshot snap) {
    if (!isActive || _route == null) return;
    _lastPosition = snap.position;
    _resetGpsTimeout();

    _checkStepAdvance(snap.position);
    _checkOffRoute(snap.position);
    notifyListeners();
  }

  void _checkStepAdvance(LatLng position) {
    final step = currentStep;
    if (step == null) return;
    const calc = Distance();
    final d = calc(position, step.location);

    for (final threshold in _announceThresholds) {
      if (d <= threshold && !_announcedThresholds.contains(threshold)) {
        _announcedThresholds.add(threshold);
        _voice.announce('Dans ${threshold.round()} mètres, ${step.instruction}');
      }
    }

    if (d <= _stepArrivalRadiusMeters) {
      _voice.announce(step.instruction);
      _announcedThresholds.clear();
      if (_currentStepIndex >= _route!.steps.length - 1) {
        stop();
      } else {
        _currentStepIndex++;
      }
    }
  }

  void _checkOffRoute(LatLng position) {
    final route = _route;
    if (route == null || route.polyline.isEmpty) return;

    final threshold =
        _mode == GuidanceMode.destination && _profile == RoutingProfile.drivingCar
            ? _offRouteThresholdRoute
            : _offRouteThresholdOffroad;

    final nearest =
        nearestPointOnPolylineWindowed(position, route.polyline, _lastSegmentIndex);
    _lastSegmentIndex = nearest.segmentIndex;
    final offNow = nearest.distanceMeters > threshold;

    _offRouteStreak = offNow ? _offRouteStreak + 1 : 0;
    final wasOffRoute = _isOffRoute;
    _isOffRoute = _offRouteStreak >= _offRouteStreakThreshold;

    if (!_isOffRoute) return;

    // Mode destination : on retente à chaque relevé tant que la déviation
    // persiste, pas seulement sur le front montant — sinon un rider qui
    // reste hors trace en continu (ex. piste alors que le guidage est en
    // profil route) n'est plus jamais rerouté après le premier recalcul.
    // _maybeReroute applique son propre cooldown, donc l'appel réseau
    // reste limité à ~1 fois par _rerouteCooldown malgré cet appel répété.
    if (_mode == GuidanceMode.destination) {
      _maybeReroute(position);
    } else if (_mode == GuidanceMode.gpxAlert && wasOffRoute != _isOffRoute) {
      // L'alerte vocale, elle, ne doit sonner qu'une fois par déviation —
      // pas de nag à chaque relevé tant qu'on reste hors trace.
      _voice.announce('Vous vous éloignez de la trace');
    }
  }

  Future<void> _maybeReroute(LatLng position) async {
    final now = _clock();
    if (_lastRerouteAttempt != null && now.difference(_lastRerouteAttempt!) < _rerouteCooldown) {
      return;
    }
    _lastRerouteAttempt = now;
    final destination = _destination;
    final profile = _profile;
    if (destination == null || profile == null) return;

    try {
      final result = await _routing.fetchRoute(
          origin: position, destination: destination, profile: profile, avoid: _avoid);
      _route = result;
      _resetStepsForNewRoute();
      notifyListeners();
    } on RoutingException {
      // Réseau indisponible : on garde le dernier itinéraire connu, la
      // prochaine déviation retentera après le délai de garde.
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _gpsTimeoutTimer?.cancel();
    super.dispose();
  }
}
