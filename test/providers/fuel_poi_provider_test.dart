import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:moto_offroad/providers/fuel_poi_provider.dart';
import 'package:moto_offroad/services/fuel_poi_service.dart';

const _toulouse = LatLng(43.6045, 1.4442);

FuelPoiProvider _provider(http.Client client) =>
    FuelPoiProvider(service: FuelPoiService(client: client));

http.Client _repond(List<Map<String, dynamic>> elements) =>
    MockClient((_) async => http.Response(jsonEncode({'elements': elements}), 200));

final _uneStation = <Map<String, dynamic>>[
  {
    'type': 'node',
    'id': 1,
    'lat': 43.61,
    'lon': 1.45,
    'tags': {'amenity': 'fuel', 'name': 'Station du Nord'},
  },
];

void main() {
  test('une recherche reussie pose les resultats et retombe le chargement', () async {
    final p = _provider(_repond(_uneStation));

    final recherche = p.searchAround(_toulouse, radiusKm: 20);
    expect(p.loading, isTrue);
    await recherche;

    expect(p.loading, isFalse);
    expect(p.results, hasLength(1));
    expect(p.unavailable, isFalse);
  });

  test('une panne signale l indisponibilite plutot que zero station', () async {
    final p = _provider(MockClient((_) async => throw Exception('reseau coupe')));

    await p.searchAround(_toulouse, radiusKm: 20);

    expect(p.unavailable, isTrue);
    expect(p.results, isEmpty);
    expect(p.loading, isFalse);
  });

  test('une recherche reussie efface une indisponibilite precedente', () async {
    var enPanne = true;
    final p = _provider(MockClient((_) async {
      if (enPanne) throw Exception('reseau coupe');
      return http.Response(jsonEncode({'elements': _uneStation}), 200);
    }));

    await p.searchAround(_toulouse, radiusKm: 20);
    expect(p.unavailable, isTrue);

    enPanne = false;
    await p.searchAround(_toulouse, radiusKm: 20);

    expect(p.unavailable, isFalse, reason: 'une erreur remanente ferait croire a une panne permanente');
    expect(p.results, hasLength(1));
  });
}
