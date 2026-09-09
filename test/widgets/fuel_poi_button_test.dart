import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:moto_offroad/models/poi.dart';
import 'package:moto_offroad/providers/fuel_poi_provider.dart';
import 'package:moto_offroad/services/fuel_poi_service.dart';
import 'package:moto_offroad/widgets/fuel_poi_button.dart';

const _toulouse = LatLng(43.6045, 1.4442);

Widget _monter(FuelPoiProvider provider, {void Function(List<PoiModel>)? onResults}) =>
    ChangeNotifierProvider.value(
      value: provider,
      child: MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.centerRight,
            child: FuelPoiButton(
              currentCenter: () => _toulouse,
              radiusKm: 20,
              onResults: onResults,
            ),
          ),
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

  testWidgets('une recherche fructueuse remonte ses resultats a l appelant', (tester) async {
    List<PoiModel>? recus;
    final provider = FuelPoiProvider(
      service: FuelPoiService(client: MockClient((_) async => http.Response(
            jsonEncode({
              'elements': [
                {
                  'type': 'node',
                  'id': 1,
                  'lat': 43.61,
                  'lon': 1.45,
                  'tags': {'amenity': 'fuel', 'name': 'Station du Nord'},
                },
              ],
            }),
            200,
          ))),
    );

    await tester.pumpWidget(_monter(provider, onResults: (r) => recus = r));
    await tester.tap(find.byKey(const Key('bouton-stations-proximite')));
    await tester.pumpAndSettle();

    // Sans cela, le pilote appuie, une icone change de couleur, et les
    // stations restent hors cadre : rien ne se passe, de son point de vue.
    expect(recus, isNotNull);
    expect(recus, hasLength(1));
  });

  testWidgets('l indicateur d indisponibilite ne deplace pas le bouton', (tester) async {
    final provider = FuelPoiProvider(
      service: FuelPoiService(client: MockClient((_) async => throw Exception('reseau coupe'))),
    );

    await tester.pumpWidget(_monter(provider));
    final avant = tester.getCenter(find.byKey(const Key('bouton-stations-proximite')));

    await tester.tap(find.byKey(const Key('bouton-stations-proximite')));
    await tester.pumpAndSettle();

    final apres = tester.getCenter(find.byKey(const Key('bouton-stations-proximite')));
    expect(find.byKey(const Key('stations-indisponible')), findsOneWidget);
    // Un indicateur qui pousse le bouton fait rater la cible au second appui.
    expect(apres, avant);
  });

  testWidgets('un second appui eteint les stations sans redemander au serveur', (tester) async {
    var appels = 0;
    final provider = FuelPoiProvider(
      service: FuelPoiService(client: MockClient((_) async {
        appels++;
        return http.Response(
          jsonEncode({
            'elements': [
              {
                'type': 'node',
                'id': 1,
                'lat': 43.61,
                'lon': 1.45,
                'tags': {'amenity': 'fuel', 'name': 'Station du Nord'},
              },
            ],
          }),
          200,
        );
      })),
    );

    await tester.pumpWidget(_monter(provider));
    await tester.tap(find.byKey(const Key('bouton-stations-proximite')));
    await tester.pumpAndSettle();
    expect(provider.results, hasLength(1));

    await tester.tap(find.byKey(const Key('bouton-stations-proximite')));
    await tester.pumpAndSettle();

    expect(provider.results, isEmpty, reason: 'le second appui doit eteindre');
    expect(appels, 1, reason: 'eteindre ne doit pas relancer une requete');
  });

  testWidgets('un appui apres un echec efface l indicateur d indisponibilite', (tester) async {
    final provider = FuelPoiProvider(
      service: FuelPoiService(client: MockClient((_) async => throw Exception('reseau coupe'))),
    );

    await tester.pumpWidget(_monter(provider));
    await tester.tap(find.byKey(const Key('bouton-stations-proximite')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('stations-indisponible')), findsOneWidget);

    await tester.tap(find.byKey(const Key('bouton-stations-proximite')));
    await tester.pumpAndSettle();

    // Sans cela, le nuage barre reste colle a l'ecran sans moyen de l'oter.
    expect(find.byKey(const Key('stations-indisponible')), findsNothing);
  });
}
