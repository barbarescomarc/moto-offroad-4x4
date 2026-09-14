// lib/services/routing_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../config/api_keys.dart';
import '../models/route_result.dart';
import '../models/vehicle_kind.dart';

enum RoutingProfile { drivingCar, cyclingMountain, drivingHgv }

extension RoutingProfileExt on RoutingProfile {
  String get orsId {
    switch (this) {
      case RoutingProfile.drivingCar:      return 'driving-car';
      case RoutingProfile.cyclingMountain: return 'cycling-mountain';
      case RoutingProfile.drivingHgv:      return 'driving-hgv';
    }
  }

  /// L'itinéraire suit-il des routes ouvertes, par opposition aux pistes ?
  ///
  /// Décide de la tolérance avant de déclarer le pilote sorti de route : sur
  /// bitume, quelques dizaines de mètres d'écart veulent dire qu'on a raté un
  /// virage ; sur piste, c'est le GPS qui dérive.
  bool get suitLaRoute => this != RoutingProfile.cyclingMountain;

  /// Seul ce profil accepte des restrictions de gabarit côté ORS : demander à
  /// `driving-car` d'éviter les ponts bas fait rejeter la requête entière.
  bool get accepteGabarit => this == RoutingProfile.drivingHgv;
}

/// Le profil ORS à demander pour ce véhicule dans ce mode de navigation.
///
/// ORS n'a pas de profil « 4x4 » dédié : hors du mode hors-route, un véhicule
/// à quatre roues reprend le profil route, seul à couvrir les pistes qu'il
/// peut carrosser.
///
/// Le camping-car passe par le profil poids lourd, le seul qu'ORS laisse
/// contraindre en hauteur, longueur et tonnage. Il n'en sort que si son
/// pilote a ouvert la piste dans les Réglages — les fourgons 4x4 existent.
/// Sur piste, le gabarit cesse d'être transmis : ORS rejette la requête
/// entière si on le joint à un autre profil que le poids lourd. C'est le prix
/// assumé d'aller là où un porteur de 3,5 t ne va pas, et le réglage le dit.
RoutingProfile profilItineraire({
  required VehicleKind vehicule,
  required bool modeHorsRoute,
  required bool autoriseHorsRoute,
}) {
  if (modeHorsRoute && autoriseHorsRoute) return RoutingProfile.cyclingMountain;
  if (vehicule.hasGabarit) return RoutingProfile.drivingHgv;
  return RoutingProfile.drivingCar;
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
    GabaritVehicule? gabarit,
  }) async {
    final results = await _fetchRoutes(
      waypoints: [origin, destination], profile: profile, avoid: avoid,
      gabarit: gabarit,
    );
    return results.first;
  }

  // Jusqu'à 3 itinéraires distincts entre deux points (limite imposée par
  // ORS) — sert à choisir celui qui tourne le plus quand la préférence
  // "routes sinueuses" est active (voir routeSinuosityDegPerKm), faute
  // d'un vrai algorithme de recherche de route sinueuse côté ORS.
  Future<List<RouteResult>> fetchRouteAlternatives({
    required LatLng origin,
    required LatLng destination,
    required RoutingProfile profile,
    Set<AvoidFeature> avoid = const {},
    GabaritVehicule? gabarit,
    int targetCount = 3,
  }) =>
      _fetchRoutes(
        waypoints: [origin, destination],
        profile: profile,
        avoid: avoid,
        gabarit: gabarit,
        alternativeRoutesTargetCount: targetCount,
      );

  // Trace à main levée : autant d'étapes que de points posés sur la carte.
  // ORS accepte nativement plus de deux coordonnées — chaque paire
  // consécutive devient un « segment » dans la réponse, déjà géré par
  // _parseFeature qui les parcourt tous pour construire la liste d'étapes.
  Future<RouteResult> fetchMultiPointRoute({
    required List<LatLng> waypoints,
    required RoutingProfile profile,
    Set<AvoidFeature> avoid = const {},
    GabaritVehicule? gabarit,
  }) async {
    assert(waypoints.length >= 2, 'Il faut au moins deux points pour un itinéraire');
    final results = await _fetchRoutes(
        waypoints: waypoints, profile: profile, avoid: avoid, gabarit: gabarit);
    return results.first;
  }

  Future<List<RouteResult>> _fetchRoutes({
    required List<LatLng> waypoints,
    required RoutingProfile profile,
    required Set<AvoidFeature> avoid,
    GabaritVehicule? gabarit,
    int? alternativeRoutesTargetCount,
  }) async {
    final uri = Uri.parse(
        'https://api.openrouteservice.org/v2/directions/${profile.orsId}/geojson');

    // `avoid_features` et `profile_params` logent tous deux sous `options` :
    // on accumule, sous peine que le gabarit efface silencieusement les
    // évitements du pilote, ou l'inverse.
    final options = <String, dynamic>{
      if (avoid.isNotEmpty) 'avoid_features': avoid.map((a) => a.orsId).toList(),
      // Le gabarit n'est transmis qu'au profil qui sait le lire : ORS rejette
      // la requête entière si on le joint à `driving-car`, et un guidage
      // refusé est pire qu'un guidage sans restriction.
      if (gabarit != null && profile.accepteGabarit) ...{
        'vehicle_type': 'hgv',
        'profile_params': {'restrictions': gabarit.restrictionsOrs},
      },
    };

    final body = <String, dynamic>{
      'coordinates': waypoints.map((p) => [p.longitude, p.latitude]).toList(),
      'instructions': true,
      'language': 'fr',
      if (options.isNotEmpty) 'options': options,
      // Non cumulable avec plus de deux points ni avec les évitements selon
      // l'API ORS — n'est demandé que pour un guidage vers une destination
      // simple (voir GuidanceProvider).
      if (alternativeRoutesTargetCount != null)
        'alternative_routes': {
          'target_count': alternativeRoutesTargetCount,
          'share_factor': 0.6,
          'weight_factor': 1.4,
        },
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

    return _parseAll(resp.body);
  }

  List<RouteResult> _parseAll(String rawBody) {
    final json = jsonDecode(rawBody) as Map<String, dynamic>;
    final features = json['features'] as List<dynamic>;
    return features
        .map((f) => _parseFeature(f as Map<String, dynamic>))
        .toList();
  }

  RouteResult _parseFeature(Map<String, dynamic> feature) {
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
