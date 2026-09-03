// lib/services/routing_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../config/api_keys.dart';
import '../models/route_result.dart';

enum RoutingProfile { drivingCar, cyclingMountain }

extension RoutingProfileExt on RoutingProfile {
  String get orsId {
    switch (this) {
      case RoutingProfile.drivingCar:      return 'driving-car';
      case RoutingProfile.cyclingMountain: return 'cycling-mountain';
    }
  }
}

enum AvoidFeature { highways, tollways, ferries }

extension AvoidFeatureExt on AvoidFeature {
  String get orsId {
    switch (this) {
      case AvoidFeature.highways: return 'highways';
      case AvoidFeature.tollways: return 'tollways';
      case AvoidFeature.ferries:  return 'ferries';
    }
  }
}

class RoutingException implements Exception {
  final String message;
  const RoutingException(this.message);
  @override
  String toString() => message;
}

class RoutingService {
  final http.Client _client;
  RoutingService({http.Client? client}) : _client = client ?? http.Client();

  Future<RouteResult> fetchRoute({
    required LatLng origin,
    required LatLng destination,
    required RoutingProfile profile,
    Set<AvoidFeature> avoid = const {},
  }) async {
    final uri = Uri.parse(
        'https://api.openrouteservice.org/v2/directions/${profile.orsId}/geojson');

    final body = <String, dynamic>{
      'coordinates': [
        [origin.longitude, origin.latitude],
        [destination.longitude, destination.latitude],
      ],
      'instructions': true,
      'language': 'fr',
      if (avoid.isNotEmpty)
        'options': {'avoid_features': avoid.map((a) => a.orsId).toList()},
    };

    http.Response resp;
    try {
      resp = await _client
          .post(
            uri,
            headers: {
              'Authorization': ApiKeys.openRouteServiceApiKey,
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const RoutingException(
          "Impossible de calculer l'itinéraire — vérifie ta connexion");
    }

    if (resp.statusCode == 429) {
      throw const RoutingException('Service de guidage indisponible, réessaie plus tard');
    }
    if (resp.statusCode != 200) {
      throw const RoutingException("Impossible de calculer l'itinéraire");
    }

    return _parse(resp.body);
  }

  RouteResult _parse(String rawBody) {
    final json = jsonDecode(rawBody) as Map<String, dynamic>;
    final feature = (json['features'] as List<dynamic>).first as Map<String, dynamic>;

    final geometry = feature['geometry'] as Map<String, dynamic>;
    final coords = geometry['coordinates'] as List<dynamic>;
    final polyline = coords
        .map((c) => LatLng((c as List)[1] as double, (c[0] as num).toDouble()))
        .toList();

    final properties = feature['properties'] as Map<String, dynamic>;
    final summary = properties['summary'] as Map<String, dynamic>;
    final segments = properties['segments'] as List<dynamic>;

    final steps = <RouteStep>[];
    for (final segment in segments) {
      final segSteps = (segment as Map<String, dynamic>)['steps'] as List<dynamic>;
      for (final s in segSteps) {
        final step = s as Map<String, dynamic>;
        final wayPoints = step['way_points'] as List<dynamic>;
        final pointIndex = (wayPoints.first as num).toInt().clamp(0, polyline.length - 1);
        steps.add(RouteStep(
          instruction:    step['instruction'] as String,
          distanceMeters: (step['distance'] as num).toDouble(),
          maneuver:       _maneuverFromOrsType((step['type'] as num).toInt()),
          location:       polyline[pointIndex],
        ));
      }
    }

    return RouteResult(
      polyline: polyline,
      steps: steps,
      totalDistanceMeters:  (summary['distance'] as num).toDouble(),
      totalDurationSeconds: (summary['duration'] as num).toDouble(),
    );
  }

  // Codes de manœuvre ORS — slight/keep sont regroupés avec le virage
  // correspondant pour rester sur l'ensemble d'instructions déjà utilisé
  // par le mode GPX (voir gpx_route_deriver.dart).
  ManeuverType _maneuverFromOrsType(int type) {
    switch (type) {
      case 0: case 4: case 12: return ManeuverType.turnLeft;
      case 1: case 5: case 13: return ManeuverType.turnRight;
      case 2:  return ManeuverType.sharpLeft;
      case 3:  return ManeuverType.sharpRight;
      case 9:  return ManeuverType.uturn;
      case 10: return ManeuverType.arrive;
      case 11: return ManeuverType.depart;
      default: return ManeuverType.straight;
    }
  }
}
