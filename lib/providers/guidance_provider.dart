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
import '../services/speed_camera_service.dart';
import '../services/speed_limit_service.dart';
import '../utils/route_geometry.dart';

enum GuidanceMode { destination, gpxAlert, gpxTurnByTurn }

class GuidanceProvider extends ChangeNotifier {
  GuidanceProvider({
    RoutingService? routingService,
    GuidanceVoiceService? voiceService,
    GuidanceBackgroundClient? backgroundClient,
    SpeedLimitService? speedLimitService,
    SpeedCameraService? speedCameraService,
    Stream<GpsSnapshot>? positionStream,
    DateTime Function()? clock,
  })  : _routing = routingService ?? RoutingService(),
        _voice = voiceService ?? GuidanceVoiceService(),
        _background = backgroundClient ?? GuidanceBackgroundClient(),
        _speedLimit = speedLimitService ?? SpeedLimitService(),
        _speedCamera = speedCameraService ?? SpeedCameraService(),
        _positionStream = positionStream ?? LocationService().stream,
        _clock = clock ?? DateTime.now;

  // Rayon (m) d'arrivée sur une manœuvre — au-delà, l'étape suivante démarre.
  static const double _stepArrivalRadiusMeters = 30;
  // Distances (m) de pré-annonce vocale avant une manœuvre.
  static const List<double> _announceThresholds = [300, 100];
  // Distance restante (m) le long de l'itinéraire en deçà de laquelle
  // l'arrivée devient possible. Sur une boucle, départ et arrivée se touchent :
  // à vol d'oiseau le rider est « arrivé » avant même d'être parti. Seule la
  // distance restante le long du parcours dit s'il a vraiment fait la boucle.
  static const double _finalStretchMeters = 300;
  // Écarts (m) à la trace au-delà desquels on considère une déviation.
  static const double _offRouteThresholdRoute = 40;
  static const double _offRouteThresholdOffroad = 60;
  // Relevés consécutifs hors trace requis avant d'agir — filtre le bruit GPS.
  static const int _offRouteStreakThreshold = 2;
  // Fréquence minimale entre deux recalculs après déviation.
  static const Duration _rerouteCooldown = Duration(seconds: 20);
  // Silence GPS au-delà duquel le guidage se signale en perte de signal.
  static const Duration _gpsTimeout = Duration(seconds: 15);
  // Fréquence de rafraîchissement de la limite de vitesse — Overpass n'est
  // pas fait pour être interrogé à chaque relevé GPS, on ne requête que si
  // le rider s'est significativement déplacé ou qu'assez de temps a passé.
  static const double _speedLimitMinMoveMeters = 200;
  static const Duration _speedLimitMinInterval = Duration(seconds: 45);
  // Fréquence de rafraîchissement des radars connus — leur position ne
  // change jamais, un intervalle plus large que la limite de vitesse suffit.
  static const double _cameraQueryMinMoveMeters = 500;
  static const Duration _cameraQueryMinInterval = Duration(seconds: 60);
  // Un radar à plus de cette distance de la route suivie n'est pas dessus
  // (route parallèle, bretelle...) : on l'ignore plutôt que de fausser
  // l'alerte.
  static const double _cameraMaxRoadDistanceMeters = 60;
  // Distances de pré-alerte légales (décret du 3 janvier 2012), choisies
  // selon la vitesse actuelle du rider à défaut de connaître le type de
  // route au niveau du radar lui-même (agglomération / route / autoroute).
  static const double _controlZoneAgglomerationMeters = 500;
  static const double _controlZoneRouteMeters = 2000;
  static const double _controlZoneAutorouteMeters = 4000;

