// lib/services/fuel_poi_service.dart
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../models/poi.dart';
import '../models/vehicle_kind.dart';
import 'overpass.dart';

// Overpass n'a pas répondu : réseau absent, service indisponible ou saturé.
// Distingué d'une liste vide à dessein — « aucune station ici » et « je n'ai
// pas pu demander » n'appellent pas la même conduite du pilote.
class FuelPoiUnavailable implements Exception {
  const FuelPoiUnavailable();
}

// Les points d'appui du véhicule via Overpass, comme le font déjà
// SpeedCameraService et SpeedLimitService. Ce qu'on cherche dépend de ce
// qu'on conduit : carburant et réparateur moto pour une moto, aires, vidange,
// eau et bornes pour un camping-car.
// Données OpenStreetMap : très bonnes en ville, inégales en campagne — c'est
// justement là que roule le pilote, donc l'absence de résultat ne prouve
// jamais l'absence de station.
class FuelPoiService {
  FuelPoiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<List<PoiModel>> fetchAround(
    LatLng center, {
    required int radiusKm,
    VehicleKind vehicule = VehicleKind.moto,
  }) async {
    final rayonMetres = radiusKm * 1000;
    final autour = 'around:$rayonMetres,${center.latitude},${center.longitude}';
    // `nwr` et `out center` plutôt que `node` seul : beaucoup de stations sont
    // cartographiées comme surfaces, et seraient invisibles autrement.
    final selecteurs = vehicule.poiCategories
        .map((c) => c.overpassSelector)
        .whereType<String>()
        .map((s) => 'nwr($autour)$s;')
        .join();
    final query = '[out:json][timeout:15];($selecteurs);out center;';

    // Overpass public est tres irregulier : la meme requete rend 200 en cinq
    // secondes, 504, ou douze secondes, selon sa charge du moment. Une seule
    // tentative transformait n'importe quel hoquet en echec definitif — d'ou
    // un unique reessai, et un delai large.
    final response = await _demander(query) ?? await _demander(query);
    if (response == null) throw const FuelPoiUnavailable();

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

  /// Une tentative. Rend `null` sur echec — reseau, refus ou 504 — pour que
  /// l'appelant decide de reessayer, plutot que de lever a la premiere alerte.
  Future<http.Response?> _demander(String query) async {
    try {
      final response = await _client
          .post(
            Uri.parse(overpassEndpoint),
            headers: const {'User-Agent': overpassUserAgent},
            body: {'data': query},
          )
          .timeout(const Duration(seconds: 30));
      return response.statusCode == 200 ? response : null;
    } catch (_) {
      return null;
    }
  }

  PoiModel? _toPoi(Map<String, dynamic> element) {
    final tags = element['tags'] as Map<String, dynamic>? ?? const {};
    final category = categorieDepuisTags(tags);
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
