import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:moto_offroad/models/ride.dart';
import 'package:moto_offroad/models/shared_trace.dart';
import 'package:moto_offroad/providers/rides_provider.dart';
import 'package:moto_offroad/providers/settings_provider.dart';
import 'package:moto_offroad/screens/rides/publish_trace_screen.dart';
import 'package:moto_offroad/screens/rides/ride_detail_screen.dart';
import 'package:moto_offroad/services/ride_database.dart';
import 'package:moto_offroad/services/ride_repository.dart';
import 'package:moto_offroad/services/shared_traces_api_client.dart';

// L'aperçu de la fiche est un vrai FlutterMap : son cache tuiles intégré
// (activé par défaut, voulu tel quel en production — voir publish_trace_
// screen.dart) appelle path_provider, dont aucune implémentation n'est
// enregistrée en test. On fournit une implémentation factice plutôt que de
// désactiver le cache dans l'écran lui-même : ce que le test contourne doit
// rester dans le test.
class _PathProviderFactice extends PathProviderPlatform {
  @override
  Future<String?> getApplicationCachePath() async =>
      (await Directory.systemTemp.createTemp('publish_trace_screen_test_')).path;
}

// ── Fabriques ─────────────────────────────────────────────────
Ride rideFactice({String id = 'r1', String? sharedTraceId}) => Ride(
      id: id,
      name: 'Sortie test',
      startedAt: DateTime(2026, 9, 1, 10, 0),
      source: RideSource.recorded,
      status: RideStatus.finished,
      stats: RideStats.empty,
      sharedTraceId: sharedTraceId,
    );

// Points en ligne droite, distincts d'une décimale à chaque pas : seul le
// tout premier point a une latitude qui commence par "43.600" (43.6000000
// une fois formaté par GpxService avec 7 décimales), ce qui permet de
// vérifier que le recadrage l'a bien exclu sans dépendre d'une valeur
// arbitraire ailleurs dans le tracé.
List<RidePoint> pointsFactices(int n, {String rideId = 'r1'}) => [
      for (int i = 0; i < n; i++)
        RidePoint(
          rideId: rideId,
          seq: i,
          segment: 0,
          lat: 43.60 + i * 0.001,
          lng: 1.44 + i * 0.001,
          speedKmh: 10,
          timestamp: DateTime(2026, 9, 1, 10, 0).add(Duration(minutes: i)),
        ),
    ];

// Double du client HTTP : capture les publications ou lève l'échec voulu,
// jamais de vraie requête réseau.
class _ApiFactice extends SharedTracesApiClient {
  _ApiFactice() : super(client: MockClient((_) async => http.Response('', 200)), readToken: () async => 'jeton');

  final publiees = <Map<String, Object?>>[];
  Object? erreur;

  @override
  Future<String> publish({
    required String name,
    required String description,
    required String authorName,
    required TraceVehicle vehicle,
    required TraceDifficulty difficulty,
    required String gpx,
    String licenceVersion = SharedTracesApiClient.licenceVersion,
  }) async {
    if (erreur != null) throw erreur!;
    publiees.add({
      'name': name,
      'description': description,
      'authorName': authorName,
      'vehicle': vehicle,
      'difficulty': difficulty,
      'gpx': gpx,
      'licenceVersion': licenceVersion,
    });
    return 'trace-nouvelle';
  }
}

// pumpAndSettle() attend qu'aucune frame ne soit plus programmée — un critère
// qui ne se vérifie jamais tant que l'indicateur de chargement
// (CircularProgressIndicator, tourne indéfiniment par construction) reste à
// l'écran, même une seule frame. Ce couple pump + vraie pause + pump laisse
// le temps réel (on est dans tester.runAsync) à la lecture sqflite ffi de
// revenir, sans exiger l'arrêt d'une animation qui n'a pas vocation à
// s'arrêter.
Future<void> asseoir(WidgetTester tester) async {
  await tester.pump();
  await Future<void>.delayed(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 200));
}

