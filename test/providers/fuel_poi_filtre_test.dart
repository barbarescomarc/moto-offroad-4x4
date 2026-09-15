// test/providers/fuel_poi_filtre_test.dart
//
// Le filtre des catégories. Sur une carte de ville, chaque fontaine publique
// est un point d'eau : sans filtre, la carte cache ce qu'on cherchait.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moto_offroad/models/poi.dart';
import 'package:moto_offroad/models/vehicle_kind.dart';
import 'package:moto_offroad/providers/fuel_poi_provider.dart';
import 'package:moto_offroad/services/fuel_poi_service.dart';

const _toulouse = LatLng(43.6045, 1.4442);

// Overpass rend un mélange des catégories demandées par le véhicule.
String _reponseOverpass() => jsonEncode({
      'elements': [
        {'type': 'node', 'id': 1, 'lat': 43.60, 'lon': 1.44,
         'tags': {'amenity': 'fuel', 'name': 'Station'}},
        {'type': 'node', 'id': 2, 'lat': 43.61, 'lon': 1.44,
         'tags': {'amenity': 'drinking_water', 'name': 'Fontaine 1'}},
        {'type': 'node', 'id': 3, 'lat': 43.62, 'lon': 1.44,
         'tags': {'amenity': 'drinking_water', 'name': 'Fontaine 2'}},
        {'type': 'node', 'id': 4, 'lat': 43.63, 'lon': 1.44,
         'tags': {'shop': 'car_repair', 'name': 'Garage'}},
      ],
    });

Future<FuelPoiProvider> _providerAvecResultats() async {
  SharedPreferences.setMockInitialValues({});
  final provider = FuelPoiProvider(
    service: FuelPoiService(
        client: MockClient((_) async => http.Response(_reponseOverpass(), 200))),
  );
  await provider.chargerFiltres();
  await provider.searchAround(_toulouse, radiusKm: 20, vehicule: VehicleKind.van);
  return provider;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sans filtre, tout est affiché', () async {
    final provider = await _providerAvecResultats();

    expect(provider.results, hasLength(4));
    expect(provider.resultatsFiltres, hasLength(4));
  });

  test('masquer une catégorie retire ses points de la carte', () async {
    final provider = await _providerAvecResultats();

    await provider.basculerCategorie(PoiCategory.eauPotable);

    expect(provider.resultatsFiltres, hasLength(2));
    expect(
      provider.resultatsFiltres.any((p) => p.category == PoiCategory.eauPotable),
      isFalse,
    );
  });

  test('les résultats bruts ne sont jamais perdus', () async {
    final provider = await _providerAvecResultats();

    await provider.basculerCategorie(PoiCategory.eauPotable);

    expect(provider.results, hasLength(4),
        reason: 'rallumer le filtre doit être instantané, sans redemander');
  });

  test('rebasculer réaffiche la catégorie', () async {
    final provider = await _providerAvecResultats();

    await provider.basculerCategorie(PoiCategory.eauPotable);
    await provider.basculerCategorie(PoiCategory.eauPotable);

    expect(provider.resultatsFiltres, hasLength(4));
  });

  test('tout afficher lève tous les filtres', () async {
    final provider = await _providerAvecResultats();

    await provider.basculerCategorie(PoiCategory.eauPotable);
    await provider.basculerCategorie(PoiCategory.garage);
    await provider.toutAfficher();

    expect(provider.resultatsFiltres, hasLength(4));
  });

  // On ne propose de filtrer que ce qui a été trouvé : offrir de masquer une
  // famille absente laisse croire qu'on a raté quelque chose.
  test('seules les catégories trouvées sont proposées', () async {
    final provider = await _providerAvecResultats();

    expect(provider.categoriesTrouvees, [
      PoiCategory.gasStation,
      PoiCategory.garage,
      PoiCategory.eauPotable,
    ]);
  });

  test('le compte par catégorie explique la carte encombrée', () async {
    final provider = await _providerAvecResultats();

    expect(provider.compte(PoiCategory.eauPotable), 2);
    expect(provider.compte(PoiCategory.gasStation), 1);
  });

  test('le choix survit au redémarrage', () async {
    final premier = await _providerAvecResultats();
    await premier.basculerCategorie(PoiCategory.eauPotable);

    final second = FuelPoiProvider(
      service: FuelPoiService(
          client: MockClient((_) async => http.Response(_reponseOverpass(), 200))),
    );
    await second.chargerFiltres();
    await second.searchAround(_toulouse, radiusKm: 20, vehicule: VehicleKind.van);

    expect(second.estAffichee(PoiCategory.eauPotable), isFalse);
    expect(second.resultatsFiltres, hasLength(2));
  });

  // Stocker ce qu'on masque plutôt que ce qu'on montre : une catégorie
  // ajoutée plus tard à un véhicule doit s'afficher d'office.
  test('une catégorie jamais vue s affiche par défaut', () async {
    SharedPreferences.setMockInitialValues({
      'poi_categories_masquees': ['eauPotable'],
    });
    final provider = FuelPoiProvider(
      service: FuelPoiService(
          client: MockClient((_) async => http.Response(_reponseOverpass(), 200))),
    );
    await provider.chargerFiltres();

    expect(provider.estAffichee(PoiCategory.borneRecharge), isTrue);
    expect(provider.estAffichee(PoiCategory.eauPotable), isFalse);
  });
}
