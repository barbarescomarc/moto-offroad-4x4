import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:moto_offroad/providers/fuel_poi_provider.dart';
import 'package:moto_offroad/services/fuel_poi_service.dart';
import 'package:moto_offroad/widgets/fuel_poi_button.dart';

const _toulouse = LatLng(43.6045, 1.4442);

Widget _monter(FuelPoiProvider provider) => ChangeNotifierProvider.value(
      value: provider,
      child: MaterialApp(
        home: Scaffold(
          body: FuelPoiButton(currentCenter: () => _toulouse, radiusKm: 20),
        ),
      ),
    );

void main() {
  testWidgets('un appui cherche les stations autour du centre fourni', (tester) async {
    var appels = 0;
    LatLng? centreDemande;
    final provider = FuelPoiProvider(
      service: FuelPoiService(client: MockClient((requete) async {
        appels++;
        final data = requete.bodyFields['data'] ?? '';
        final m = RegExp(r'around:\d+,([-\d.]+),([-\d.]+)').firstMatch(data);
        centreDemande = LatLng(double.parse(m!.group(1)!), double.parse(m.group(2)!));
        return http.Response(jsonEncode({'elements': []}), 200);
      })),
    );

    await tester.pumpWidget(_monter(provider));
    await tester.tap(find.byKey(const Key('bouton-stations-proximite')));
    await tester.pumpAndSettle();

    expect(appels, 1);
    expect(centreDemande, _toulouse);
  });

  testWidgets('un second appui pendant la recherche ne la relance pas', (tester) async {
    var appels = 0;
    final provider = FuelPoiProvider(
      service: FuelPoiService(client: MockClient((_) async {
        appels++;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return http.Response(jsonEncode({'elements': []}), 200);
      })),
    );

    await tester.pumpWidget(_monter(provider));
    await tester.tap(find.byKey(const Key('bouton-stations-proximite')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('bouton-stations-proximite')));
    await tester.pumpAndSettle();

    expect(appels, 1, reason: 'un appui repete ne doit pas empiler les requetes Overpass');
  });

  testWidgets('une indisponibilite est signalee au pilote', (tester) async {
    final provider = FuelPoiProvider(
      service: FuelPoiService(client: MockClient((_) async => throw Exception('reseau coupe'))),
    );

    await tester.pumpWidget(_monter(provider));
    await tester.tap(find.byKey(const Key('bouton-stations-proximite')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('stations-indisponible')), findsOneWidget);
  });
}
