import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moto_offroad/app/router.dart';
import 'package:moto_offroad/providers/account_provider.dart';
import 'package:moto_offroad/screens/account/account_screen.dart';
import 'package:moto_offroad/screens/legal/charte_screen.dart';
import 'package:moto_offroad/services/account_api_client.dart';
import 'package:moto_offroad/services/account_storage.dart';

// Double de AccountApiClient : capture les acceptations de charte sans
// jamais faire de vraie requête réseau. L'inscription, elle, passe par un
// vrai MockClient — c'est ce qui fait passer AccountProvider à `connecte`
// (verified: true), condition pour que le mur de la charte s'applique
// (voir accountRedirect, qui ne le teste qu'après la vérification
// d'adresse).
class _ApiFactice extends AccountApiClient {
  _ApiFactice()
      : super(
          baseUrl: 'https://exemple.test',
          client: MockClient(
            (_) async => http.Response(jsonEncode({'token': 'jeton', 'verified': true}), 201),
          ),
        );

  final chartesAcceptees = <String>[];

  @override
  Future<AccountResult<void>> acceptCharte({required String token, required String version}) async {
    chartesAcceptees.add(version);
    return const AccountResult.success(null);
  }
}

// Même double, mais dont l'acceptation échoue toujours réseau — simule un
// rider hors couverture face à l'écran de la charte (Critique 3a de la
// revue finale).
class _ApiFacticeHorsLigne extends AccountApiClient {
  _ApiFacticeHorsLigne()
      : super(
          baseUrl: 'https://exemple.test',
          client: MockClient(
            (_) async => http.Response(jsonEncode({'token': 'jeton', 'verified': true}), 201),
          ),
        );

  @override
  Future<AccountResult<void>> acceptCharte({required String token, required String version}) async =>
      const AccountResult.failure(AccountError.reseau);
}

// Compte connecté (adresse vérifiée) dont le rider a — ou non — déjà
// accepté la charte dans sa version courante.
Future<AccountProvider> compteDeTest({required String? charteVersion, AccountApiClient? api}) async {
  final compte = AccountProvider(api: api ?? _ApiFactice(), storage: AccountStorage());
  await compte.register(email: 'rider@example.test', password: 'dix caracteres', charteVersion: charteVersion);
  return compte;
}

