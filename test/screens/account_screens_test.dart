import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:convert';
import 'package:moto_offroad/providers/account_provider.dart';
import 'package:moto_offroad/services/account_api_client.dart';
import 'package:moto_offroad/screens/account/register_screen.dart';
import 'package:moto_offroad/screens/account/verify_screen.dart';

Widget monter(Widget enfant, AccountProvider p) => ChangeNotifierProvider.value(
      value: p,
      child: MaterialApp(home: enfant),
    );

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('l inscription refuse un mot de passe trop court sans appeler le serveur', (tester) async {
    var appels = 0;
    final p = AccountProvider(
      api: AccountApiClient(baseUrl: 'https://exemple.test', client: MockClient((_) async {
        appels++;
        return http.Response('{}', 201);
      })),
    );
    await tester.pumpWidget(monter(const RegisterScreen(), p));

    await tester.enterText(find.byKey(const Key('champ-email')), 'rider@example.test');
    await tester.enterText(find.byKey(const Key('champ-mot-de-passe')), 'court');
    await tester.tap(find.byKey(const Key('bouton-inscription')));
    await tester.pump();

    expect(find.textContaining('10 caractères'), findsOneWidget);
    expect(appels, 0);
  });

  testWidgets('l ecran d attente propose de renvoyer et de corriger l adresse', (tester) async {
    final p = AccountProvider(
      api: AccountApiClient(baseUrl: 'https://exemple.test', client: MockClient((_) async =>
          http.Response(jsonEncode({'email': 'rider@example.test', 'verified': false}), 200))),
    );
    await tester.pumpWidget(monter(const VerifyScreen(), p));
    await tester.pump();

    expect(find.byKey(const Key('bouton-jai-confirme')), findsOneWidget);
    expect(find.byKey(const Key('bouton-renvoyer')), findsOneWidget);
    expect(find.byKey(const Key('bouton-corriger-adresse')), findsOneWidget);
  });

  testWidgets('une panne reseau affiche un message explicite', (tester) async {
    final p = AccountProvider(
      api: AccountApiClient(baseUrl: 'https://exemple.test',
          client: MockClient((_) async => throw Exception('reseau coupe'))),
    );
    await tester.pumpWidget(monter(const RegisterScreen(), p));

    await tester.enterText(find.byKey(const Key('champ-email')), 'rider@example.test');
    await tester.enterText(find.byKey(const Key('champ-mot-de-passe')), 'dix caracteres');
    await tester.tap(find.byKey(const Key('bouton-inscription')));
    await tester.pumpAndSettle();

    expect(find.textContaining('connexion internet'), findsOneWidget);
  });
}
