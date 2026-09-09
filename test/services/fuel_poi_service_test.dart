import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:moto_offroad/models/poi.dart';
import 'package:moto_offroad/services/fuel_poi_service.dart';

const _toulouse = LatLng(43.6045, 1.4442);

String _overpassJson(List<Map<String, dynamic>> elements) =>
    jsonEncode({'elements': elements});

void main() {
  test('rend les stations et les reparateurs, chacun dans sa categorie', () async {
    final service = FuelPoiService(
      client: MockClient((_) async => http.Response(
            _overpassJson([
              {
                'type': 'node',
                'id': 1,
                'lat': 43.61,
                'lon': 1.45,
                'tags': {'amenity': 'fuel', 'name': 'Station du Nord'},
              },
              {
                'type': 'node',
                'id': 2,
                'lat': 43.59,
                'lon': 1.43,
                'tags': {'shop': 'motorcycle', 'name': 'Moto Sud'},
              },
            ]),
            200,
          )),
    );

    final resultats = await service.fetchAround(_toulouse, radiusKm: 20);

    expect(resultats, hasLength(2));
    expect(
      resultats.firstWhere((p) => p.name == 'Station du Nord').category,
      PoiCategory.gasStation,
    );
    expect(
      resultats.firstWhere((p) => p.name == 'Moto Sud').category,
      PoiCategory.motoShop,
    );
  });

  test('la requete demande aussi les surfaces, pas seulement les points', () async {
    late String envoye;
    final service = FuelPoiService(
      client: MockClient((requete) async {
        envoye = requete.bodyFields['data'] ?? '';
        return http.Response(_overpassJson([]), 200);
      }),
    );

    await service.fetchAround(_toulouse, radiusKm: 20);

    // Sans cela, Overpass ne renverrait que les stations cartographiees comme
    // points — or beaucoup le sont comme surfaces, et seraient invisibles.
    expect(envoye, contains('nwr'));
    expect(envoye, contains('out center'));
  });

  test('une station cartographiee comme surface est reconnue par son centre', () async {
    final service = FuelPoiService(
      client: MockClient((_) async => http.Response(
            _overpassJson([
              {
                'type': 'way',
                'id': 7,
                'center': {'lat': 43.62, 'lon': 1.46},
                'tags': {'amenity': 'fuel', 'name': 'Station en surface'},
              },
            ]),
            200,
          )),
    );

    final resultats = await service.fetchAround(_toulouse, radiusKm: 20);

    expect(resultats, hasLength(1));
    expect(resultats.single.position, const LatLng(43.62, 1.46));
  });

  test('une panne reseau leve, au lieu de se faire passer pour zero station', () async {
    final service = FuelPoiService(
      client: MockClient((_) async => throw Exception('reseau coupe')),
    );

    // Rendre une liste vide dirait au pilote « il n'y a rien ici » alors que
    // la question n'a jamais atteint Overpass. Il doit pouvoir reessayer.
    expect(
      () => service.fetchAround(_toulouse, radiusKm: 20),
      throwsA(isA<FuelPoiUnavailable>()),
    );
  });

  test('un refus du service leve aussi', () async {
    final service = FuelPoiService(
      client: MockClient((_) async => http.Response('rate limited', 429)),
    );

    expect(
      () => service.fetchAround(_toulouse, radiusKm: 20),
      throwsA(isA<FuelPoiUnavailable>()),
    );
  });

  test('aucune station trouvee rend une liste vide, sans lever', () async {
    final service = FuelPoiService(
      client: MockClient((_) async => http.Response(_overpassJson([]), 200)),
    );

    expect(await service.fetchAround(_toulouse, radiusKm: 20), isEmpty);
  });
}
