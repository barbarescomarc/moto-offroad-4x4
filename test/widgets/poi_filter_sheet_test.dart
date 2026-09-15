// test/widgets/poi_filter_sheet_test.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moto_offroad/models/poi.dart';
import 'package:moto_offroad/models/vehicle_kind.dart';
import 'package:moto_offroad/providers/fuel_poi_provider.dart';
import 'package:moto_offroad/services/fuel_poi_service.dart';
import 'package:moto_offroad/widgets/poi_filter_sheet.dart';

String _reponse() => jsonEncode({
      'elements': [
        {'type': 'node', 'id': 1, 'lat': 43.60, 'lon': 1.44,
         'tags': {'amenity': 'fuel', 'name': 'Station'}},
        {'type': 'node', 'id': 2, 'lat': 43.61, 'lon': 1.44,
         'tags': {'amenity': 'drinking_water', 'name': 'Fontaine 1'}},
        {'type': 'node', 'id': 3, 'lat': 43.62, 'lon': 1.44,
         'tags': {'amenity': 'drinking_water', 'name': 'Fontaine 2'}},
      ],
    });

Future<FuelPoiProvider> _provider({bool avecResultats = true}) async {
  SharedPreferences.setMockInitialValues({});
  final provider = FuelPoiProvider(
    service: FuelPoiService(
        client: MockClient((_) async => http.Response(_reponse(), 200))),
  );
  await provider.chargerFiltres();
  if (avecResultats) {
    await provider.searchAround(const LatLng(43.6, 1.44),
        radiusKm: 20, vehicule: VehicleKind.van);
  }
  return provider;
}

Widget _monter(FuelPoiProvider provider) => ChangeNotifierProvider.value(
      value: provider,
      child: const MaterialApp(home: Scaffold(body: PoiFilterSheet())),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('chaque catégorie trouvée a sa puce, avec son compte',
      (tester) async {
    await tester.pumpWidget(_monter(await _provider()));

    expect(find.byKey(const Key('filtre-eauPotable')), findsOneWidget);
    expect(find.byKey(const Key('filtre-gasStation')), findsOneWidget);
    expect(find.textContaining('Eau potable  2'), findsOneWidget);
  });

  // Offrir de filtrer une famille absente des résultats laisse croire qu'on a
  // raté quelque chose.
  testWidgets('une catégorie absente des résultats n est pas proposée',
      (tester) async {
    await tester.pumpWidget(_monter(await _provider()));

    expect(find.byKey(const Key('filtre-vidange')), findsNothing);
  });

  testWidgets('décocher une puce masque la catégorie', (tester) async {
    final provider = await _provider();
    await tester.pumpWidget(_monter(provider));

    await tester.tap(find.byKey(const Key('filtre-eauPotable')));
    await tester.pumpAndSettle();

    expect(provider.estAffichee(PoiCategory.eauPotable), isFalse);
    expect(provider.resultatsFiltres, hasLength(1));
  });

  testWidgets('tout afficher remet les puces', (tester) async {
    final provider = await _provider();
    await tester.pumpWidget(_monter(provider));

    await tester.tap(find.byKey(const Key('filtre-eauPotable')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('filtre-tout-afficher')));
    await tester.pumpAndSettle();

    expect(provider.resultatsFiltres, hasLength(3));
  });

  testWidgets('sans résultat, la feuille le dit au lieu d être vide',
      (tester) async {
    await tester.pumpWidget(_monter(await _provider(avecResultats: false)));

    expect(find.textContaining('Lance une recherche'), findsOneWidget);
    expect(find.byKey(const Key('filtre-tout-afficher')), findsNothing);
  });
}
