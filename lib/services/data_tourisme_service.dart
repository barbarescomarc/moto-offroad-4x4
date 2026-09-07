// lib/services/data_tourisme_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../config/api_keys.dart';
import '../models/poi.dart';

// Types DATAtourisme (ontologie officielle) associés à chaque catégorie
// affichée par l'app — vérifiés par appel réel à l'API, la doc publique ne
// donnant pas la liste exacte des noms de classe.
const Map<PoiCategory, String> _apiTypeFor = {
  PoiCategory.viewpoint:   'PointOfView',
  PoiCategory.guestHouse:  'Guesthouse',
  PoiCategory.naturalSite: 'NaturalHeritage',
  PoiCategory.heritage:    'CulturalSite',
};

class DataTourismeService {
  DataTourismeService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String _baseUrl = 'https://api.datatourisme.fr/v1/placeOfInterest';
  static const int _pageSize = 50;

  // Recherche autour d'un point, pour les catégories demandées. Une requête
  // par catégorie : l'API ne semble pas accepter plusieurs valeurs de type
  // dans un seul filtre. Un site déjà tagué "Camping" (type DATAtourisme
  // dédié) est reclassé dans la catégorie camping de l'app plutôt que
  // hébergement — sur demande explicite : les campings ne doivent jamais se
  // perdre dans la catégorie "hébergements".
  Future<List<PoiModel>> searchAround(
    LatLng point, {
    required double radiusKm,
    required Set<PoiCategory> categories,
  }) async {
    final byId = <String, PoiModel>{};

    for (final category in categories) {
      final apiType = _apiTypeFor[category];
      if (apiType == null) continue;
      await _fetchType(point, radiusKm, apiType, category, byId);

      // Hébergements : on va aussi chercher les campings, systématiquement,
      // rangés dans la catégorie camping existante de l'app.
      if (category == PoiCategory.guestHouse) {
        await _fetchType(point, radiusKm, 'Camping', PoiCategory.camping, byId);
      }
    }

    return byId.values.toList();
  }

  // Variante « le long de la route » : l'API ne sait interroger qu'un
  // disque autour d'un point, pas un corridor. On échantillonne le tracé
  // tous les [radiusKm] (les disques successifs se recouvrent alors sans
  // laisser de trou) et on fusionne les résultats par identifiant.
  Future<List<PoiModel>> searchAlongRoute(
    List<LatLng> polyline, {
    required double radiusKm,
    required Set<PoiCategory> categories,
  }) async {
    final samples = _sampleAlongPolyline(polyline, radiusKm);
    final byId = <String, PoiModel>{};

    for (final point in samples) {
      final found = await searchAround(point, radiusKm: radiusKm, categories: categories);
      for (final poi in found) {
        byId[poi.id] = poi;
      }
    }
    return byId.values.toList();
  }

  List<LatLng> _sampleAlongPolyline(List<LatLng> polyline, double intervalKm) {
    if (polyline.isEmpty) return const [];
    if (polyline.length == 1) return polyline;

    const calc = Distance();
    final intervalMeters = intervalKm * 1000;
    final samples = <LatLng>[polyline.first];
    double sinceLastSample = 0;

    for (var i = 1; i < polyline.length; i++) {
      sinceLastSample += calc(polyline[i - 1], polyline[i]);
      if (sinceLastSample >= intervalMeters) {
        samples.add(polyline[i]);
        sinceLastSample = 0;
      }
    }
    if (samples.last != polyline.last) samples.add(polyline.last);
    return samples;
  }

  Future<void> _fetchType(
    LatLng point,
    double radiusKm,
    String apiType,
    PoiCategory category,
    Map<String, PoiModel> byId,
  ) async {
    try {
      final uri = Uri.parse(_baseUrl).replace(queryParameters: {
        'geo_distance': '${point.latitude},${point.longitude},${radiusKm}km',
        'filters': 'type=$apiType',
        'page_size': '$_pageSize',
      });
      final response = await _client
          .get(uri, headers: {'X-API-Key': ApiKeys.dataTourismeApiKey})
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final objects = data['objects'] as List<dynamic>? ?? [];
      for (final raw in objects) {
        final poi = _parsePoi(raw as Map<String, dynamic>, category);
        if (poi != null) byId[poi.id] = poi;
      }
    } catch (_) {
      // Pas de réseau ou service indisponible : cette catégorie reste
      // simplement absente du résultat, sans faire échouer toute la
      // recherche.
    }
  }

  PoiModel? _parsePoi(Map<String, dynamic> raw, PoiCategory category) {
    final id = raw['uuid'] as String?;
    if (id == null) return null;

    final locations = raw['isLocatedAt'] as List<dynamic>?;
    if (locations == null || locations.isEmpty) return null;
    final geo = (locations.first as Map<String, dynamic>)['geo'] as Map<String, dynamic>?;
    final lat = (geo?['latitude'] as num?)?.toDouble();
    final lon = (geo?['longitude'] as num?)?.toDouble();
    if (lat == null || lon == null) return null;

    // Un site tagué "Camping" reste catégorisé camping même s'il a été
    // trouvé via une autre requête que la sienne.
    final types = (raw['type'] as List<dynamic>?)?.cast<String>() ?? const [];
    final resolvedCategory = types.contains('Camping') ? PoiCategory.camping : category;

    final label = raw['label'] as Map<String, dynamic>?;
    final name = (label?['@fr'] ?? label?['@en'] ?? 'Sans nom') as String;

    final address = (locations.first as Map<String, dynamic>)['address'] as List<dynamic>?;
    final addressLabel = address != null && address.isNotEmpty
        ? _formatAddress(address.first as Map<String, dynamic>)
        : null;

    final contacts = raw['hasContact'] as List<dynamic>?;
    String? phone;
    String? website;
    if (contacts != null && contacts.isNotEmpty) {
      final contact = contacts.first as Map<String, dynamic>;
      phone = (contact['telephone'] as List<dynamic>?)?.cast<String>().firstOrNull;
      website = (contact['homepage'] as List<dynamic>?)?.cast<String>().firstOrNull;
    }

    return PoiModel(
      id: id,
      name: name,
      category: resolvedCategory,
      position: LatLng(lat, lon),
      address: addressLabel,
      phone: phone,
      website: website,
    );
  }

  String? _formatAddress(Map<String, dynamic> address) {
    final street = (address['streetAddress'] as List<dynamic>?)?.cast<String>().firstOrNull;
    final locality = address['addressLocality'] as String?;
    if (street != null && locality != null) return '$street, $locality';
    return locality ?? street;
  }

  void dispose() => _client.close();
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
