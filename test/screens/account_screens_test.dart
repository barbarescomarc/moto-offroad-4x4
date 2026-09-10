import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:convert';
import 'package:moto_offroad/providers/account_provider.dart';
import 'package:moto_offroad/services/account_api_client.dart';
import 'package:moto_offroad/services/legal_documents.dart';
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
    // Le bouton est desormais inerte tant que la charte n est pas acceptee
    // (Critique 1) : il faut cocher la case pour meme atteindre la
    // validation du mot de passe.
    await tester.tap(find.byKey(const Key('case-acceptation-charte')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('bouton-inscription')));
    await tester.pump();

    expect(find.textContaining('10 caractères'), findsOneWidget);
    expect(appels, 0);
  });

  // ── Charte du pilote a l inscription (Critique 1 de la revue finale) ──
  //
  // Avant ce correctif, RegisterScreen envoyait systematiquement
  // LegalDocuments.charteVersion sans jamais montrer la charte : un rider
  // se voyait enregistrer une acceptation d un document qu il n avait
  // jamais vu, precisement celui qui l avertit que la detection de chute
  // peut echouer et que rien ici ne remplace le 112.

  testWidgets('le bouton d inscription reste inactif tant que la charte n est pas acceptee', (tester) async {
    final p = AccountProvider(
      api: AccountApiClient(baseUrl: 'https://exemple.test', client: MockClient((_) async => http.Response('{}', 201))),
    );
    await tester.pumpWidget(monter(const RegisterScreen(), p));

    final avant = tester.widget<FilledButton>(find.byKey(const Key('bouton-inscription')));
    expect(avant.onPressed, isNull);

    await tester.tap(find.byKey(const Key('case-acceptation-charte')));
    await tester.pump();

    final apres = tester.widget<FilledButton>(find.byKey(const Key('bouton-inscription')));
    expect(apres.onPressed, isNotNull);
  });

  testWidgets('le lien charte du pilote ouvre le texte complet depuis l inscription', (tester) async {
    final p = AccountProvider(
      api: AccountApiClient(baseUrl: 'https://exemple.test', client: MockClient((_) async => http.Response('{}', 201))),
    );
    await tester.runAsync(() async {
      // LegalDocumentScreen lit docs/legal/charte-du-pilote.md via
      // rootBundle : une vraie lecture de fichier, hors de l horloge
      // simulee (voir la meme remarque dans account_screens_test.dart pour
      // CharteScreen, plus haut dans ce fichier).
      await tester.pumpWidget(monter(const RegisterScreen(), p));
      await tester.tap(find.text('charte du pilote'));
      await tester.pumpAndSettle();

      // Le 112 : point 2 de la charte, preuve que le vrai texte est
      // affiche, pas un texte de test.
      expect(find.textContaining('112'), findsWidgets);
    });
  });

  testWidgets('cocher la charte puis s inscrire envoie sa version au serveur', (tester) async {
    Map<String, dynamic>? corpsEnvoye;
    final p = AccountProvider(
      api: AccountApiClient(baseUrl: 'https://exemple.test', client: MockClient((req) async {
        corpsEnvoye = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'token': 'jeton', 'verified': false}), 201);
      })),
    );
    await tester.pumpWidget(monter(const RegisterScreen(), p));

    await tester.enterText(find.byKey(const Key('champ-email')), 'rider@example.test');
    await tester.enterText(find.byKey(const Key('champ-mot-de-passe')), 'dix caracteres');
    await tester.tap(find.byKey(const Key('case-acceptation-charte')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('bouton-inscription')));
    await tester.pumpAndSettle();

    expect(corpsEnvoye?['charteVersion'], LegalDocuments.charteVersion);
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
    await tester.tap(find.byKey(const Key('case-acceptation-charte')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('bouton-inscription')));
    await tester.pumpAndSettle();

    expect(find.textContaining('connexion internet'), findsOneWidget);
  });
}
