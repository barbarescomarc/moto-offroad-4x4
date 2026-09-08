// test/providers/guidance_provider_test.dart
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:moto_offroad/models/route_result.dart';
import 'package:moto_offroad/models/trace.dart';
import 'package:moto_offroad/providers/guidance_provider.dart';
import 'package:moto_offroad/services/background_service_coordinator.dart';
import 'package:moto_offroad/services/guidance_background_client.dart';
import 'package:moto_offroad/services/guidance_voice_service.dart';
import 'package:moto_offroad/services/location_service.dart';
import 'package:moto_offroad/services/routing_service.dart';
import 'package:moto_offroad/services/speed_camera_service.dart';
import 'package:moto_offroad/services/speed_limit_service.dart';

final _t0 = DateTime(2026, 9, 3, 10, 0, 0);

GpsSnapshot _gps(LatLng pos, {int s = 0, double speedKmh = 20}) => GpsSnapshot(
  position:       pos,
  accuracyMeters: 4,
  altitudeMeters: 300,
  speedKmh:       speedKmh,
  headingDeg:     0,
  timestamp:      _t0.add(Duration(seconds: s)),
);

class _FakeRoutingService extends RoutingService {
  int calls = 0;
  int alternativesCalls = 0;
  RouteResult Function()? nextResult;
  List<RouteResult> Function()? nextAlternatives;
  bool shouldThrow = false;

  @override
  Future<RouteResult> fetchRoute({
    required LatLng origin,
    required LatLng destination,
    required RoutingProfile profile,
    Set<AvoidFeature> avoid = const {},
  }) async {
    calls++;
    if (shouldThrow) throw const RoutingException('pas de réseau');
    return nextResult!();
  }

  @override
  Future<List<RouteResult>> fetchRouteAlternatives({
    required LatLng origin,
    required LatLng destination,
    required RoutingProfile profile,
    Set<AvoidFeature> avoid = const {},
    int targetCount = 3,
  }) async {
    alternativesCalls++;
    if (shouldThrow) throw const RoutingException('pas de réseau');
    return nextAlternatives!();
  }
}

class _FakeControl implements ForegroundServiceControl {
  @override
  Future<bool> isRunning() async => true;
  @override
  Future<bool> start({required String title, required String text}) async => true;
  @override
  Future<void> update({required String title, required String text}) async {}
  @override
  Future<void> stop() async {}
}

class _FakeSpeedLimitService extends SpeedLimitService {
  int calls = 0;
  final List<LatLng> queriedPositions = [];
  double? nextLimit;

  @override
  Future<double?> fetchSpeedLimitKmh(LatLng position) async {
    calls++;
    queriedPositions.add(position);
    return nextLimit;
  }
}

class _FakeSpeedCameraService extends SpeedCameraService {
  int calls = 0;
  List<LatLng> nextCameras = const [];

  @override
  Future<List<LatLng>> fetchNearbyCameras(LatLng position) async {
    calls++;
    return nextCameras;
  }
}

class _FakeTtsEngine implements TtsEngine {
  final List<String> spoken = [];
  @override
  Future<void> setLanguage(String lang) async {}
  @override
  Future<void> speak(String text) async => spoken.add(text);
  @override
  Future<void> stop() async {}
}

RouteResult _straightRoute() => RouteResult(
  polyline: [const LatLng(44.0, 6.0), const LatLng(44.0, 6.01)],
  steps: [
    const RouteStep(
      instruction: 'Tournez à droite',
      distanceMeters: 500,
      maneuver: ManeuverType.turnRight,
      location: LatLng(44.0, 6.005),
    ),
    const RouteStep(
      instruction: 'Destination atteinte',
      distanceMeters: 500,
      maneuver: ManeuverType.arrive,
      location: LatLng(44.0, 6.01),
    ),
  ],
  totalDistanceMeters: 1000,
  totalDurationSeconds: 120,
);

// Deux segments d'environ 400 m, 800,7 m annoncés en 600 s : à la charnière,
// il reste exactement la moitié du trajet.
RouteResult _twoSegmentRoute() => const RouteResult(
  polyline: [LatLng(44.0, 6.0), LatLng(44.0, 6.005), LatLng(44.0, 6.01)],
  steps: [
    RouteStep(
      instruction: 'Destination atteinte',
      distanceMeters: 800,
      maneuver: ManeuverType.arrive,
      location: LatLng(44.0, 6.01),
    ),
  ],
  totalDistanceMeters: 800.7,
  totalDurationSeconds: 600,
);