// Le vrai routeur de l'application (buildAppRouter, celui que main.dart
// monte), pas une reconstruction partielle : seule façon de prouver que le
// mur de la charte est réellement branché dans accountRedirect, pas
// seulement que CharteScreen se construit bien en isolation. '/mon-compte'
// sert de point d'arrivée protégé : une route hors ShellRoute, qui ne
// dépend que d'AccountProvider (déjà fourni ici), donc atteignable dans un
// test widget pur — contrairement à la carte (MapProvider/FMTC,
// wakelock_plus, PackageInfo, voir test/app/router_test.dart) ou à /sos
// (bouton SOS animé en boucle, incompatible avec pumpAndSettle).
Future<void> appDeTest(WidgetTester tester, AccountProvider compte) async {
  // CharteScreen lit docs/legal/charte-du-pilote.md via rootBundle : une
  // vraie lecture de fichier, pas mockable en zone de temps simulé — sans
  // runAsync, le pump ne progresse jamais (même constat, déjà posé pour
  // sqflite ffi, dans publish_trace_screen_test.dart et
  // shared_trace_detail_screen_test.dart).
  await tester.runAsync(() async {
    SharedPreferences.setMockInitialValues({});
    // Une charte déjà acceptée en entrant sur cette route ne bouge plus de
    // là (voir le test dédié) ; mais accepter DEPUIS charteRoute renvoie
    // vers '/', qui monte MainShell — d'où ce mock, sur le même modèle que
    // test/app/router_test.dart, pour éviter une MissingPluginException
    // résiduelle sur son vérificateur de mise à jour.
    PackageInfo.setMockInitialValues(
      appName: 'test',
      packageName: 'test',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<AccountProvider>.value(
        value: compte,
        child: MaterialApp.router(routerConfig: buildAppRouter(initialLocation: AppRoutes.account)),
      ),
    );
    await tester.pumpAndSettle();
  });
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    // compteDeTest() accepte parfois la charte avant que appDeTest() ne
    // pose son propre mock plus bas (voir tester.runAsync) : sans celui-ci
    // en place des le depart, memoriser la version localement (Tache 23C)
    // leverait une MissingPluginException.
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('la charte s affiche tant qu elle n est pas acceptee, et bloque l acces', (tester) async {
    final compte = await compteDeTest(charteVersion: null);
    await appDeTest(tester, compte);

    expect(find.byType(CharteScreen), findsOneWidget);
    // Le 112 : point 2 de la charte, sur ce que l'application ne remplace
    // jamais — preuve que le vrai texte (docs/legal/charte-du-pilote.md,
    // lu via LegalDocuments) est bien affiché, pas un texte de test.
    expect(find.textContaining('112'), findsWidgets);
    // Rien d'autre n'est atteignable tant que la charte n'est pas acceptée
    // — pas même une route hors ShellRoute comme /mon-compte.
    expect(find.byType(AccountScreen), findsNothing);
  });

  testWidgets("le bouton J'accepte reste inactif tant que la case n est pas cochee", (tester) async {
    final compte = await compteDeTest(charteVersion: null);
    await appDeTest(tester, compte);

    final bouton = tester.widget<FilledButton>(find.widgetWithText(FilledButton, "J'accepte"));
    expect(bouton.onPressed, isNull);
  });

  // CharteScreen seul, sans GoRouter : ce test porte sur l'action
  // (cocher, appuyer, appeler le serveur, fermer l'écran), pas sur la
  // navigation. Une acceptation réussie depuis charteRoute renvoie vers
  // '/' (même règle que pour la vérification d'adresse, voir
  // accountRedirect), ce qui monterait la carte — hors de portée d'un test
  // widget pur (FMTC, wakelock_plus, voir test/app/router_test.dart). La
  // preuve qu'un rider déjà accepté atteint directement une route protégée
  // est apportée par le test suivant, qui ne passe pas par cette étape.
  testWidgets("accepter la charte appelle le serveur, memorise la version et ferme l ecran", (tester) async {
    final api = _ApiFactice();
    final compte = await compteDeTest(charteVersion: null, api: api);

    await tester.runAsync(() async {
      await tester.pumpWidget(
        ChangeNotifierProvider<AccountProvider>.value(
          value: compte,
          child: const MaterialApp(home: CharteScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      final bouton = tester.widget<FilledButton>(find.widgetWithText(FilledButton, "J'accepte"));
      expect(bouton.onPressed, isNotNull);

      // pumpAndSettle n'est pas utilisable après ce tap : un succès ne
      // remet pas `_enCours` à faux (voir CharteScreen._accepter — c'est
      // accountRedirect qui fait disparaître l'écran dans l'application
      // réelle, hors de propos ici puisque ce test le monte sans routeur).
      // Le bouton reste donc en `CircularProgressIndicator` indéterminé,
      // dont l'animation ne s'arrête jamais.
      await tester.tap(find.text("J'accepte"));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    });

    expect(api.chartesAcceptees, ['1.0']);
    expect(compte.charteVersion, '1.0');
  });

  testWidgets('une charte deja acceptee ne reapparait pas, la route protegee est directement atteignable',
      (tester) async {
    final compte = await compteDeTest(charteVersion: '1.0');
    await appDeTest(tester, compte);

    expect(find.byType(CharteScreen), findsNothing);
    expect(find.byType(AccountScreen), findsOneWidget);
  });

  // ── Critique 3a de la revue finale ────────────────────────────────
  //
  // Le mur de la charte est total (SOS et compte a rebours de chute
  // compris) et, avant ce correctif, la seule sortie exigeait le reseau que
  // la panne refusait justement — un rider hors couverture n avait alors
  // aucune sortie. Ce test prouve, au niveau de l ecran, que l acceptation
  // n echoue plus quand le serveur est injoignable.
  testWidgets('hors reseau, accepter la charte ne laisse pas le rider bloque sur un message d echec', (tester) async {
    final api = _ApiFacticeHorsLigne();
    final compte = await compteDeTest(charteVersion: null, api: api);

    await tester.runAsync(() async {
      await tester.pumpWidget(
        ChangeNotifierProvider<AccountProvider>.value(
          value: compte,
          child: const MaterialApp(home: CharteScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.text("J'accepte"));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    });

    expect(find.textContaining("Impossible d'enregistrer"), findsNothing,
        reason: 'une panne reseau ne doit plus etre traitee comme un echec (Critique 3a)');
    expect(compte.charteVersion, '1.0',
        reason: 'l acceptation doit debloquer l acces localement meme sans reseau, '
            'sinon le mur reste ferme devant le SOS sans aucune issue hors ligne');
  });
}
