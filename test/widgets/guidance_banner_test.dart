// test/widgets/guidance_banner_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:moto_offroad/models/trace.dart';
import 'package:moto_offroad/providers/guidance_provider.dart';
import 'package:moto_offroad/services/guidance_background_client.dart';
import 'package:moto_offroad/widgets/guidance_banner.dart';

class _MockGuidanceBackgroundClient extends GuidanceBackgroundClient {
  @override
  Future<void> start(String message) async {}

  @override
  Future<void> stop() async {}
}

TraceModel _straightTrace() => TraceModel(
  id: 't1', name: 'test',
  points: [
    TracePoint(position: const LatLng(44.0, 6.0)),
    TracePoint(position: const LatLng(44.01, 6.0)),
  ],
);

Future<void> _pump(WidgetTester tester, GuidanceProvider guidance) {
  return tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: guidance,
      child: const MaterialApp(home: Scaffold(body: GuidanceBanner())),
    ),
  );
}

void main() {
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
