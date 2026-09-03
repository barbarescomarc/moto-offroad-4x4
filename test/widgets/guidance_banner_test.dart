// test/widgets/guidance_banner_test.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moto_offroad/models/trace.dart';
import 'package:moto_offroad/providers/guidance_provider.dart';
import 'package:moto_offroad/providers/settings_provider.dart';
import 'package:moto_offroad/models/route_result.dart';
import 'package:moto_offroad/services/guidance_background_client.dart';
import 'package:moto_offroad/services/guidance_voice_service.dart';
import 'package:moto_offroad/services/location_service.dart';
import 'package:moto_offroad/services/routing_service.dart';
import 'package:moto_offroad/widgets/guidance_banner.dart';

class _MockGuidanceBackgroundClient extends GuidanceBackgroundClient {
  @override
  Future<void> start(String message) async {}

  @override
  Future<void> stop() async {}
}

// Itinéraire de 800 m parcouru en 600 s, en deux segments égaux : à la
// charnière, il reste exactement la moitié du trajet, donc 5 min.
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

class _FakeRoutingService extends RoutingService {
  @override
  Future<RouteResult> fetchRoute({
    required LatLng origin,
    required LatLng destination,
    required RoutingProfile profile,
    Set<AvoidFeature> avoid = const {},
  }) async => _twoSegmentRoute();
}

class _SilentTtsEngine implements TtsEngine {
  @override
  Future<void> setLanguage(String lang) async {}
  @override
  Future<void> speak(String text) async {}
  @override
  Future<void> stop() async {}
}

GpsSnapshot _gps(LatLng pos) => GpsSnapshot(
  position:       pos,
  accuracyMeters: 4,
  altitudeMeters: 300,
  speedKmh:       20,
  headingDeg:     0,
  timestamp:      DateTime(2026, 9, 3, 10),
);

TraceModel _straightTrace() => TraceModel(
  id: 't1', name: 'test',
  points: [
    TracePoint(position: const LatLng(44.0, 6.0)),
    TracePoint(position: const LatLng(44.01, 6.0)),
  ],
);

Future<void> _pump(
  WidgetTester tester,
  GuidanceProvider guidance, {
  SettingsProvider? settings,
}) {
  return tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: guidance),
        ChangeNotifierProvider.value(value: settings ?? SettingsProvider()),
      ],
      child: const MaterialApp(home: Scaffold(body: GuidanceBanner())),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('n\'affiche rien quand le guidage est inactif', (tester) async {
    final guidance = GuidanceProvider(
      positionStream: const Stream.empty(),
      backgroundClient: _MockGuidanceBackgroundClient(),
    );
    await _pump(tester, guidance);
    expect(find.byType(GuidanceBanner), findsOneWidget);
    expect(find.text('Suivi de la trace'), findsNothing);
  });

  testWidgets('affiche l\'instruction en mode alerte GPX', (tester) async {
    final guidance = GuidanceProvider(
      positionStream: const Stream.empty(),
      backgroundClient: _MockGuidanceBackgroundClient(),
    );
    guidance.startOnTrace(_straightTrace(), GuidanceMode.gpxAlert);
    await _pump(tester, guidance);
    expect(find.text('Suivi de la trace'), findsOneWidget);
    guidance.stop();
    await tester.pumpAndSettle();
  });

  testWidgets('le bouton mute appelle toggleMute', (tester) async {
    final guidance = GuidanceProvider(
      positionStream: const Stream.empty(),
      backgroundClient: _MockGuidanceBackgroundClient(),
    );
    guidance.startOnTrace(_straightTrace(), GuidanceMode.gpxAlert);
    await _pump(tester, guidance);

    expect(guidance.isMuted, isFalse);
    await tester.tap(find.byIcon(Icons.volume_up));
    await tester.pump();
    expect(guidance.isMuted, isTrue);
    guidance.stop();
    await tester.pumpAndSettle();
  });

  testWidgets('le bouton mute persiste le choix dans les réglages', (tester) async {
    final guidance = GuidanceProvider(
      positionStream: const Stream.empty(),
      backgroundClient: _MockGuidanceBackgroundClient(),
    );
    final settings = SettingsProvider();
    await settings.load();
    guidance.startOnTrace(_straightTrace(), GuidanceMode.gpxAlert);
    await _pump(tester, guidance, settings: settings);

    await tester.tap(find.byIcon(Icons.volume_up));
    await tester.pumpAndSettle();

    expect(settings.guidanceVoiceMuted, isTrue);
    guidance.stop();
    await tester.pumpAndSettle();
  });

  testWidgets('affiche la distance restante et l\'ETA en mode destination', (tester) async {
    final positions = StreamController<GpsSnapshot>.broadcast();
    addTearDown(positions.close);
    final guidance = GuidanceProvider(
      routingService: _FakeRoutingService(),
      voiceService: GuidanceVoiceService(engine: _SilentTtsEngine()),
      positionStream: positions.stream,
      backgroundClient: _MockGuidanceBackgroundClient(),
    );
    await guidance.startToDestination(
      origin: const LatLng(44.0, 6.0),
      destination: const LatLng(44.0, 6.01),
      profile: RoutingProfile.drivingCar,
    );

    // À mi-parcours : 0,4 km restants sur 0,8 km, soit la moitié des 600 s.
    positions.add(_gps(const LatLng(44.0, 6.006)));
    await tester.pump();
    await _pump(tester, guidance);

    expect(find.text('0.4 km restants'), findsOneWidget);
    expect(find.text('5 min'), findsOneWidget);
    guidance.stop();
    await tester.pumpAndSettle();
  });

  testWidgets('aucune ETA affichée sur un guidage de trace GPX', (tester) async {
    final guidance = GuidanceProvider(
      positionStream: const Stream.empty(),
      backgroundClient: _MockGuidanceBackgroundClient(),
    );
    guidance.startOnTrace(_straightTrace(), GuidanceMode.gpxAlert);
    await _pump(tester, guidance);

    expect(find.textContaining('min'), findsNothing);
    guidance.stop();
    await tester.pumpAndSettle();
  });

  testWidgets('le bouton fermer appelle stop', (tester) async {
    final guidance = GuidanceProvider(
      positionStream: const Stream.empty(),
      backgroundClient: _MockGuidanceBackgroundClient(),
    );
    guidance.startOnTrace(_straightTrace(), GuidanceMode.gpxAlert);
    await _pump(tester, guidance);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(guidance.isActive, isFalse);
  });
}