  final RoutingService _routing;
  final GuidanceVoiceService _voice;
  final GuidanceBackgroundClient _background;
  final SpeedLimitService _speedLimit;
  final SpeedCameraService _speedCamera;
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
  double? _speedLimitKmh;
  LatLng? _lastSpeedLimitQueryPosition;
  DateTime? _lastSpeedLimitQueryAt;
  bool _speedLimitQueryInFlight = false;
  double? _upcomingControlZoneMeters;
  List<LatLng> _knownCameras = const [];
  LatLng? _lastCameraQueryPosition;
  DateTime? _lastCameraQueryAt;
  bool _cameraQueryInFlight = false;
  // Radar déjà annoncé à la voix — évite de répéter l'alerte à chaque
  // relevé GPS tant que le rider approche du même radar.
  LatLng? _announcedCamera;
  final Set<double> _announcedThresholds = {};
  // Dernier segment de la polyligne reconnu sous le rider. Sert d'amorce à la
  // recherche fenêtrée : sur une trace qui boucle, un balayage complet peut
  // rattacher le rider au brin retour et masquer une vraie déviation.
  int _lastSegmentIndex = 0;
  // Au premier relevé d'un itinéraire, la fenêtre n'a encore rien à quoi
  // s'accrocher : une trace GPX peut être rejointe n'importe où, y compris à
  // rebours. Un balayage complet amorce alors _lastSegmentIndex.
  bool _needsAcquisition = true;
  // Le rider a-t-il déjà été loin de l'arrivée sur cet itinéraire ? Sans ce
  // témoin, une boucle « arrive » au départ (voir _finalStretchMeters).
  bool _hasLeftFinalStretch = false;

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
  double? get speedLimitKmh => _speedLimitKmh;
  double? get upcomingControlZoneMeters => _upcomingControlZoneMeters;

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
    // Reste du segment courant à partir du point projeté, puis les suivants
    // en entier — compter tout le segment courant surestimerait la distance
    // de sa longueur, et ferait rater l'arrivée sur un long dernier tronçon.
    double total = calc(nearest.point, r.polyline[nearest.segmentIndex + 1]);
    for (var i = nearest.segmentIndex + 2; i < r.polyline.length; i++) {
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
    _needsAcquisition = true;
    _hasLeftFinalStretch = false;
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
    // désigne plus rien de comparable, la recherche se ré-amorce.
    _lastSegmentIndex = 0;
    _needsAcquisition = true;
    _hasLeftFinalStretch = false;
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
    _speedLimitKmh = null;
    _lastSpeedLimitQueryPosition = null;
    _lastSpeedLimitQueryAt = null;
    _upcomingControlZoneMeters = null;
    _knownCameras = const [];
    _lastCameraQueryPosition = null;
    _lastCameraQueryAt = null;
    _announcedCamera = null;
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

    // La position sur la trace d'abord : l'avancement des étapes s'appuie
    // sur la distance restante, qui dépend du segment reconnu à ce relevé.
    _checkOffRoute(snap.position);
    _noteDistanceFromFinish(snap.position);
    _checkStepAdvance(snap.position);
    _maybeRefreshSpeedLimit(snap.position);
    _maybeRefreshCameras(snap.position, snap.speedKmh);
    _updateUpcomingControlZone(snap.position, snap.speedKmh);
    notifyListeners();
  }

  void _maybeRefreshSpeedLimit(LatLng position) {
    if (_speedLimitQueryInFlight) return;
    final now = _clock();
    final lastAt = _lastSpeedLimitQueryAt;
    final lastPos = _lastSpeedLimitQueryPosition;
    final dueToTime = lastAt == null || now.difference(lastAt) >= _speedLimitMinInterval;
    final dueToMove = lastPos == null ||
        const Distance()(position, lastPos) >= _speedLimitMinMoveMeters;
    if (!dueToTime && !dueToMove) return;

    _speedLimitQueryInFlight = true;
    _lastSpeedLimitQueryPosition = position;
    _lastSpeedLimitQueryAt = now;
    _speedLimit.fetchSpeedLimitKmh(position).then((limit) {
      _speedLimitQueryInFlight = false;
      // Le guidage a pu s'arrêter pendant la requête : rien à mettre à jour.
      if (!isActive) return;
      _speedLimitKmh = limit;
      notifyListeners();
    });
  }

  void _maybeRefreshCameras(LatLng position, double speedKmh) {
    if (_cameraQueryInFlight) return;
    final now = _clock();
    final lastAt = _lastCameraQueryAt;
    final lastPos = _lastCameraQueryPosition;
    final dueToTime = lastAt == null || now.difference(lastAt) >= _cameraQueryMinInterval;
    final dueToMove = lastPos == null ||
        const Distance()(position, lastPos) >= _cameraQueryMinMoveMeters;
    if (!dueToTime && !dueToMove) return;

    _cameraQueryInFlight = true;
    _lastCameraQueryPosition = position;
    _lastCameraQueryAt = now;
    _speedCamera.fetchNearbyCameras(position).then((cameras) {
      _cameraQueryInFlight = false;
      // Le guidage a pu s'arrêter pendant la requête : rien à mettre à jour.
      if (!isActive) return;
      _knownCameras = cameras;
      // Le calcul synchrone dans _onPosition a pu tourner avant que ce cache
      // ne soit rempli (premier relevé, ou juste après un rafraîchissement) :
      // on le rejoue avec les données désormais à jour.
      _updateUpcomingControlZone(position, speedKmh);
      notifyListeners();
    });
  }