TraceModel _traceFrom(List<LatLng> points) => TraceModel(
  id: 't1', name: 'test',
  points: points.map((p) => TracePoint(position: p)).toList(),
);

void main() {
  late StreamController<GpsSnapshot> positionController;
  late _FakeRoutingService routing;
  late _FakeSpeedLimitService speedLimit;
  late _FakeSpeedCameraService speedCamera;
  late _FakeTtsEngine ttsEngine;
  late GuidanceProvider guidance;
  late DateTime fakeNow;

  setUp(() {
    positionController = StreamController<GpsSnapshot>.broadcast();
    routing = _FakeRoutingService();
    speedLimit = _FakeSpeedLimitService();
    speedCamera = _FakeSpeedCameraService();
    ttsEngine = _FakeTtsEngine();
    fakeNow = _t0;
    guidance = GuidanceProvider(
      routingService: routing,
      voiceService: GuidanceVoiceService(engine: ttsEngine),
      backgroundClient: GuidanceBackgroundClient(
        coordinator: BackgroundServiceCoordinator(control: _FakeControl()),
      ),
      speedLimitService: speedLimit,
      speedCameraService: speedCamera,
      positionStream: positionController.stream,
      clock: () => fakeNow,
    );
  });

  tearDown(() => positionController.close());

  test('startToDestination active le guidage et récupère la route', () async {
    routing.nextResult = _straightRoute;
    final ok = await guidance.startToDestination(
      origin: const LatLng(44.0, 6.0),
      destination: const LatLng(44.0, 6.01),
      profile: RoutingProfile.drivingCar,
    );
    expect(ok, isTrue);
    expect(guidance.isActive, isTrue);
    expect(guidance.mode, GuidanceMode.destination);
    expect(guidance.currentStep?.instruction, 'Tournez à droite');
  });

  test('preferCurvyRoutes demande des alternatives et retient la plus sinueuse', () async {
    final straight = RouteResult(
      polyline: [const LatLng(44.00, 6.0), const LatLng(44.02, 6.0)],
      steps: const [],
      totalDistanceMeters: 2000, totalDurationSeconds: 200,
    );
    final curvy = RouteResult(
      polyline: [
        const LatLng(44.00, 6.00),
        const LatLng(44.01, 6.00),
        const LatLng(44.01, 6.01),
        const LatLng(44.02, 6.01),
        const LatLng(44.02, 6.02),
        const LatLng(44.01, 6.02),
      ],
      steps: const [],
      totalDistanceMeters: 2500, totalDurationSeconds: 260,
    );
    routing.nextAlternatives = () => [straight, curvy];

    final ok = await guidance.startToDestination(
      origin: const LatLng(44.0, 6.0),
      destination: const LatLng(44.02, 6.02),
      profile: RoutingProfile.drivingCar,
      preferCurvyRoutes: true,
    );

    expect(ok, isTrue);
    expect(routing.alternativesCalls, 1);
    expect(routing.calls, 0);
    expect(guidance.route?.polyline, curvy.polyline);
  });

  test('sans preferCurvyRoutes, une seule route est demandée (pas d\'alternatives)', () async {
    routing.nextResult = _straightRoute;

    await guidance.startToDestination(
      origin: const LatLng(44.0, 6.0),
      destination: const LatLng(44.0, 6.01),
      profile: RoutingProfile.drivingCar,
    );

    expect(routing.calls, 1);
    expect(routing.alternativesCalls, 0);
  });

  test('échec réseau au démarrage n\'active pas le guidage et remplit error', () async {
    routing.shouldThrow = true;
    final ok = await guidance.startToDestination(
      origin: const LatLng(44.0, 6.0),
      destination: const LatLng(44.0, 6.01),
      profile: RoutingProfile.drivingCar,
    );
    expect(ok, isFalse);
    expect(guidance.isActive, isFalse);
    expect(guidance.error, isNotNull);
  });

  test('approcher du point de manœuvre avance à l\'étape suivante et annonce', () async {
    routing.nextResult = _straightRoute;
    await guidance.startToDestination(
      origin: const LatLng(44.0, 6.0),
      destination: const LatLng(44.0, 6.01),
      profile: RoutingProfile.drivingCar,
    );

    positionController.add(_gps(const LatLng(44.0, 6.005)));
    await Future<void>.delayed(Duration.zero);

    expect(guidance.currentStep?.maneuver, ManeuverType.arrive);
    expect(ttsEngine.spoken, contains('Tournez à droite'));
  });

  test('atteindre la dernière étape arrête le guidage', () async {
    routing.nextResult = _straightRoute;
    await guidance.startToDestination(
      origin: const LatLng(44.0, 6.0),
      destination: const LatLng(44.0, 6.01),
      profile: RoutingProfile.drivingCar,
    );

    positionController.add(_gps(const LatLng(44.0, 6.005)));
    await Future<void>.delayed(Duration.zero);
    positionController.add(_gps(const LatLng(44.0, 6.01)));
    await Future<void>.delayed(Duration.zero);

    expect(guidance.isActive, isFalse);
  });

  test('un seul relevé hors trace ne déclenche pas de déviation (filtre le bruit)', () async {
    routing.nextResult = _straightRoute;
    await guidance.startToDestination(
      origin: const LatLng(44.0, 6.0),
      destination: const LatLng(44.0, 6.01),
      profile: RoutingProfile.drivingCar,
    );

    positionController.add(_gps(const LatLng(44.002, 6.0))); // ~220m à côté
    await Future<void>.delayed(Duration.zero);

    expect(guidance.isOffRoute, isFalse);
    expect(routing.calls, 1); // uniquement l'appel initial
  });

  test('une déviation soutenue en mode destination redemande un itinéraire', () async {
    routing.nextResult = _straightRoute;
    await guidance.startToDestination(
      origin: const LatLng(44.0, 6.0),
      destination: const LatLng(44.0, 6.01),
      profile: RoutingProfile.drivingCar,
    );

    positionController.add(_gps(const LatLng(44.002, 6.0), s: 1));
    await Future<void>.delayed(Duration.zero);
    positionController.add(_gps(const LatLng(44.002, 6.0), s: 2));
    await Future<void>.delayed(Duration.zero);

    expect(guidance.isOffRoute, isTrue);
    expect(routing.calls, 2); // appel initial + recalcul
  });

  test(
    'une déviation qui persiste après le recalcul redemande un itinéraire une fois le cooldown écoulé',
    () async {
      routing.nextResult = _straightRoute;
      await guidance.startToDestination(
        origin: const LatLng(44.0, 6.0),
        destination: const LatLng(44.0, 6.01),
        profile: RoutingProfile.drivingCar,
      );

      positionController.add(_gps(const LatLng(44.002, 6.0), s: 1));
      await Future<void>.delayed(Duration.zero);
      positionController.add(_gps(const LatLng(44.002, 6.0), s: 2));
      await Future<void>.delayed(Duration.zero);

      expect(guidance.isOffRoute, isTrue);
      expect(routing.calls, 2); // appel initial + premier recalcul

      // Toujours hors trace juste après : le cooldown de 20s bloque un
      // nouvel appel réseau immédiat, même si la déviation persiste.
      positionController.add(_gps(const LatLng(44.002, 6.0), s: 3));
      await Future<void>.delayed(Duration.zero);
      expect(routing.calls, 2);

      // Le cooldown écoulé (horloge simulée, pas d'attente réelle), un
      // relevé toujours hors trace redemande un itinéraire : la déviation
      // continue de retenter tant qu'elle persiste, elle ne s'arme plus
      // seulement sur le front montant.
      fakeNow = fakeNow.add(const Duration(seconds: 21));
      positionController.add(_gps(const LatLng(44.002, 6.0), s: 4));
      await Future<void>.delayed(Duration.zero);

      expect(routing.calls, 3);
    },
  );

  test('startOnTrace en mode alerte ne fait aucun appel réseau', () {
    final trace = _traceFrom([const LatLng(44.0, 6.0), const LatLng(44.01, 6.0)]);
    guidance.startOnTrace(trace, GuidanceMode.gpxAlert);

    expect(guidance.isActive, isTrue);
    expect(guidance.mode, GuidanceMode.gpxAlert);
    expect(routing.calls, 0);
  });

  test('mute empêche les annonces vocales', () async {
    routing.nextResult = _straightRoute;
    await guidance.startToDestination(
      origin: const LatLng(44.0, 6.0),
      destination: const LatLng(44.0, 6.01),
      profile: RoutingProfile.drivingCar,
    );
    guidance.toggleMute();

    positionController.add(_gps(const LatLng(44.0, 6.005)));
    await Future<void>.delayed(Duration.zero);

    expect(ttsEngine.spoken, isEmpty);
  });

  test('l\'ETA est proportionnelle à la distance restante', () async {
    routing.nextResult = _twoSegmentRoute;
    await guidance.startToDestination(
      origin: const LatLng(44.0, 6.0),
      destination: const LatLng(44.0, 6.01),
      profile: RoutingProfile.drivingCar,
    );

    // À la charnière entre les deux segments : il reste exactement le second.
    positionController.add(_gps(const LatLng(44.0, 6.005)));
    await Future<void>.delayed(Duration.zero);

    expect(guidance.remainingDistanceMeters, closeTo(400, 10));
    expect(guidance.eta.inSeconds, closeTo(300, 15));
  });

  test('pas d\'ETA sur une trace GPX, faute de durée connue', () async {
    final trace = _traceFrom([const LatLng(44.0, 6.0), const LatLng(44.01, 6.0)]);
    guidance.startOnTrace(trace, GuidanceMode.gpxAlert);

    positionController.add(_gps(const LatLng(44.001, 6.0)));
    await Future<void>.delayed(Duration.zero);

    expect(guidance.remainingDistanceMeters, greaterThan(0));
    expect(guidance.eta, Duration.zero);
  });

  test('le mode alerte GPX s\'arrête en bout de trace', () async {
    final trace = _traceFrom([const LatLng(44.0, 6.0), const LatLng(44.01, 6.0)]);
    guidance.startOnTrace(trace, GuidanceMode.gpxAlert);
    expect(guidance.isActive, isTrue);

    // On part du début de la trace, puis on en atteint le bout.
    positionController.add(_gps(const LatLng(44.0, 6.0), s: 1));
    await Future<void>.delayed(Duration.zero);
    positionController.add(_gps(const LatLng(44.01, 6.0), s: 2));
    await Future<void>.delayed(Duration.zero);

    expect(guidance.isActive, isFalse);
    expect(ttsEngine.spoken, contains('Destination atteinte'));
  });

  test('stop désactive le guidage', () async {
    routing.nextResult = _straightRoute;
    await guidance.startToDestination(
      origin: const LatLng(44.0, 6.0),
      destination: const LatLng(44.0, 6.01),
      profile: RoutingProfile.drivingCar,
    );
    guidance.stop();
    expect(guidance.isActive, isFalse);
    expect(guidance.route, isNull);
  });

  // ── Traces en boucle : départ ≈ arrivée ───────────────────
  //
  // Carré de 500 m de côté qui revient à son point de départ — la forme
  // typique d'une sortie offroad. Le point d'arrivée est à moins de 30 m du
  // point de départ : sans garde-fou, le guidage « arrive » dès le premier
  // relevé.

  test('trace GPX en boucle : le guidage ne s\'arrête pas au point de départ', () async {
    guidance.startOnTrace(_traceFrom(_squareLoop), GuidanceMode.gpxAlert);

    positionController.add(_gps(_squareLoop.first, s: 1));
    await Future<void>.delayed(Duration.zero);
    // Bruit GPS : 5 m au nord du départ, soit du côté du brin retour.
    positionController.add(_gps(const LatLng(44.000045, 6.0), s: 2));
    await Future<void>.delayed(Duration.zero);

    expect(guidance.isActive, isTrue);
    expect(ttsEngine.spoken, isEmpty);
  });

  test('trace GPX en boucle : l\'arrivée est détectée une fois la boucle parcourue', () async {
    guidance.startOnTrace(_traceFrom(_squareLoop), GuidanceMode.gpxAlert);

    positionController.add(_gps(_squareLoop[1], s: 1));
    await Future<void>.delayed(Duration.zero);
    positionController.add(_gps(_squareLoop[2], s: 2));
    await Future<void>.delayed(Duration.zero);
    positionController.add(_gps(_squareLoop[3], s: 3));
    await Future<void>.delayed(Duration.zero);
    // 10 m avant la fermeture de la boucle, sur le dernier brin.
    positionController.add(_gps(const LatLng(44.00009, 6.0), s: 4));
    await Future<void>.delayed(Duration.zero);

    expect(guidance.isActive, isFalse);
    expect(ttsEngine.spoken, contains('Destination atteinte'));
  });

  // ── Recherche fenêtrée : accrochage initial et recalage ───

  test('guidage GPX démarré au milieu de la trace : le premier relevé s\'accroche au bon segment', () async {
    guidance.startOnTrace(_traceFrom(_longStraightTrace), GuidanceMode.gpxAlert);

    positionController.add(_gps(_longStraightTrace[20], s: 1));
    await Future<void>.delayed(Duration.zero);
    positionController.add(_gps(_longStraightTrace[20], s: 2));
    await Future<void>.delayed(Duration.zero);

    expect(guidance.isOffRoute, isFalse);
    // Il reste 9 segments d'environ 100 m, pas les 29 de la trace entière.
    expect(guidance.remainingDistanceMeters, closeTo(900, 20));
  });

  // ── Limite de vitesse ──────────────────────────────────────

  group('speedLimitKmh', () {
    test('se met à jour depuis le premier relevé GPS en guidage', () async {
      speedLimit.nextLimit = 90;
      guidance.startOnTrace(_traceFrom(_longStraightTrace), GuidanceMode.gpxAlert);

      positionController.add(_gps(_longStraightTrace[0], s: 1));
      await Future<void>.delayed(Duration.zero);

      expect(speedLimit.calls, 1);
      expect(guidance.speedLimitKmh, 90);
    });

    test('ne requête pas à nouveau sur un relevé proche dans le temps et l\'espace', () async {
      speedLimit.nextLimit = 90;
      guidance.startOnTrace(_traceFrom(_longStraightTrace), GuidanceMode.gpxAlert);
      positionController.add(_gps(_longStraightTrace[0], s: 1));
      await Future<void>.delayed(Duration.zero);
      expect(speedLimit.calls, 1);

      // Quelques mètres plus loin, quelques secondes après.
      positionController.add(_gps(_longStraightTrace[1], s: 2));
      await Future<void>.delayed(Duration.zero);

      expect(speedLimit.calls, 1);
    });

    test('requête à nouveau après un déplacement suffisant', () async {
      speedLimit.nextLimit = 90;
      guidance.startOnTrace(_traceFrom(_longStraightTrace), GuidanceMode.gpxAlert);
      positionController.add(_gps(_longStraightTrace[0], s: 1));
      await Future<void>.delayed(Duration.zero);
      expect(speedLimit.calls, 1);

      // ~100 m plus loin par point de la trace ; 3 points ≈ 270 m.
      positionController.add(_gps(_longStraightTrace[3], s: 2));
      await Future<void>.delayed(Duration.zero);

      expect(speedLimit.calls, 2);
    });

    test('requête à nouveau après un délai suffisant même sans déplacement', () async {
      speedLimit.nextLimit = 90;
      guidance.startOnTrace(_traceFrom(_longStraightTrace), GuidanceMode.gpxAlert);
      positionController.add(_gps(_longStraightTrace[0], s: 1));
      await Future<void>.delayed(Duration.zero);
      expect(speedLimit.calls, 1);

      fakeNow = fakeNow.add(const Duration(seconds: 50));
      positionController.add(_gps(_longStraightTrace[0], s: 2));
      await Future<void>.delayed(Duration.zero);

      expect(speedLimit.calls, 2);
    });

    test('remise à zéro à l\'arrêt du guidage', () async {
      speedLimit.nextLimit = 90;
      guidance.startOnTrace(_traceFrom(_longStraightTrace), GuidanceMode.gpxAlert);
      positionController.add(_gps(_longStraightTrace[0], s: 1));
      await Future<void>.delayed(Duration.zero);
      expect(guidance.speedLimitKmh, 90);

      guidance.stop();

      expect(guidance.speedLimitKmh, isNull);
    });
  });

  // ── Zone de contrôle possible (radars fixes) ──────────────
  // _longStraightTrace : 30 points plein nord espacés d'environ 100,2 m.

  group('upcomingControlZoneMeters', () {
    test('un radar à ~400 m devant, à faible vitesse, déclenche la zone', () async {
      speedCamera.nextCameras = [_longStraightTrace[4]]; // ~400 m
      guidance.startOnTrace(_traceFrom(_longStraightTrace), GuidanceMode.gpxAlert);

      positionController.add(_gps(_longStraightTrace[0], s: 1, speedKmh: 20));
      await Future<void>.delayed(Duration.zero);

      expect(guidance.upcomingControlZoneMeters, isNotNull);
      expect(guidance.upcomingControlZoneMeters, closeTo(400, 20));
      expect(ttsEngine.spoken, contains('Zone de contrôle possible'));
    });

    test('un radar derrière le rider n\'est pas signalé', () async {
      speedCamera.nextCameras = [_longStraightTrace[2]];
      guidance.startOnTrace(_traceFrom(_longStraightTrace), GuidanceMode.gpxAlert);

      positionController.add(_gps(_longStraightTrace[10], s: 1, speedKmh: 20));
      await Future<void>.delayed(Duration.zero);

      expect(guidance.upcomingControlZoneMeters, isNull);
    });

    test('un radar hors de portée pour la vitesse actuelle n\'est pas signalé', () async {
      speedCamera.nextCameras = [_longStraightTrace[8]]; // ~800 m
      guidance.startOnTrace(_traceFrom(_longStraightTrace), GuidanceMode.gpxAlert);

      // 20 km/h → seuil agglomération (500 m), 800 m est hors de portée.
      positionController.add(_gps(_longStraightTrace[0], s: 1, speedKmh: 20));
      await Future<void>.delayed(Duration.zero);

      expect(guidance.upcomingControlZoneMeters, isNull);
    });

    test('le même radar devient audible à vitesse plus élevée (seuil route)', () async {
      speedCamera.nextCameras = [_longStraightTrace[8]]; // ~800 m
      guidance.startOnTrace(_traceFrom(_longStraightTrace), GuidanceMode.gpxAlert);

      // 70 km/h → seuil route (2000 m), 800 m est dans la zone.
      positionController.add(_gps(_longStraightTrace[0], s: 1, speedKmh: 70));
      await Future<void>.delayed(Duration.zero);

      expect(guidance.upcomingControlZoneMeters, closeTo(800, 20));
    });

    test('un radar trop éloigné latéralement de la route est ignoré', () async {
      // ~240 m à l'est du tracé (au-delà du seuil de 60 m).
      speedCamera.nextCameras = [const LatLng(44.0009, 6.003)];
      guidance.startOnTrace(_traceFrom(_longStraightTrace), GuidanceMode.gpxAlert);

      positionController.add(_gps(_longStraightTrace[0], s: 1, speedKmh: 20));
      await Future<void>.delayed(Duration.zero);

      expect(guidance.upcomingControlZoneMeters, isNull);
    });

    test('l\'annonce vocale ne se répète pas en approchant du même radar', () async {
      speedCamera.nextCameras = [_longStraightTrace[4]];
      guidance.startOnTrace(_traceFrom(_longStraightTrace), GuidanceMode.gpxAlert);

      positionController.add(_gps(_longStraightTrace[0], s: 1, speedKmh: 20));
      await Future<void>.delayed(Duration.zero);
      positionController.add(_gps(_longStraightTrace[1], s: 2, speedKmh: 20));
      await Future<void>.delayed(Duration.zero);

      expect(ttsEngine.spoken.where((m) => m == 'Zone de contrôle possible').length, 1);
    });

    test('remise à zéro à l\'arrêt du guidage', () async {
      speedCamera.nextCameras = [_longStraightTrace[4]];
      guidance.startOnTrace(_traceFrom(_longStraightTrace), GuidanceMode.gpxAlert);
      positionController.add(_gps(_longStraightTrace[0], s: 1, speedKmh: 20));
      await Future<void>.delayed(Duration.zero);
      expect(guidance.upcomingControlZoneMeters, isNotNull);

      guidance.stop();

      expect(guidance.upcomingControlZoneMeters, isNull);
    });
  });
}

// Carré de ~500 m de côté fermé sur son point de départ (0,0045° de latitude
// et 0,00625° de longitude font ~500 m à 44° N).
const _squareLoop = [
  LatLng(44.0, 6.0),
  LatLng(44.0, 6.00625),
  LatLng(44.0045, 6.00625),
  LatLng(44.0045, 6.0),
  LatLng(44.0, 6.0),
];

// 30 points plein nord espacés de ~100 m (0,0009° de latitude).
final _longStraightTrace = List.generate(30, (i) => LatLng(44.0 + i * 0.0009, 6.0));
