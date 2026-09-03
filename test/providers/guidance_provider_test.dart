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

final _t0 = DateTime(2026, 9, 3, 10, 0, 0);

GpsSnapshot _gps(LatLng pos, {int s = 0}) => GpsSnapshot(
  position:       pos,
  accuracyMeters: 4,
  altitudeMeters: 300,
  speedKmh:       20,
  headingDeg:     0,
  timestamp:      _t0.add(Duration(seconds: s)),
);

class _FakeRoutingService extends RoutingService {
  int calls = 0;
  RouteResult Function()? nextResult;
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

TraceModel _traceFrom(List<LatLng> points) => TraceModel(
  id: 't1', name: 'test',
  points: points.map((p) => TracePoint(position: p)).toList(),
);

void main() {
  late StreamController<GpsSnapshot> positionController;
  late _FakeRoutingService routing;
  late _FakeTtsEngine ttsEngine;
  late GuidanceProvider guidance;

  setUp(() {
    positionController = StreamController<GpsSnapshot>.broadcast();
    routing = _FakeRoutingService();
    ttsEngine = _FakeTtsEngine();
    guidance = GuidanceProvider(
      routingService: routing,
      voiceService: GuidanceVoiceService(engine: ttsEngine),
      backgroundClient: GuidanceBackgroundClient(
        coordinator: BackgroundServiceCoordinator(control: _FakeControl()),
      ),
      positionStream: positionController.stream,
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

      // Le cooldown écoulé, un relevé toujours hors trace redemande un
      // itinéraire : la déviation continue de retenter tant qu'elle
      // persiste, elle ne s'arme plus seulement sur le front montant.
      await Future<void>.delayed(const Duration(seconds: 21));
      positionController.add(_gps(const LatLng(44.002, 6.0), s: 4));
      await Future<void>.delayed(Duration.zero);

      expect(routing.calls, 3);
    },
    timeout: const Timeout(Duration(seconds: 40)),
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
}
