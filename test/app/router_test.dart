import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:provider/provider.dart';
import 'package:moto_offroad/app/router.dart';
import 'package:moto_offroad/providers/account_provider.dart';
import 'package:moto_offroad/providers/map_provider.dart';
import 'package:moto_offroad/providers/settings_provider.dart';
import 'package:moto_offroad/services/account_api_client.dart';
import 'package:moto_offroad/services/account_storage.dart';
import 'package:moto_offroad/screens/map/map_screen.dart';
import 'package:moto_offroad/screens/sos/sos_screen.dart';

// Ce fichier prouve que le mur d'inscription est réellement branché dans le
// GoRouter de l'application — pas seulement que `accountRedirect` (testée
// en fonction pure dans account_gate_test.dart) se comporte bien en
// isolation, mais que son résultat gouverne vraiment la destination
// affichée une fois le routeur monté avec un vrai AccountProvider.
//
// `buildAppRouter()` construit un routeur indépendant à chaque appel : les
// tests n'ont pas à se soucier de l'état laissé par un test précédent dans
// l'instance globale [appRouter] utilisée par l'application.
void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    // Depuis le round 2 (Tache 23C), un compte sans charteVersion confirme
    // (register()/login() qui aboutit sur `null`) efface desormais le
    // filet local, meme quand il n y avait rien a effacer : cet appel a
    // SharedPreferences non simule bloquait indefiniment pumpAndSettle()
    // dans ce fichier (meme famille de piege que le mock deja pose plus
    // bas pour MainShell/PackageInfo).
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
      'un rider deconnecte atterrit sur l ecran d accueil du compte, pas sur la carte',
      (tester) async {
    final compte = AccountProvider(
      api: AccountApiClient(
        baseUrl: 'https://exemple.test',
        client: MockClient((_) async => http.Response('{}', 200)),
      ),
      storage: AccountStorage(),
    );
    await compte.restore(); // aucun jeton stocké : statut déconnecté

    await tester.pumpWidget(
      ChangeNotifierProvider<AccountProvider>.value(
        value: compte,
        child: MaterialApp.router(routerConfig: buildAppRouter()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ecran-bienvenue')), findsOneWidget);
    expect(find.byType(MapScreen), findsNothing);
  });

  // Complément du premier test, dans l'autre sens : un rider avec un compte
  // mais une adresse non vérifiée doit être ramené sur l'écran d'attente
  // depuis N'IMPORTE QUEL écran — pas seulement les écrans de compte. `/sos`
  // sert de départ : une route hors ShellRoute, sans aucune dépendance
  // Provider (contrairement à MapScreen/MainShell, qui exigent une dizaine
  // de providers et plusieurs plugins natifs — MapTileCache/FMTC avec son
  // backend ObjectBox, wakelock_plus, PackageInfo — hors de portée d'un test
  // widget pur ; une tentative directe échoue sur
  // `ProviderNotFoundException: MapProvider`).
  //
  // Ce test discrimine réellement le branchement : sans lui, `/sos` est une
  // route déclarée sans aucune redirection propre, donc atteignable
  // directement — seul le `redirect` du routeur peut en détourner un rider
  // non vérifié vers `/verification`.
  testWidgets(
      'un rider non verifie est renvoye vers l ecran de verification, meme depuis un ecran hors mur',
      (tester) async {
    final compte = AccountProvider(
      api: AccountApiClient(
        baseUrl: 'https://exemple.test',
        client: MockClient((_) async =>
            http.Response(jsonEncode({'token': 'jeton', 'verified': false}), 201)),
      ),
      storage: AccountStorage(),
    );
    await compte.register(email: 'rider@example.test', password: 'dix caracteres');
    expect(compte.status, AccountStatus.nonVerifie);

    await tester.pumpWidget(
      ChangeNotifierProvider<AccountProvider>.value(
        value: compte,
        child: MaterialApp.router(
          routerConfig: buildAppRouter(initialLocation: '/sos'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ecran-verification')), findsOneWidget);
    expect(find.byType(SosScreen), findsNothing);
  });

  // I7 de la revue finale : pendant le tout premier instant du démarrage
  // (AccountProvider construit mais restore() pas encore résolu), la carte
  // ne doit pas se monter — sinon son initState demande aussitôt la
  // permission de localisation, avant même que le mur d'inscription ait pu
  // s'appliquer. Ce test se garde bien d'appeler restore() : c'est
  // exactement l'instant qu'il prouve.
  testWidgets(
      'pendant le chargement du compte, un ecran neutre remplace la carte',
      (tester) async {
    // MainShell (voir router.dart) interroge PackageInfo/SharedPreferences
    // pour les mises à jour dès son initState, quel que soit l'écran
    // affiché dans le ShellRoute — sans quoi cet appel non simulé lève une
    // MissingPluginException dans ce test.
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'test',
      packageName: 'test',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );

    final compte = AccountProvider(
      api: AccountApiClient(
        baseUrl: 'https://exemple.test',
        client: MockClient((_) async => http.Response('{}', 200)),
      ),
      storage: AccountStorage(),
    );
    // Ne pas appeler restore() : le statut reste "chargement", sa valeur
    // initiale — voir AccountProvider._status.

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AccountProvider>.value(value: compte),
          // MainShell les regarde (barre de navigation, réglage
          // d'auto-masquage) quel que soit l'écran affiché en dessous.
          ChangeNotifierProvider(create: (_) => MapProvider()),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ],
        child: MaterialApp.router(routerConfig: buildAppRouter()),
      ),
    );
    // pump() et non pumpAndSettle() : l'indicateur de chargement anime en
    // boucle, et la vérification des mises à jour part sur un vrai appel
    // réseau (silencieux en cas d'échec, voir UpdateChecker) — pumpAndSettle()
    // ne se terminerait jamais.
    await tester.pump();

    expect(find.byKey(const Key('ecran-chargement-compte')), findsOneWidget);
    expect(find.byType(MapScreen), findsNothing);
  });
}