// La fiche (aperçu + curseurs + trois champs + deux SegmentedButton + les
// conditions + le bouton) dépasse la hauteur par défaut de la surface de
// test (600 logical px) : ListView ne matérialise que les éléments proches
// de la zone visible, et même une fois matérialisé un widget partiellement
// hors zone peut rater un tap (hit-test manqué en bord de viewport). Agrandir
// la surface évite tout défilement et ses fragilités plutôt que de les
// contourner.
void agrandirEcran(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  sqfliteFfiInit();
  setUpAll(() => PathProviderPlatform.instance = _PathProviderFactice());

  // Une seule base par test, refermée à la fin — même stratégie que
  // rides_provider_test.dart et shared_trace_detail_screen_test.dart. Le
  // premier jet de ce fichier ouvrait une base ':memory:' neuve par appel
  // de fabrique sans jamais la refermer ; l'accumulation de connexions FFI
  // non refermées est ce qui faisait pendre le tout premier test du
  // fichier (blocage natif hors de portée du timeout du test runner,
  // signature `dart:isolate _RawReceivePort._handleMessage`).
  late Database db;
  late RideRepository repo;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: RideDatabase.schemaVersion, onCreate: RideDatabase.onCreate),
    );
    repo = RideRepository(db);
  });
  tearDown(() async => db.close());

  Future<RidesProvider> providerAvec(Ride ride, List<RidePoint> points) async {
    await repo.insertRide(ride);
    await repo.appendPoints(points);
    final provider = RidesProvider(repository: repo);
    await provider.refresh();
    return provider;
  }

  Future<Widget> ficheSortieDeTest(Ride ride) async {
    final provider = await providerAvec(ride, []);
    return ChangeNotifierProvider<RidesProvider>.value(
      value: provider,
      child: MaterialApp(home: RideDetailScreen(rideId: ride.id)),
    );
  }

  // Même fiche, mais routée pour de vrai (GoRouter avec les deux mêmes
  // chemins que router.dart) : seule façon de prouver que le bouton Publier
  // mène réellement à PublishTraceScreen, pas seulement que les deux chaînes
  // de route se correspondent à la lecture.
  Future<Widget> ficheAvecNavigationDeTest(
    Ride ride,
    List<RidePoint> points, {
    SharedTracesApiClient? api,
  }) async {
    final ridesProvider = await providerAvec(ride, points);
    final settings = SettingsProvider();
    await settings.load();
    final router = GoRouter(
      initialLocation: '/rides/${ride.id}',
      routes: [
        GoRoute(
          path: '/rides/:id',
          builder: (_, state) => RideDetailScreen(rideId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: '/rides/:id/publier',
          builder: (_, state) => PublishTraceScreen(
            rideId: state.pathParameters['id']!,
            api: api ?? _ApiFactice(),
          ),
        ),
      ],
    );
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<RidesProvider>.value(value: ridesProvider),
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  Future<Widget> ecranPublicationDeTest(
    Ride ride,
    List<RidePoint> points, {
    SharedTracesApiClient? api,
  }) async {
    final ridesProvider = await providerAvec(ride, points);
    final settings = SettingsProvider();
    await settings.load();
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<RidesProvider>.value(value: ridesProvider),
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
      ],
      child: MaterialApp(
        home: PublishTraceScreen(rideId: ride.id, api: api ?? _ApiFactice()),
      ),
    );
  }

  // Chaque test ci-dessous est enveloppé dans tester.runAsync : la fiche
  // comme l'écran de publication lisent la base sqflite ffi réelle pendant
  // le pump (RideDetailScreen via son FutureBuilder, PublishTraceScreen via
  // _chargerPoints), et ces opérations passent par un isolat d'arrière-plan
  // authentique. Sans runAsync, cette lecture ne progresse jamais dans la
  // zone de temps simulé de testWidgets — le pump ne se termine tout
  // simplement pas (voir le même constat, déjà posé, dans
  // shared_trace_detail_screen_test.dart et shared_traces_panel_test.dart).

  testWidgets('une sortie telechargee ne propose pas de la republier', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(await ficheSortieDeTest(rideFactice(sharedTraceId: 't42')));
      await asseoir(tester);
      expect(find.text('Publier'), findsNothing);
    });
  });

  testWidgets('une sortie enregistree propose de la publier', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(await ficheSortieDeTest(rideFactice()));
      await asseoir(tester);
      expect(find.text('Publier'), findsOneWidget);
    });
  });

  // Deux écrans finis mais reliés à rien : déjà arrivé deux fois dans ce lot.
  // Un test qui tape réellement sur Publier et vérifie l'écran qui apparaît,
  // pas seulement que les deux chaînes de route se correspondent.
  testWidgets('taper sur Publier mene a PublishTraceScreen', (tester) async {
    SharedPreferences.setMockInitialValues({'partage_avertissement_vu': true});
    await tester.runAsync(() async {
      await tester.pumpWidget(await ficheAvecNavigationDeTest(rideFactice(), pointsFactices(10)));
      await asseoir(tester);
      expect(find.byType(PublishTraceScreen), findsNothing);

      await tester.tap(find.text('Publier'));
      await asseoir(tester);

      // context.push empile la route : RideDetailScreen reste monté sous
      // PublishTraceScreen (pile de navigation), c'est PublishTraceScreen
      // qui doit être au sommet — visible et destinataire des taps.
      expect(find.byType(PublishTraceScreen), findsOneWidget);
      expect(find.text('Publier la trace'), findsOneWidget);
    });
  });

  // Trouvaille critique de la relecture : ni _apercu (sublist, point central)
  // ni le recadrage n'ont de sens sous 2 points. Une sortie interrompue par
  // un crash de l'enregistrement, ou un import avorté, peut légitimement
  // laisser une sortie à 0 ou 1 point — et RideDetailScreen propose Publier
  // pour toute sortie non téléchargée, quel que soit son nombre de points.
  testWidgets('une sortie sans point affiche le message, ne plante pas', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(await ecranPublicationDeTest(rideFactice(), []));
      await asseoir(tester);
      expect(find.textContaining("n'a pas assez de points"), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('une sortie a un seul point affiche le message, ne plante pas', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(await ecranPublicationDeTest(rideFactice(), pointsFactices(1)));
      await asseoir(tester);
      expect(find.textContaining("n'a pas assez de points"), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('l avertissement de premiere publication apparait une seule fois', (tester) async {
    agrandirEcran(tester);
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(await ecranPublicationDeTest(rideFactice(), pointsFactices(10)));
      await asseoir(tester);
      expect(find.textContaining('devant chez toi'), findsOneWidget);
      await tester.tap(find.text('Compris'));
      await asseoir(tester);

      await tester.pumpWidget(await ecranPublicationDeTest(rideFactice(), pointsFactices(10)));
      await asseoir(tester);
      expect(find.textContaining('devant chez toi'), findsNothing);
    });
  });

  // Adapté du brief : la case d'acceptation des conditions (exigence
  // légale non négociable — voir docs/legal/conditions-publication-traces.md)
  // doit être cochée pour que Publier fasse quoi que ce soit ; le brief
  // d'origine ne le faisait pas encore. Voir aussi le test dédié plus bas
  // qui pin cette règle indépendamment.
  testWidgets('publier envoie la trace recadree et la fiche saisie', (tester) async {
    agrandirEcran(tester);
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({'partage_avertissement_vu': true});
      final api = _ApiFactice();
      await tester.pumpWidget(await ecranPublicationDeTest(rideFactice(), pointsFactices(10), api: api));
      await asseoir(tester);

      await tester.enterText(find.byKey(const Key('champ_description')), 'Pistes forestieres, deux gues');
      await tester.tap(find.text('4x4'));
      await tester.tap(find.text('Difficile'));
      await tester.drag(find.byKey(const Key('curseur_debut')), const Offset(60, 0));
      await tester.tap(find.byKey(const Key('case_acceptation')));
      await asseoir(tester);
      await tester.tap(find.text('Publier'));
      await asseoir(tester);

      expect(api.publiees.single['vehicle'], TraceVehicle.quatreQuatre);
      expect(api.publiees.single['difficulty'], TraceDifficulty.difficile);
      expect(api.publiees.single['description'], 'Pistes forestieres, deux gues');
      // La version des conditions acceptées doit parvenir au serveur : c'est
      // la trace écrite du consentement, elle ne doit jamais dépendre en
      // silence d'une valeur par défaut.
      expect(api.publiees.single['licenceVersion'], '1.0');
      // Le depart a ete rogne : le premier point d'origine n'est plus dans le GPX.
      expect((api.publiees.single['gpx'] as String).contains('43.600'), isFalse);
    });
  });

  testWidgets('une description vide bloque la publication', (tester) async {
    agrandirEcran(tester);
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({'partage_avertissement_vu': true});
      final api = _ApiFactice();
      await tester.pumpWidget(await ecranPublicationDeTest(rideFactice(), pointsFactices(10), api: api));
      await asseoir(tester);
      await tester.tap(find.byKey(const Key('case_acceptation')));
      await asseoir(tester);
      await tester.tap(find.text('Publier'));
      await asseoir(tester);
      expect(api.publiees, isEmpty);
      expect(find.textContaining('description'), findsWidgets);
    });
  });

  testWidgets('sans acceptation des conditions, Publier reste inactif', (tester) async {
    agrandirEcran(tester);
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({'partage_avertissement_vu': true});
      await tester.pumpWidget(await ecranPublicationDeTest(rideFactice(), pointsFactices(10)));
      await asseoir(tester);
      final avant = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Publier'));
      expect(avant.onPressed, isNull);

      await tester.tap(find.byKey(const Key('case_acceptation')));
      await asseoir(tester);
      final apres = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Publier'));
      expect(apres.onPressed, isNotNull);
    });
  });

  testWidgets('le lien conditions de publication ouvre le texte complet', (tester) async {
    agrandirEcran(tester);
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({'partage_avertissement_vu': true});
      await tester.pumpWidget(await ecranPublicationDeTest(rideFactice(), pointsFactices(10)));
      await asseoir(tester);
      await tester.tap(find.text('conditions de publication'));
      await asseoir(tester);
      expect(find.textContaining("droits d'exploitation"), findsWidgets);
    });
  });
}
