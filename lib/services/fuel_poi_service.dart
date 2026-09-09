// lib/services/fuel_poi_service.dart
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../models/poi.dart';

// Overpass n'a pas répondu : réseau absent, service indisponible ou saturé.
// Distingué d'une liste vide à dessein — « aucune station ici » et « je n'ai
// pas pu demander » n'appellent pas la même conduite du pilote.
class FuelPoiUnavailable implements Exception {
  const FuelPoiUnavailable();
}

// Stations-service (amenity=fuel) et réparateurs moto (shop=motorcycle) via
// Overpass, comme le font déjà SpeedCameraService et SpeedLimitService.
// Données OpenStreetMap : très bonnes en ville, inégales en campagne — c'est
// justement là que roule le pilote, donc l'absence de résultat ne prouve
// jamais l'absence de station.
class FuelPoiService {
  FuelPoiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<List<PoiModel>> fetchAround(LatLng center, {required int radiusKm}) async {
    final rayonMetres = radiusKm * 1000;
    final autour = 'around:$rayonMetres,${center.latitude},${center.longitude}';
    // `nwr` et `out center` plutôt que `node` seul : beaucoup de stations sont
    // cartographiées comme surfaces, et seraient invisibles autrement.
    final query = '[out:json][timeout:15];'
        '(nwr($autour)[amenity=fuel];'
        'nwr($autour)[shop=motorcycle];);'
        'out center;';

    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('https://overpass-api.de/api/interpreter'),
            body: {'data': query},
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const FuelPoiUnavailable();
    }
    if (response.statusCode != 200) throw const FuelPoiUnavailable();

    final Map<String, dynamic> data;
    try {
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw const FuelPoiUnavailable();
    }
    final elements = data['elements'] as List<dynamic>? ?? [];

    return elements
        .map((e) => e as Map<String, dynamic>)
        .map(_toPoi)
        .whereType<PoiModel>()
        .toList();
  }

  PoiModel? _toPoi(Map<String, dynamic> element) {
    final tags = element['tags'] as Map<String, dynamic>? ?? const {};
    final category = tags['amenity'] == 'fuel'
        ? PoiCategory.gasStation
        : tags['shop'] == 'motorcycle'
            ? PoiCategory.motoShop
            : null;
    if (category == null) return null;

    // Un point porte ses coordonnées ; une surface ne donne que son centre.
    final centre = element['center'] as Map<String, dynamic>?;
    final lat = element['lat'] as num? ?? centre?['lat'] as num?;
    final lon = element['lon'] as num? ?? centre?['lon'] as num?;
    if (lat == null || lon == null) return null;

    return PoiModel(
      id: '${element['type']}/${element['id']}',
      name: tags['name'] as String? ?? category.label,
      category: category,
      position: LatLng(lat.toDouble(), lon.toDouble()),
    );
  }

  void dispose() => _client.close();
}
