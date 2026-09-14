import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:moto_offroad/models/poi.dart';
import 'package:moto_offroad/models/vehicle_kind.dart';
import 'package:moto_offroad/services/fuel_poi_service.dart';

const _pailheres = LatLng(42.7400, 1.9800);

String _overpassJson(List<Map<String, dynamic>> elements) =>
    jsonEncode({'elements': elements});

/// Capture la requête envoyée à Overpass sans y répondre quoi que ce soit.
(FuelPoiService, String Function()) _serviceEspion() {
  var envoye = '';
  final service = FuelPoiService(
    client: MockClient((requete) async {
      envoye = requete.bodyFields['data'] ?? '';
      return http.Response(_overpassJson([]), 200);
    }),
  );
  return (service, () => envoye);
}

void main() {
  group('le véhicule décide de ce qu on cherche', () {
    test('la moto cherche du carburant et un réparateur moto', () async {
      final (service, envoye) = _serviceEspion();

      await service.fetchAround(_pailheres, radiusKm: 20, vehicule: VehicleKind.moto);

      expect(envoye(), contains('[amenity=fuel]'));
      expect(envoye(), contains('[shop=motorcycle]'));
      expect(envoye(), isNot(contains('caravan_site')));
    });

    test('le camping-car cherche aires, vidange, eau et bornes', () async {
      final (service, envoye) = _serviceEspion();

      await service.fetchAround(_pailheres, radiusKm: 20, vehicule: VehicleKind.van);

      expect(envoye(), contains('[tourism=caravan_site]'));
      expect(envoye(), contains('[amenity=sanitary_dump_station]'));
      expect(envoye(), contains('[amenity=drinking_water]'));
      expect(envoye(), contains('[amenity=charging_station]'));
      expect(envoye(), contains('[amenity=fuel]'));
    });

    test('le camping-car ne demande pas de réparateur moto', () async {
      final (service, envoye) = _serviceEspion();

      await service.fetchAround(_pailheres, radiusKm: 20, vehicule: VehicleKind.van);

      // Chaque sélecteur en trop est une requête payée à un service public
      // gratuit, et autant de points sans objet posés sur la carte.
      expect(envoye(), isNot(contains('[shop=motorcycle]')));
    });

    test('le véhicule par défaut reste la moto', () async {
      final (service, envoye) = _serviceEspion();

      await service.fetchAround(_pailheres, radiusKm: 20);

      // Les installés d'avant le choix du véhicule conduisaient une moto :
      // leur application ne doit pas changer de comportement sous leurs pieds.
      expect(envoye(), contains('[shop=motorcycle]'));
    });
  });

  group('reconnaissance des points renvoyés par Overpass', () {
    test('une aire de camping-car est classée comme telle', () async {
      final service = FuelPoiService(
        client: MockClient((_) async => http.Response(
              _overpassJson([
                {
                  'type': 'node',
                  'id': 1,
                  'lat': 42.75,
                  'lon': 1.98,
                  'tags': {'tourism': 'caravan_site', 'name': 'Aire du col'},
                },
                {
                  'type': 'node',
                  'id': 2,
                  'lat': 42.74,
                  'lon': 1.97,
                  'tags': {'amenity': 'sanitary_dump_station', 'name': 'Vidange'},
                },
                {
                  'type': 'node',
                  'id': 3,
                  'lat': 42.73,
                  'lon': 1.96,
                  'tags': {'amenity': 'charging_station', 'name': 'Borne'},
                },
              ]),
              200,
            )),
      );

      final resultats =
          await service.fetchAround(_pailheres, radiusKm: 20, vehicule: VehicleKind.van);

      expect(resultats, hasLength(3));
      expect(resultats.firstWhere((p) => p.name == 'Aire du col').category,
          PoiCategory.aireCampingCar);
      expect(resultats.firstWhere((p) => p.name == 'Vidange').category,
          PoiCategory.vidange);
      expect(resultats.firstWhere((p) => p.name == 'Borne').category,
          PoiCategory.borneRecharge);
    });

    test('un élément sans tag connu est écarté plutôt que mal classé', () {
      expect(categorieDepuisTags(const {'leisure': 'pitch'}), isNull);
      expect(categorieDepuisTags(const {}), isNull);
    });
  });

  group('ce que le véhicule change ailleurs', () {
    test('seul le camping-car a un gabarit à surveiller', () {
      expect(VehicleKind.van.hasGabarit, isTrue);
      expect(VehicleKind.moto.hasGabarit, isFalse);
      expect(VehicleKind.quatreQuatre.hasGabarit, isFalse);
    });

    test('le profil de pilotage moto ne vaut que pour la moto', () {
      expect(VehicleKind.moto.usesMotoProfile, isTrue);
      expect(VehicleKind.van.usesMotoProfile, isFalse);
      expect(VehicleKind.quatreQuatre.usesMotoProfile, isFalse);
    });

    test('le camping-car ne va pas hors des routes ouvertes', () {
      expect(VehicleKind.van.roulesHorsRoute, isFalse);
      expect(VehicleKind.moto.roulesHorsRoute, isTrue);
      expect(VehicleKind.quatreQuatre.roulesHorsRoute, isTrue);
    });

    test('chaque véhicule se met dans une phrase sans faute d accord', () {
      expect('${VehicleKind.moto.avecArticle} est '
          'arrêté${VehicleKind.moto.accordePasse}', 'la moto est arrêtée');
      expect('${VehicleKind.van.avecArticle} est '
          'arrêté${VehicleKind.van.accordePasse}', 'le camping-car est arrêté');
      expect('${VehicleKind.quatreQuatre.avecArticle} est '
          'arrêté${VehicleKind.quatreQuatre.accordePasse}', 'le 4x4 est arrêté');
    });

    test('chaque véhicule cherche au moins du carburant', () {
      for (final v in VehicleKind.values) {
        expect(v.poiCategories, contains(PoiCategory.gasStation),
            reason: '${v.label} doit pouvoir faire le plein');
      }
    });

    test('toute catégorie affichée par un véhicule sait se demander à Overpass', () {
      for (final v in VehicleKind.values) {
        for (final c in v.poiCategories) {
          expect(c.overpassSelector, isNotNull,
              reason: '${c.label} est proposée pour ${v.label} mais ne sait pas '
                  'se traduire en requête');
        }
      }
    });
  });
}
