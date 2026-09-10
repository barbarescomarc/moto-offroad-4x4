import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:moto_offroad/models/ride.dart';
import 'package:moto_offroad/providers/rides_provider.dart';
import 'package:moto_offroad/screens/rides/ride_detail_screen.dart';
import 'package:moto_offroad/services/ride_database.dart';
import 'package:moto_offroad/services/ride_repository.dart';

// _RideMap embarque une TileLayer FlutterMap, qui interroge path_provider
// pour son cache de tuiles disque — même pare-feu que
// publish_trace_screen_test.dart, sans lequel une MissingPluginException
// asynchrone (donc rattachée arbitrairement à un test ultérieur) apparaît
// après coup.
class _PathProviderFactice extends PathProviderPlatform {
  @override
  Future<String?> getApplicationCachePath() async =>
      (await Directory.systemTemp.createTemp('ride_detail_screen_test_')).path;
}

RidePoint pointFactice(String rideId, int seq) => RidePoint(
      rideId: rideId,
      seq: seq,
      segment: 0,
      lat: 43.6 + seq * 0.001,
      lng: 1.44 + seq * 0.001,
      speedKmh: 20,
      timestamp: DateTime(2026, 1, 1).add(Duration(seconds: seq)),
    );

Ride rideFactice({required String id, required RideSource source, String? sharedTraceId}) => Ride(
      id: id,
      name: 'Sortie test',
      startedAt: DateTime(2026, 1, 1),
      endedAt: DateTime(2026, 1, 1, 1),
      source: source,
      status: RideStatus.finished,
      stats: RideStats.empty,
      sharedTraceId: sharedTraceId,
    );

Future<RideRepository> depotDeTest() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(version: RideDatabase.schemaVersion, onCreate: RideDatabase.onCreate),
  );
  return RideRepository(db);
}

// pumpAndSettle() n'est pas utilisable ici : RideDetailScreen appelle
// provider.pointsOf(rideId) directement dans son FutureBuilder (un nouveau
// Future à chaque reconstruction), et sa carte tente de vraies requêtes
// réseau (tuiles OSM) qui échouent puis se reconstruisent en boucle dans
// cet environnement de test — même pare-feu que publish_trace_screen_test
// .dart. Ce couple pump + vraie pause + pump laisse le temps réel (on est
// dans tester.runAsync) à la lecture sqflite ffi de revenir.
Future<void> asseoir(WidgetTester tester) async {
  await tester.pump();
  await Future<void>.delayed(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  setUpAll(() => PathProviderPlatform.instance = _PathProviderFactice());

  // Trouvaille mineure de la revue finale (spec §7.3) : une sortie
  // téléchargée depuis le catalogue partagé n'affichait que "Importée" sur
  // sa fiche, indiscernable d'un import GPX ordinaire — sharedTraceId ne
  // servait qu'à masquer le bouton Publier.

  testWidgets('une sortie telechargee depuis le partage affiche son origine', (tester) async {
    await tester.runAsync(() async {
      final repo = await depotDeTest();
      final ride = rideFactice(id: 'r1', source: RideSource.imported, sharedTraceId: 'trace-42');
      await repo.insertRide(ride);
      await repo.appendPoints([pointFactice('r1', 0), pointFactice('r1', 1)]);

      final provider = RidesProvider(repository: repo);
      await provider.refresh();

      await tester.pumpWidget(
        ChangeNotifierProvider<RidesProvider>.value(
          value: provider,
          child: const MaterialApp(home: RideDetailScreen(rideId: 'r1')),
        ),
      );
      await asseoir(tester);

      expect(find.text('téléchargée depuis le partage'), findsOneWidget);
      // Une sortie qui ne lui appartient pas ne peut pas être republiée.
      expect(find.text('Publier'), findsNothing);
    });
  });

  testWidgets('un import GPX ordinaire (sans sharedTraceId) reste "Importee"', (tester) async {
    await tester.runAsync(() async {
      final repo = await depotDeTest();
      final ride = rideFactice(id: 'r2', source: RideSource.imported);
      await repo.insertRide(ride);
      await repo.appendPoints([pointFactice('r2', 0), pointFactice('r2', 1)]);

      final provider = RidesProvider(repository: repo);
      await provider.refresh();

      await tester.pumpWidget(
        ChangeNotifierProvider<RidesProvider>.value(
          value: provider,
          child: const MaterialApp(home: RideDetailScreen(rideId: 'r2')),
        ),
      );
      await asseoir(tester);

      expect(find.text('Importée'), findsOneWidget);
      expect(find.text('téléchargée depuis le partage'), findsNothing);
    });
  });

  testWidgets('une sortie enregistree affiche toujours "Enregistree"', (tester) async {
    await tester.runAsync(() async {
      final repo = await depotDeTest();
      final ride = rideFactice(id: 'r3', source: RideSource.recorded);
      await repo.insertRide(ride);
      await repo.appendPoints([pointFactice('r3', 0), pointFactice('r3', 1)]);

      final provider = RidesProvider(repository: repo);
      await provider.refresh();

      await tester.pumpWidget(
        ChangeNotifierProvider<RidesProvider>.value(
          value: provider,
          child: const MaterialApp(home: RideDetailScreen(rideId: 'r3')),
        ),
      );
      await asseoir(tester);

      expect(find.text('Enregistrée'), findsOneWidget);
    });
  });
}
