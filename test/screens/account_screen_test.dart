import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:latlong2/latlong.dart';
import 'package:moto_offroad/providers/account_provider.dart';
import 'package:moto_offroad/providers/shared_traces_provider.dart';
import 'package:moto_offroad/services/account_api_client.dart';
import 'package:moto_offroad/services/shared_traces_api_client.dart';
import 'package:moto_offroad/screens/account/account_screen.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    // deleteAccount() efface aussi la charte memorisee localement (Tache
    // 23C) : sans ce mock, l'appel a SharedPreferences leverait une
    // MissingPluginException (meme raison que dans router_test.dart).
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('la suppression de compte demande confirmation avant d agir',
      (tester) async {
    var suppressionAppelee = false;
    // Le mock renvoie un jeton valide pour l inscription : sans lui,
    // `AccountApiClient.register` échoue au décodage JSON (clé "token"
    // absente) et `AccountProvider.deleteAccount` court-circuite avant tout
    // appel réseau faute de jeton — le test ne prouverait alors plus rien
    // sur la confirmation.
    final p = AccountProvider(
      api: AccountApiClient(
          baseUrl: 'https://exemple.test',
          client: MockClient((req) async {
            if (req.method == 'DELETE') {
              suppressionAppelee = true;
              return http.Response('{}', 200);
            }
            return http.Response(
              jsonEncode(
                  {'token': 'jeton', 'verified': true, 'displayName': 'Marc'}),
              201,
            );
          })),
    );
    await p.register(email: 'rider@example.test', password: 'dix caracteres');

    // AccountScreen efface aussi la recherche du catalogue partagé à la
    // suppression (Trouvaille mineure de la revue finale) : ce provider
    // doit donc être disponible ici comme il l'est réellement dans
    // l'application (voir main.dart).
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AccountProvider>.value(value: p),
        ChangeNotifierProvider<SharedTracesProvider>(
          create: (_) => SharedTracesProvider(SharedTracesApiClient(readToken: () async => null)),
        ),
      ],
      child: const MaterialApp(home: AccountScreen()),
    ));
    await tester.tap(find.byKey(const Key('bouton-supprimer-compte')));
    await tester.pumpAndSettle();

    expect(suppressionAppelee, isFalse,
        reason: 'aucune suppression sans confirmation');
    expect(find.textContaining('définitive'), findsOneWidget);

    await tester.tap(find.byKey(const Key('bouton-confirmer-suppression')));
    await tester.pumpAndSettle();
    expect(suppressionAppelee, isTrue);
  });

  // Trouvaille mineure de la revue finale : SharedTracesProvider est fourni
  // une seule fois pour toute l'application, partagé entre les comptes qui
  // se succèdent sur le même téléphone.

  testWidgets('la suppression de compte reussie efface aussi la recherche du catalogue partage',
      (tester) async {
    final p = AccountProvider(
      api: AccountApiClient(
          baseUrl: 'https://exemple.test',
          client: MockClient((req) async {
            if (req.method == 'DELETE') return http.Response('{}', 200);
            return http.Response(jsonEncode({'token': 'jeton', 'verified': true}), 201);
          })),
    );
    await p.register(email: 'rider@example.test', password: 'dix caracteres');

    final traces = SharedTracesProvider(SharedTracesApiClient(readToken: () async => null));
    await traces.setReference(const LatLng(43.6, 1.44), label: '12 rue du Sidobre');
    expect(traces.reference, isNotNull);

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AccountProvider>.value(value: p),
        ChangeNotifierProvider<SharedTracesProvider>.value(value: traces),
      ],
      child: const MaterialApp(home: AccountScreen()),
    ));
    await tester.tap(find.byKey(const Key('bouton-supprimer-compte')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bouton-confirmer-suppression')));
    await tester.pumpAndSettle();

    expect(traces.reference, isNull,
        reason: 'un compte supprime ne doit pas laisser la recherche du precedent rider derriere lui');
  });

  testWidgets('se deconnecter efface aussi la recherche du catalogue partage', (tester) async {
    final p = AccountProvider(
      api: AccountApiClient(
          baseUrl: 'https://exemple.test',
          client: MockClient((_) async => http.Response(jsonEncode({'token': 'jeton', 'verified': true}), 201))),
    );
    await p.register(email: 'rider@example.test', password: 'dix caracteres');

    final traces = SharedTracesProvider(SharedTracesApiClient(readToken: () async => null));
    await traces.setReference(const LatLng(43.6, 1.44), label: '12 rue du Sidobre');
    expect(traces.reference, isNotNull);

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AccountProvider>.value(value: p),
        ChangeNotifierProvider<SharedTracesProvider>.value(value: traces),
      ],
      child: const MaterialApp(home: AccountScreen()),
    ));
    await tester.tap(find.byKey(const Key('bouton-deconnexion')));
    await tester.pumpAndSettle();

    expect(traces.reference, isNull);
  });
}
