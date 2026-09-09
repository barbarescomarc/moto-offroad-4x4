import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:convert';
import 'package:provider/provider.dart';
import 'package:moto_offroad/app/router.dart';
import 'package:moto_offroad/providers/account_provider.dart';
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
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

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

  // Complément naturel du premier test : un rider connecté et vérifié ne
  // doit plus être bloqué par le mur d'inscription. La carte elle-même
  // (MapScreen, à l'intérieur du ShellRoute) n'a pas pu servir de cible ici
  // — une tentative directe échoue sur `ProviderNotFoundException:
  // MapProvider`, MainShell/MapScreen exigeant une dizaine de providers
  // (MapProvider, TraceProvider, GroupProvider, FuelProvider, SoloProvider,
  // SettingsProvider, FavoritesProvider, GuidanceProvider,
  // PoiSearchProvider, RideRepository) ainsi que des plugins natifs
  // (MapTileCache/FMTC, backend ObjectBox, wakelock_plus, PackageInfo) que
  // les corriger un par un ne suffit pas forcément à lever en test widget
  // pur. À la place, `/sos` — une route hors ShellRoute, sans aucune
  // dépendance Provider — sert de témoin : elle vérifie exactement la même
  // logique de redirection (`accountRedirect` avec statut connecté), sans
  // la lourdeur de la carte.
  testWidgets(
      'un rider connecte et verifie atteint un ecran hors mur, pas l ecran d accueil du compte',
      (tester) async {
    await AccountStorage().writeToken('jeton');
    final compte = AccountProvider(
      api: AccountApiClient(
        baseUrl: 'https://exemple.test',
        client: MockClient((_) async => http.Response(
            jsonEncode({'email': 'rider@example.test', 'verified': true}), 200)),
      ),
      storage: AccountStorage(),
    );
    await compte.restore(); // jeton valide, adresse vérifiée : statut connecté

    await tester.pumpWidget(
      ChangeNotifierProvider<AccountProvider>.value(
        value: compte,
        child: MaterialApp.router(
          routerConfig: buildAppRouter(initialLocation: '/sos'),
        ),
      ),
    );
    // Pas de `pumpAndSettle` ici : SosScreen affiche un
    // CircularProgressIndicator tant que la position GPS n'est pas
    // disponible (jamais, en test), une animation qui ne « s'installe »
    // donc jamais. Quelques frames suffisent pour vérifier l'écran affiché.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(SosScreen), findsOneWidget);
    expect(find.byKey(const Key('ecran-bienvenue')), findsNothing);
  });
}
