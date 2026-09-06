// lib/services/speed_camera_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

// Radars fixes (tag OSM highway=speed_camera), via Overpass — maintenu par
// la communauté, pas un fichier officiel : couverture correcte sur les
// grands axes, mais incomplète. Ne renvoie jamais de position exacte à
// l'affichage : voir GuidanceProvider pour la transformation en "zone de
// contrôle possible", seule formulation légale en France (décret du 3
// janvier 2012).
class SpeedCameraService {
  SpeedCameraService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  // Rayon (m) de la requête Overpass — couvre la plus grande distance de
  // pré-alerte utilisée (autoroute, 4 km), avec une marge.
  static const double _queryRadiusMeters = 4500;

  Future<List<LatLng>> fetchNearbyCameras(LatLng position) async {
    final query = '[out:json][timeout:15];'
        'node(around:$_queryRadiusMeters,${position.latitude},${position.longitude})'
        '[highway=speed_camera];out;';

    try {
      final response = await _client
          .post(
            Uri.parse('https://overpass-api.de/api/interpreter'),
            body: {'data': query},
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final elements = data['elements'] as List<dynamic>? ?? [];
      return elements
          .map((e) => e as Map<String, dynamic>)
          .where((e) => e['lat'] != null && e['lon'] != null)
          .map((e) => LatLng((e['lat'] as num).toDouble(), (e['lon'] as num).toDouble()))
          .toList();
    } catch (_) {
      // Pas de réseau ou service indisponible : aucune alerte plutôt qu'un
      // crash du guidage.
      return [];
    }
  }

  void dispose() => _client.close();
}
