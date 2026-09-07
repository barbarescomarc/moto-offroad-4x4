// test/services/data_tourisme_service_test.dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:moto_offroad/models/poi.dart';
import 'package:moto_offroad/services/data_tourisme_service.dart';

// Fixtures basées sur des réponses réelles de l'API (capturées en test manuel).
Map<String, dynamic> _catalogResponse(List<Map<String, dynamic>> objects) => {
      'objects': objects,
      'meta': {'total': objects.length, 'page': 1, 'page_size': 50, 'total_pages': 1},
    };

Map<String, dynamic> _place({
  required String uuid,
  required String nameFr,
  required List<String> types,
  required double lat,
  required double lon,
  String? street,
  String? locality,
  String? phone,
  String? website,
}) =>
    {
      'label': {'@fr': nameFr, '@en': nameFr},
      'type': types,
      'uuid': uuid,
      'isLocatedAt': [
        {
          'geo': {'latitude': lat, 'longitude': lon},
          if (street != null || locality != null)
            'address': [
              {
                if (street != null) 'streetAddress': [street],
                if (locality != null) 'addressLocality': locality,
              },
            ],
        },
      ],
      if (phone != null || website != null)
        'hasContact': [
          {
            if (phone != null) 'telephone': [phone],
            if (website != null) 'homepage': [website],
          },
        ],
    };

void main() {
  const position = LatLng(45.1885, 5.7245);

  group('searchAround', () {
    test('parse un point de vue avec adresse et contact', () async {
      final body = jsonEncode(_catalogResponse([
        _place(
          uuid: 'a1',
          nameFr: 'Vallon de Combeau',
          types: ['Landform', 'PointOfInterest', 'PointOfView', 'NaturalHeritage'],
          lat: 44.774676,
          lon: 5.573502,
          street: 'Suivre direction Col de Ménée',
          locality: 'Châtillon-en-Diois',
          phone: '+33 4 75 21 10 07',
        ),
      ]));
      final service = DataTourismeService(client: MockClient((_) async => http.Response(body, 200)));

      final results = await service.searchAround(
        position, radiusKm: 20, categories: {PoiCategory.viewpoint},
      );

      expect(results, hasLength(1));
      expect(results.first.id, 'a1');
      expect(results.first.name, 'Vallon de Combeau');
      expect(results.first.category, PoiCategory.viewpoint);
      expect(results.first.position, const LatLng(44.774676, 5.573502));
      expect(results.first.address, contains('Châtillon-en-Diois'));
      expect(results.first.phone, '+33 4 75 21 10 07');
    });

    test('un site tagué Camping est reclassé en camping même trouvé via une autre catégorie', () async {
      final body = jsonEncode(_catalogResponse([
        _place(
          uuid: 'c1',
          nameFr: 'Camping le Vercors',
          types: ['Camping', 'CampingAndCaravanning', 'Accommodation', 'PlaceOfInterest'],
          lat: 45.17, lon: 5.54,
        ),
      ]));
      final service = DataTourismeService(client: MockClient((_) async => http.Response(body, 200)));

      // Recherché via le filtre "hébergements" (Guesthouse), mais taggé Camping.
      final results = await service.searchAround(
        position, radiusKm: 20, categories: {PoiCategory.guestHouse},
      );

      expect(results, hasLength(1));
      expect(results.first.category, PoiCategory.camping);
    });

    test('la catégorie hébergements interroge aussi les campings systématiquement', () async {
      var callCount = 0;
      final types = <String>[];
      final service = DataTourismeService(client: MockClient((request) async {
        callCount++;
        final type = request.url.queryParameters['filters'];
        types.add(type ?? '');
        return http.Response(jsonEncode(_catalogResponse(const [])), 200);
      }));

      await service.searchAround(position, radiusKm: 20, categories: {PoiCategory.guestHouse});

      expect(callCount, 2);
      expect(types, containsAll(['type=Guesthouse', 'type=Camping']));
    });

    test('dédoublonne les résultats par identifiant entre catégories', () async {
      final shared = _place(
        uuid: 'dup1', nameFr: 'Site partagé',
        types: ['CulturalSite', 'PointOfView'],
        lat: 45.1, lon: 5.7,
      );
      final service = DataTourismeService(client: MockClient((_) async =>
          http.Response(jsonEncode(_catalogResponse([shared])), 200)));

      final results = await service.searchAround(
        position, radiusKm: 20, categories: {PoiCategory.viewpoint, PoiCategory.heritage},
      );

      expect(results, hasLength(1));
    });

    test('une réponse HTTP en erreur pour une catégorie n\'empêche pas les autres', () async {
      final service = DataTourismeService(client: MockClient((request) async {
        if (request.url.queryParameters['filters'] == 'type=PointOfView') {
          return http.Response('', 500);
        }
        return http.Response(jsonEncode(_catalogResponse([
          _place(uuid: 'ok1', nameFr: 'Site culturel', types: ['CulturalSite'], lat: 45.1, lon: 5.7),
        ])), 200);
      }));

      final results = await service.searchAround(
        position, radiusKm: 20, categories: {PoiCategory.viewpoint, PoiCategory.heritage},
      );

      expect(results, hasLength(1));
      expect(results.first.id, 'ok1');
    });

    test('renvoie une liste vide sans lever d\'exception en cas de panne réseau', () async {
      final service = DataTourismeService(client: MockClient((_) async => throw Exception('offline')));

      final results = await service.searchAround(
        position, radiusKm: 20, categories: {PoiCategory.viewpoint},
      );

      expect(results, isEmpty);
    });
  });

  group('searchAlongRoute', () {
    test('échantillonne le tracé tous les [radiusKm] et fusionne les résultats', () async {
      // Ligne droite plein nord sur ~40 km (0,36° de latitude ≈ 40 km).
      final polyline = [
        const LatLng(44.0, 6.0),
        const LatLng(44.18, 6.0),
        const LatLng(44.36, 6.0),
      ];
      final calledPositions = <String>[];
      final service = DataTourismeService(client: MockClient((request) async {
        calledPositions.add(request.url.queryParameters['geo_distance'] ?? '');
        return http.Response(jsonEncode(_catalogResponse(const [])), 200);
      }));

      await service.searchAlongRoute(polyline, radiusKm: 20, categories: {PoiCategory.viewpoint});

      // Au moins un échantillon au départ et un à l'arrivée : la route fait
      // ~40 km, largement plus que les 20 km d'un seul disque de recherche.
      expect(calledPositions.length, greaterThanOrEqualTo(2));
      expect(calledPositions.first, startsWith('44.0,6.0'));
    });
  });
}
