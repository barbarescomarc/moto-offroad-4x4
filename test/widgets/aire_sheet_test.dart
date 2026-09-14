// test/widgets/aire_sheet_test.dart
//
// La règle de la fiche : ne jamais laisser croire qu'on sait ce qu'on ne
// sait pas. Un champ vide dit « Non renseigné » et propose de le compléter.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moto_offroad/models/aire.dart';
import 'package:moto_offroad/models/vehicle_kind.dart';
import 'package:moto_offroad/providers/aires_provider.dart';
import 'package:moto_offroad/providers/settings_provider.dart';
import 'package:moto_offroad/services/aires_api_client.dart';
import 'package:moto_offroad/widgets/aire_sheet.dart';

const _aireNue = AireModel(
  id: 'osm:node:1', position: LatLng(43.6, 1.44), source: 'osm', name: 'Aire test',
);

Future<Widget> _monter(
  AireModel aire, {
  AiresApiClient? client,
  double hauteurM = 2.8,
  VoidCallback? onGuider,
}) async {
  SharedPreferences.setMockInitialValues({});
  final settings = SettingsProvider();
  await settings.load();
  await settings.setVehicleKind(VehicleKind.van);
  await settings.setGabarit(hauteurM: hauteurM);

  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: settings),
      ChangeNotifierProvider(create: (_) => AiresProvider(
            client: AiresApiClient(
              client: MockClient((_) async => http.Response('{"aires":[]}', 200)),
              baseUrl: 'https://hub.test',
            ),
          )),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: AireSheet(
          aire: aire, client: client, onGuider: onGuider ?? () {},
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('un champ vide dit « Non renseigné » et propose de compléter',
      (tester) async {
    await tester.pumpWidget(await _monter(_aireNue));

    expect(find.text('Non renseigné'), findsWidgets);
    expect(find.text('· compléter'), findsWidgets);
    expect(find.byKey(const Key('completer-max_height_m')), findsOneWidget);
  });

  testWidgets('un champ renseigné s affiche à la place', (tester) async {
    await tester.pumpWidget(await _monter(const AireModel(
      id: 'osm:node:1', position: LatLng(43.6, 1.44), source: 'osm',
      name: 'Aire test', capacity: 12,
    )));

    expect(find.text('12 places'), findsOneWidget);
    expect(find.byKey(const Key('completer-capacity')), findsNothing);
  });

  // Écrire « ça passe » faute d'information serait exactement le mensonge
  // que cette fiche refuse.
  testWidgets('sans hauteur connue, aucun verdict de gabarit', (tester) async {
    await tester.pumpWidget(await _monter(_aireNue));

    expect(find.textContaining('Ton gabarit passe'), findsNothing);
    expect(find.textContaining('Trop haut'), findsNothing);
  });

  testWidgets('avec une hauteur connue, le verdict est affiché', (tester) async {
    await tester.pumpWidget(await _monter(
      const AireModel(id: 'osm:node:1', position: LatLng(43.6, 1.44),
          source: 'osm', name: 'Aire', maxHeightM: 3.5),
      hauteurM: 2.8,
    ));

    expect(find.textContaining('Ton gabarit passe'), findsOneWidget);
  });

  testWidgets('un camping-car trop haut est averti', (tester) async {
    await tester.pumpWidget(await _monter(
      const AireModel(id: 'osm:node:1', position: LatLng(43.6, 1.44),
          source: 'osm', name: 'Aire', maxHeightM: 2.5),
      hauteurM: 3.2,
    ));

    expect(find.textContaining('Trop haut'), findsOneWidget);
  });

  testWidgets('le bouton naviguer appelle le guidage', (tester) async {
    var appele = false;
    await tester.pumpWidget(
        await _monter(_aireNue, onGuider: () => appele = true));

    await tester.tap(find.text('Naviguer vers cette aire'));
    expect(appele, isTrue);
  });

  testWidgets('seuls les services présents sont listés', (tester) async {
    await tester.pumpWidget(await _monter(const AireModel(
      id: 'osm:node:1', position: LatLng(43.6, 1.44), source: 'osm',
      name: 'Aire', services: AireServices({'eau': true, 'vidange': false}),
    )));

    expect(find.text('Eau potable'), findsOneWidget);
    expect(find.text('Vidange'), findsNothing);
  });

  testWidgets('un relevé part au serveur sous le bon champ', (tester) async {
    Map<String, dynamic>? envoye;
    final client = AiresApiClient(
      client: MockClient((requete) async {
        envoye = jsonDecode(requete.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'etat': 'retenue'}), 201);
      }),
      baseUrl: 'https://hub.test',
    );
    await tester.pumpWidget(await _monter(_aireNue, client: client));

    await tester.tap(find.byKey(const Key('completer-max_height_m')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('saisie-releve')), '3,20');
    await tester.tap(find.byKey(const Key('envoyer-releve')));
    await tester.pumpAndSettle();

    expect(envoye!['champ'], 'max_height_m');
    expect(envoye!['valeur'], 3.2);
  });

  testWidgets('une saisie non numérique est refusée avant l envoi',
      (tester) async {
    var envois = 0;
    final client = AiresApiClient(
      client: MockClient((_) async {
        envois += 1;
        return http.Response('{"etat":"retenue"}', 201);
      }),
      baseUrl: 'https://hub.test',
    );
    await tester.pumpWidget(await _monter(_aireNue, client: client));

    await tester.tap(find.byKey(const Key('completer-capacity')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('saisie-releve')), '');
    await tester.tap(find.byKey(const Key('envoyer-releve')));
    await tester.pumpAndSettle();

    expect(envois, 0);
    expect(find.text('Entre une valeur'), findsOneWidget);
  });
}