  // Ne signale jamais la position d'un radar — seule une "zone de contrôle
  // possible" est autorisée en France (décret du 3 janvier 2012). La
  // distance de pré-alerte dépend du type de route ; faute de connaître le
  // classement exact au niveau du radar, on l'approxime par la vitesse
  // actuelle du rider, qui corrèle fortement avec le type de route.
  void _updateUpcomingControlZone(LatLng position, double speedKmh) {
    final route = _route;
    if (route == null || route.polyline.length < 2 || _knownCameras.isEmpty) {
      _upcomingControlZoneMeters = null;
      return;
    }

    final riderNearest = nearestPointOnPolylineWindowed(position, route.polyline, _lastSegmentIndex);

    LatLng? nearestCamera;
    double? nearestDistance;
    for (final camera in _knownCameras) {
      final cameraNearest = nearestPointOnPolyline(camera, route.polyline);
      if (cameraNearest.distanceMeters > _cameraMaxRoadDistanceMeters) continue;
      final ahead = distanceAheadAlongPolyline(route.polyline, from: riderNearest, to: cameraNearest);
      if (ahead == null) continue;
      if (nearestDistance == null || ahead < nearestDistance) {
        nearestDistance = ahead;
        nearestCamera = camera;
      }
    }

    final threshold = speedKmh <= 60
        ? _controlZoneAgglomerationMeters
        : speedKmh <= 90
            ? _controlZoneRouteMeters
            : _controlZoneAutorouteMeters;

    if (nearestCamera == null || nearestDistance == null || nearestDistance > threshold) {
      _upcomingControlZoneMeters = null;
      // Le radar annoncé est désormais dépassé ou hors de portée : une
      // prochaine approche (le sien ou un autre) pourra être réannoncée.
      _announcedCamera = null;
      return;
    }

    _upcomingControlZoneMeters = nearestDistance;
    if (_announcedCamera != nearestCamera) {
      _announcedCamera = nearestCamera;
      _voice.announce('Zone de contrôle possible');
    }
  }

  // À vol d'oiseau, pas le long du parcours : sur une boucle, la distance
  // restante le long du tracé vaut toute la boucle dès le départ, alors que
  // le rider n'a pas bougé du point d'arrivée.
  void _noteDistanceFromFinish(LatLng position) {
    final r = _route;
    if (r == null || r.polyline.isEmpty) return;
    if (const Distance()(position, r.polyline.last) > _finalStretchMeters) {
      _hasLeftFinalStretch = true;
    }
  }

  // L'étape d'arrivée n'est prise en compte que si le rider a réellement
  // parcouru l'itinéraire : il en a déjà été loin (ou il est trop court pour
  // ça) et il n'en reste plus qu'un dernier tronçon. À vol d'oiseau seul, une
  // boucle serait « arrivée » dès le départ.
  bool get _arrivalEligible {
    final r = _route;
    if (r == null) return false;
    final hasCoveredRoute =
        _hasLeftFinalStretch || r.totalDistanceMeters <= _finalStretchMeters;
    return hasCoveredRoute && remainingDistanceMeters <= _finalStretchMeters;
  }

  void _checkStepAdvance(LatLng position) {
    final step = currentStep;
    if (step == null) return;
    if (step.maneuver == ManeuverType.arrive && !_arrivalEligible) return;
    const calc = Distance();
    final d = calc(position, step.location);

    // Une étape "tout droit" ne correspond à aucune manœuvre à exécuter —
    // ORS en génère beaucoup (changement de nom de rue, etc.) le long d'un
    // trajet globalement rectiligne. Les annoncer rendrait la voix bavarde
    // en permanence ; seule une vraie manœuvre mérite d'être dite.
    final announceable = step.maneuver != ManeuverType.straight;

    if (announceable) {
      for (final threshold in _announceThresholds) {
        if (d <= threshold && !_announcedThresholds.contains(threshold)) {
          _announcedThresholds.add(threshold);
          _voice.announce('Dans ${threshold.round()} mètres, ${step.instruction}');
        }
      }
    }

    if (d <= _stepArrivalRadiusMeters) {
      if (announceable) _voice.announce(step.instruction);
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

    // Premier relevé de l'itinéraire : balayage complet pour trouver où le
    // rider a rejoint la trace. Ensuite seulement, la fenêtre suit.
    final nearest = _needsAcquisition
        ? nearestPointOnPolyline(position, route.polyline)
        : nearestPointOnPolylineWindowed(position, route.polyline, _lastSegmentIndex);
    _needsAcquisition = false;
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
