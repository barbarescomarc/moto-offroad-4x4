// test/services/routing_service_test.dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:moto_offroad/models/route_result.dart';
import 'package:moto_offroad/services/routing_service.dart';

const _sampleOrsResponse = '''
{
  "features": [
    {
      "geometry": {
        "coordinates": [[6.0, 44.0], [6.005, 44.005], [6.01, 44.01]]
      },
      "properties": {
        "summary": {"distance": 1500.0, "duration": 300.0},
        "segments": [
          {
            "distance": 1500.0,
            "duration": 300.0,
            "steps": [
              {"distance": 800.0, "duration": 150.0, "type": 11, "instruction": "Partez", "way_points": [0, 1]},
              {"distance": 700.0, "duration": 150.0, "type": 1, "instruction": "Tournez à droite", "way_points": [1, 2]},
              {"distance": 0.0, "duration": 0.0, "type": 10, "instruction": "Arrivée", "way_points": [2, 2]}
            ]
          }
        ]
      }
    }
  ]
}
''';

void main() {
  group('fetchRoute', () {
    test('parse une réponse ORS valide en RouteResult', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, contains('driving-car'));
        return http.Response(_sampleOrsResponse, 200);
      });
      final service = RoutingService(client: client);

      final result = await service.fetchRoute(
        origin: const LatLng(44.0, 6.0),
        destination: const LatLng(44.01, 6.01),
        profile: RoutingProfile.drivingCar,
      );

      expect(result.polyline.length, 3);
      expect(result.polyline.first, const LatLng(44.0, 6.0));
      expect(result.steps.length, 3);
      expect(result.steps[1].maneuver, ManeuverType.turnRight);
      expect(result.totalDistanceMeters, 1500.0);
    });

    test('envoie les avoid_features demandés', () async {
      late Map<String, dynamic> sentBody;
      final client = MockClient((request) async {
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(_sampleOrsResponse, 200);
      });
      final service = RoutingService(client: client);

      await service.fetchRoute(
        origin: const LatLng(44.0, 6.0),
        destination: const LatLng(44.01, 6.01),
        profile: RoutingProfile.drivingCar,
        avoid: {AvoidFeature.highways, AvoidFeature.tollways},
      );

      final avoidFeatures = (sentBody['options'] as Map<String, dynamic>)['avoid_features'] as List;
      expect(avoidFeatures, containsAll(['highways', 'tollways']));
    });

    test('utilise le profil cycling-mountain en offroad', () async {
      final client = MockClient((request) async {
        expect(request.url.path, contains('cycling-mountain'));
        return http.Response(_sampleOrsResponse, 200);
      });
      final service = RoutingService(client: client);

      await service.fetchRoute(
        origin: const LatLng(44.0, 6.0),
        destination: const LatLng(44.01, 6.01),
        profile: RoutingProfile.cyclingMountain,
      );
    });

    test('lève RoutingException sur erreur réseau', () async {
      final client = MockClient((request) async => throw Exception('pas de réseau'));
      final service = RoutingService(client: client);

      expect(
        () => service.fetchRoute(
          origin: const LatLng(44.0, 6.0),
          destination: const LatLng(44.01, 6.01),
          profile: RoutingProfile.drivingCar,
        ),
        throwsA(isA<RoutingException>()),
      );
    });

    test('lève RoutingException sur code 429 (quota dépassé)', () async {
      final client = MockClient((request) async => http.Response('{}', 429));
      final service = RoutingService(client: client);

      expect(
        () => service.fetchRoute(
          origin: const LatLng(44.0, 6.0),
          destination: const LatLng(44.01, 6.01),
          profile: RoutingProfile.drivingCar,
        ),
        throwsA(isA<RoutingException>()),
      );
    });
  });
}
