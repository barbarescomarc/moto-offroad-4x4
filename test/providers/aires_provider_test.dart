// test/providers/aires_provider_test.dart
//
// La règle du provider : réseau d'abord, cache ensuite, jamais l'inverse.
// Mais un serveur injoignable ne vide pas la carte — c'est précisément en
// zone blanche qu'un camping-car cherche une aire.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:moto_offroad/models/aire.dart';
import 'package:moto_offroad/providers/aires_provider.dart';
import 'package:moto_offroad/services/aires_api_client.dart';
import 'package:moto_offroad/services/aires_cache.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _centre = LatLng(43.6, 1.44);

const _aireJson = {
  'id': 'osm:node:1', 'lat': 43.6, 'lng': 1.44, 'source': 'osm',
  'name': 'Aire de Blagnac', 'capacity': 12,
};

Future<Database> Function() _baseMemoire() {
  Database? base;
  return () async {
    if (base != null) return base!;
    base = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 3,
          // Sans cela, sqflite_ffi rend la MEME base en memoire a tous les
          // tests du fichier : le cache d'un test se retrouve dans le
          // suivant, et « cache vide » n'est jamais vide.
          singleInstance: false,
          onCreate: (db, _) async {
            await db.execute('''
              CREATE TABLE aires (
                id TEXT PRIMARY KEY, lat REAL NOT NULL, lng REAL NOT NULL,
                source TEXT NOT NULL, name TEXT, description TEXT,
                services_json TEXT, price_text TEXT, price_eur REAL,
                capacity INTEGER, max_height_m REAL, max_length_m REAL,
                opening_hours TEXT, phone TEXT, website TEXT, updated_at INTEGER)
            ''');
            await db.execute('''
              CREATE TABLE aires_zone (
                id INTEGER PRIMARY KEY AUTOINCREMENT, sud REAL NOT NULL,
                ouest REAL NOT NULL, nord REAL NOT NULL, est REAL NOT NULL,
                charge_le INTEGER NOT NULL)
            ''');
          },
        ));
    return base!;
  };
}

AiresApiClient _client(Future<http.Response> Function(http.Request) repondre) =>
    AiresApiClient(client: MockClient(repondre), baseUrl: 'https://hub.test');

void main() {
  setUpAll(sqfliteFfiInit);

  test('les aires reçues sont affichées et gardées', () async {
    final cache = AiresCache(ouvrir: _baseMemoire());
    final provider = AiresProvider(
      client: _client((_) async =>
          http.Response(jsonEncode({'aires': [_aireJson]}), 200)),
      cache: cache,
    );

    await provider.charger(centre: _centre);

    expect(provider.aires, hasLength(1));
    expect(provider.origine, OrigineAires.reseau);
    expect(await cache.compter(), 1);
  });

  // Le cas qui justifie tout le cache : le pilote est en zone blanche.
  test('serveur injoignable : les aires gardées prennent le relais', () async {
    final ouvrir = _baseMemoire();
    final cache = AiresCache(ouvrir: ouvrir);
    await cache.remplacerZone(
      sud: 43.25, ouest: 1.09, nord: 43.95, est: 1.79,
      aires: [AireModel.depuisJson(Map<String, dynamic>.from(_aireJson))],
    );

    final provider = AiresProvider(
      client: _client((_) async => http.Response('boom', 503)),
      cache: cache,
    );
    await provider.charger(centre: _centre);

    expect(provider.aires, hasLength(1));
    expect(provider.origine, OrigineAires.cache);
    expect(provider.erreur, isNull,
        reason: 'le cache a répondu, ce n\'est pas une erreur');
  });

  test('serveur injoignable et cache vide : on le dit', () async {
    final provider = AiresProvider(
      client: _client((_) async => http.Response('boom', 503)),
      cache: AiresCache(ouvrir: _baseMemoire()),
    );
    await provider.charger(centre: _centre);

    expect(provider.aires, isEmpty);
    expect(provider.origine, OrigineAires.aucune);
    expect(provider.erreur, isNotNull);
  });

  // Une aire supprimée en amont doit disparaître du téléphone aussi, sinon
  // le cache accumule indéfiniment des aires qui n'existent plus.
  test('un rechargement remplace la zone au lieu de l empiler', () async {
    final cache = AiresCache(ouvrir: _baseMemoire());
    var lot = [_aireJson];
    final provider = AiresProvider(
      client: _client((_) async => http.Response(jsonEncode({'aires': lot}), 200)),
      cache: cache,
    );

    await provider.charger(centre: _centre);
    lot = const [];
    await provider.charger(centre: _centre);

    expect(provider.aires, isEmpty);
    expect(await cache.compter(), 0);
  });

  test('un relevé retenu se voit tout de suite sur la fiche', () async {
    final provider = AiresProvider(
      client: _client((_) async =>
          http.Response(jsonEncode({'aires': [_aireJson]}), 200)),
      cache: AiresCache(ouvrir: _baseMemoire()),
    );
    await provider.charger(centre: _centre);

    provider.appliquerReleve('osm:node:1', ChampAire.maxHeightM, 3.2);

    expect(provider.aires.first.maxHeightM, 3.2);
    expect(provider.aires.first.capacity, 12,
        reason: 'le reste de la fiche est intact');
  });

  test('la visibilité se bascule sans rien redemander', () async {
    final provider = AiresProvider(
      client: _client((_) async =>
          http.Response(jsonEncode({'aires': [_aireJson]}), 200)),
      cache: AiresCache(ouvrir: _baseMemoire()),
    );
    await provider.charger(centre: _centre);

    expect(provider.visible, isTrue);
    provider.basculerVisibilite();
    expect(provider.visible, isFalse);
    expect(provider.aires, hasLength(1),
        reason: 'les aires restent en mémoire');
  });

  test('la date de chargement est retenue pour être affichée', () async {
    final cache = AiresCache(ouvrir: _baseMemoire());
    await cache.remplacerZone(
      sud: 43.25, ouest: 1.09, nord: 43.95, est: 1.79,
      aires: [AireModel.depuisJson(Map<String, dynamic>.from(_aireJson))],
      le: DateTime.fromMillisecondsSinceEpoch(1700000000000),
    );

    final quand = await cache.chargeeLe(
        sud: 43.25, ouest: 1.09, nord: 43.95, est: 1.79);

    expect(quand!.millisecondsSinceEpoch, 1700000000000);
  });
}
