// lib/services/speed_limit_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../utils/route_geometry.dart';

// Limite de vitesse par tronçon (tag OSM maxspeed), via Overpass — aucune
// route ORS n'en connaît, et aucune base embarquée n'existe dans l'app.
class SpeedLimitService {
  SpeedLimitService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  // Rayon (m) de la requête Overpass autour de la position.
  static const double _queryRadiusMeters = 150;
  // Au-delà de cette distance à la route la plus proche, on ne retient plus
  // aucune limite : mieux vaut ne rien afficher qu'une valeur qui ne
  // correspond pas à la route réellement empruntée.
  static const double _maxMatchDistanceMeters = 40;

  Future<double?> fetchSpeedLimitKmh(LatLng position) async {
    final query = '[out:json][timeout:10];'
        'way(around:$_queryRadiusMeters,${position.latitude},${position.longitude})'
        '[highway][maxspeed];out geom;';

    try {
      final response = await _client
          .post(
            Uri.parse('https://overpass-api.de/api/interpreter'),
            body: {'data': query},
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      return _nearestSpeedLimit(position, jsonDecode(response.body) as Map<String, dynamic>);
    } catch (_) {
      // Pas de réseau ou service indisponible : la limite reste simplement
      // inconnue, sans faire planter le guidage.
      return null;
    }
  }

  double? _nearestSpeedLimit(LatLng position, Map<String, dynamic> data) {
    final elements = data['elements'] as List<dynamic>? ?? [];
    double? bestDistance;
    double? bestLimit;

    for (final element in elements) {
      final way = element as Map<String, dynamic>;
      final tags = way['tags'] as Map<String, dynamic>?;
      final limit = _parseMaxspeed(tags?['maxspeed'] as String?);
      if (limit == null) continue;

      final geometry = (way['geometry'] as List<dynamic>?)
          ?.map((p) => LatLng(
                ((p as Map<String, dynamic>)['lat'] as num).toDouble(),
                (p['lon'] as num).toDouble(),
              ))
          .toList();
      if (geometry == null || geometry.length < 2) continue;

      final distance = distanceToPolyline(position, geometry);
      if (distance > _maxMatchDistanceMeters) continue;
      if (bestDistance == null || distance < bestDistance) {
        bestDistance = distance;
        bestLimit = limit;
      }
    }
    return bestLimit;
  }

  // Seules les valeurs numériques pures (ex. "50") sont fiables : le tag OSM
  // maxspeed porte aussi des unités ("50 mph") ou des catégories
  // ("FR:urban") qu'on ne cherche pas à interpréter ici.
  double? _parseMaxspeed(String? raw) {
    if (raw == null || !RegExp(r'^\d+$').hasMatch(raw)) return null;
    return double.parse(raw);
  }

  void dispose() => _client.close();
}
