import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:moto_offroad/app/router.dart';
import 'package:moto_offroad/models/shared_trace.dart';
import 'package:moto_offroad/providers/shared_traces_provider.dart';
import 'package:moto_offroad/screens/rides/my_publications_screen.dart';
import 'package:moto_offroad/screens/rides/shared_traces_panel.dart';
import 'package:moto_offroad/services/shared_traces_api_client.dart';

// Fiche minimale, avec les seuls champs que ces tests font varier — même
// esprit que la fabrique de shared_traces_panel_test.dart.
SharedTraceSummary resume(
  String id, {
  String? nom,
  int downloadCount = 0,
  bool hidden = false,
  String? hiddenReason,
}) =>
    SharedTraceSummary(
      id: id,
      name: nom ?? 'Trace $id',
      authorName: 'Un rider',
      vehicle: TraceVehicle.moto,
      difficulty: TraceDifficulty.moyen,
      distanceM: 12400,
      publishedAt: DateTime(2026, 1, 1),
      downloadCount: downloadCount,
      startLat: 43.6,
      startLng: 1.44,
      hidden: hidden,
      hiddenReason: hiddenReason,
    );

// Double du client HTTP : capture les modifications et dépublications, sans
// jamais faire de vraie requête réseau. `mine()` sert une liste fixée par
// le test.
class _ApiFactice extends SharedTracesApiClient {
  _ApiFactice() : super(client: MockClient((_) async => http.Response('', 200)), readToken: () async => 'jeton');

  List<SharedTraceSummary> miennes = [];
  final modifiees = <Map<String, Object?>>[];
  final depubliees = <String>[];

  // Permettent à un test de forcer l'échec d'un appel précis, sans jamais
  // faire de vraie requête réseau — voir les tests de la Correction 2
  // (fix round 1) plus bas.
  Object? erreurMine;
  Object? erreurUpdate;
  Object? erreurUnpublish;

  @override
  Future<List<SharedTraceSummary>> mine() async {
    if (erreurMine != null) throw erreurMine!;
    return miennes;
  }

  @override
  Future<void> update(
    String id, {
    String? name,
    String? description,
    String? authorName,
    TraceVehicle? vehicle,
    TraceDifficulty? difficulty,
  }) async {
    if (erreurUpdate != null) throw erreurUpdate!;
    modifiees.add({
      'id': id,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (authorName != null) 'authorName': authorName,
      if (vehicle != null) 'vehicle': vehicle,
      if (difficulty != null) 'difficulty': difficulty,
    });
  }

  @override
  Future<void> unpublish(String id) async {
    if (erreurUnpublish != null) throw erreurUnpublish!;
    depubliees.add(id);
  }
}

Widget mesPublicationsDeTest(SharedTracesApiClient api) => MaterialApp(home: MyPublicationsScreen(api: api));

void main() {
  testWidgets('mes publications montrent le compteur et l etat retire', (tester) async {
    final api = _ApiFactice()
      ..miennes = [
        resume('t1', nom: 'Boucle', downloadCount: 12),
        resume('t2', nom: 'Crete', hidden: true, hiddenReason: 'terrain prive'),
      ];
    await tester.pumpWidget(mesPublicationsDeTest(api));
    await tester.pumpAndSettle();

    expect(find.text('Boucle'), findsOneWidget);
    expect(find.textContaining('12'), findsWidgets);
    expect(find.textContaining('Retirée du partage'), findsOneWidget);
    expect(find.textContaining('terrain prive'), findsOneWidget);
  });

  testWidgets('modifier la fiche envoie seulement les champs changes', (tester) async {
    final api = _ApiFactice()..miennes = [resume('t1', nom: 'Boucle')];
    await tester.pumpWidget(mesPublicationsDeTest(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Modifier la fiche'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('champ_description')), 'Praticable en ete seulement');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();

    expect(api.modifiees.single['id'], 't1');
    expect(api.modifiees.single['description'], 'Praticable en ete seulement');
    expect(api.modifiees.single.containsKey('name'), isFalse);
  });

  testWidgets('depublier demande confirmation avant d appeler le serveur', (tester) async {
    final api = _ApiFactice()..miennes = [resume('t1', nom: 'Boucle')];
    await tester.pumpWidget(mesPublicationsDeTest(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Dépublier'));
    await tester.pumpAndSettle();
    expect(api.depubliees, isEmpty); // rien tant que la confirmation n'est pas donnee

    await tester.tap(find.text('Dépublier définitivement'));
    await tester.pumpAndSettle();
    expect(api.depubliees, ['t1']);
  });

  // ── Fix round 1, Finding 2 (Important) ────────────────────────
  // Avant ce correctif : un échec de update()/unpublish() levait après que
  // la feuille ou le dialogue s'était déjà refermé, sans rien dire au
  // rider ; et un échec de mine() laissait le FutureBuilder tourner
  // indéfiniment, sans branche d'erreur.

  testWidgets('un echec de chargement affiche un message et permet de reessayer', (tester) async {
    final api = _ApiFactice()..erreurMine = const SharedTracesException(500, 'Le serveur ne repond pas');
    await tester.pumpWidget(mesPublicationsDeTest(api));
    await tester.pumpAndSettle();

    expect(find.textContaining('Le serveur ne repond pas'), findsOneWidget);

    api.erreurMine = null;
    api.miennes = [resume('t1', nom: 'Boucle')];
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();

    expect(find.text('Boucle'), findsOneWidget);
  });

  testWidgets('un echec de modification previent le rider au lieu de le laisser croire que ca a marche',
      (tester) async {
    final api = _ApiFactice()
      ..miennes = [resume('t1', nom: 'Boucle')]
      ..erreurUpdate = const SharedTracesException(500, 'Le serveur ne repond pas');
    await tester.pumpWidget(mesPublicationsDeTest(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Modifier la fiche'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('champ_description')), 'Nouvelle description');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Le serveur ne repond pas'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('un echec de depublication previent le rider au lieu de le laisser croire que ca a marche',
      (tester) async {
    final api = _ApiFactice()
      ..miennes = [resume('t1', nom: 'Boucle')]
      ..erreurUnpublish = const SharedTracesException(500, 'Le serveur ne repond pas');
    await tester.pumpWidget(mesPublicationsDeTest(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Dépublier'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dépublier définitivement'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Le serveur ne repond pas'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // Le brief n'exigeait pas explicitement ce test, mais le lot a déjà été
  // pris en défaut deux fois sur des écrans finis mais reliés à rien (voir
  // publish_trace_screen_test.dart et shared_traces_panel_test.dart) : un
  // test qui tape réellement sur « Mes publications » depuis le volet
  // Partagées et vérifie l'écran qui apparaît, pas seulement que les deux
  // chaînes de route se correspondent à la lecture.
  testWidgets('le bouton Mes publications du volet Partagees mene a l ecran', (tester) async {
    final sharedTraces = SharedTracesProvider(_ApiFactice());
    await sharedTraces.setReference(const LatLng(43.6, 1.44));

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: SharedTracesPanel(estVisible: true)),
        ),
        GoRoute(
          path: AppRoutes.myPublications,
          builder: (_, __) => MyPublicationsScreen(api: _ApiFactice()),
        ),
      ],
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: sharedTraces,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MyPublicationsScreen), findsNothing);

    await tester.tap(find.text('Mes publications'));
    await tester.pumpAndSettle();

    expect(find.byType(MyPublicationsScreen), findsOneWidget);
    expect(find.byType(SharedTracesPanel), findsNothing);
  });
}
