// test/services/aires_api_client_test.dart
//
// Le client des aires. Ce qui compte ici : un champ inconnu doit rester nul
// jusque dans le modèle, sans jamais devenir zéro — la fiche doit pouvoir
// écrire « non renseigné ».
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:moto_offroad/models/aire.dart';
import 'package:moto_offroad/services/aires_api_client.dart';

const _aireComplete = {
  'id': 'osm:node:1',
  'lat': 43.6,
  'lng': 1.44,
  'source': 'osm',
  'name': 'Aire de Blagnac',
  'description': 'Au bord du canal.',
  'services': {'eau': true, 'vidange': false},
  'priceText': '11 EUR/24h',
  'priceEur': 11,
  'capacity': 12,
  'maxHeightM': 3.2,
  'openingHours': '24/7',
  'phone': '+33561000000',
  'website': 'https://aire.test',
  'updatedAt': 1700000000000,
};

AiresApiClient _client(Future<http.Response> Function(http.Request) repondre) =>
    AiresApiClient(client: MockClient(repondre), baseUrl: 'https://hub.test');

void main() {
  group('lecture des aires', () {
    test('une aire complète est traduite champ par champ', () async {
      final client = _client((_) async => http.Response(
          jsonEncode({'aires': [_aireComplete], 'attribution': 'OSM'}), 200));

      final aires = await client.dansRectangle(sud: 43, ouest: 1, nord: 44, est: 2);

      expect(aires, hasLength(1));
      final aire = aires.first;
      expect(aire.id, 'osm:node:1');
      expect(aire.name, 'Aire de Blagnac');
      expect(aire.capacity, 12);
      expect(aire.maxHeightM, 3.2);
      expect(aire.services['eau'], isTrue);
      expect(aire.services['vidange'], isFalse);
    });

    // Un zéro se lirait comme « aucune place », un vide comme « gratuit ».
    test('un champ absent reste nul, jamais zéro', () async {
      final client = _client((_) async => http.Response(
          jsonEncode({'aires': [{'id': 'osm:node:2', 'lat': 43.6, 'lng': 1.44}]}), 200));

      final aire = (await client.dansRectangle(sud: 43, ouest: 1, nord: 44, est: 2)).first;

      expect(aire.capacity, isNull);
      expect(aire.priceEur, isNull);
      expect(aire.maxHeightM, isNull);
      expect(aire.services.estVide, isTrue);
    });

    test('la bbox part dans le bon ordre', () async {
      String? bbox;
      final client = _client((requete) async {
        bbox = requete.url.queryParameters['bbox'];
        return http.Response(jsonEncode({'aires': []}), 200);
      });

      await client.dansRectangle(sud: 43, ouest: 1, nord: 44, est: 2);

      expect(bbox, '43.0,1.0,44.0,2.0');
    });

    test('un serveur en erreur lève plutôt que de rendre une liste vide', () async {
      final client = _client((_) async => http.Response('boom', 503));
      expect(
        () => client.dansRectangle(sud: 43, ouest: 1, nord: 44, est: 2),
        throwsA(isA<AiresIndisponibles>()),
      );
    });

    test('une réponse illisible lève aussi', () async {
      final client = _client((_) async => http.Response('<html>', 200));
      expect(
        () => client.dansRectangle(sud: 43, ouest: 1, nord: 44, est: 2),
        throwsA(isA<AiresIndisponibles>()),
      );
    });
  });

  group('relevé du pilote', () {
    test('le champ part sous son nom serveur, avec la date de visite', () async {
      Map<String, dynamic>? corps;
      final client = _client((requete) async {
        corps = jsonDecode(requete.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'etat': 'retenue'}), 201);
      });

      final etat = await client.contribuer(
        aireId: 'osm:node:1',
        champ: ChampAire.maxHeightM,
        valeur: 3.2,
        vuLe: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );

      expect(etat, 'retenue');
      expect(corps!['champ'], 'max_height_m');
      expect(corps!['valeur'], 3.2);
      expect(corps!['vuLe'], 1700000000000);
    });

    test('l identifiant de l aire tient dans l URL', () async {
      Uri? url;
      final client = _client((requete) async {
        url = requete.url;
        return http.Response(jsonEncode({'etat': 'retenue'}), 201);
      });

      await client.contribuer(
          aireId: 'osm:node:1', champ: ChampAire.capacity, valeur: 12);

      expect(url!.path, '/api/aires/osm:node:1/contribution');
    });

    test('sans compte, le message le dit clairement', () async {
      final client = _client((_) async => http.Response('{}', 401));
      expect(
        () => client.contribuer(
            aireId: 'osm:node:1', champ: ChampAire.capacity, valeur: 12),
        throwsA(isA<ContributionRefusee>()
            .having((e) => e.message, 'message', contains('connecte-toi'))),
      );
    });

    test('une valeur refusée remonte la raison du serveur', () async {
      final client = _client((_) async =>
          http.Response(jsonEncode({'error': 'valeur hors bornes'}), 400));
      expect(
        () => client.contribuer(
            aireId: 'osm:node:1', champ: ChampAire.maxHeightM, valeur: 47),
        throwsA(isA<ContributionRefusee>()
            .having((e) => e.message, 'message', 'valeur hors bornes')),
      );
    });

    test('le jeton de compte accompagne le relevé', () async {
      String? autorisation;
      final client = AiresApiClient(
        client: MockClient((requete) async {
          autorisation = requete.headers['Authorization'];
          return http.Response(jsonEncode({'etat': 'retenue'}), 201);
        }),
        baseUrl: 'https://hub.test',
        readToken: () async => 'jeton-test',
      );

      await client.contribuer(
          aireId: 'osm:node:1', champ: ChampAire.capacity, valeur: 12);

      expect(autorisation, 'Bearer jeton-test');
    });
  });

  group('le modèle', () {
    test('une aire sans nom en a quand même un à afficher', () {
      const aire = AireModel(id: 'x', position: LatLng(0, 0), source: 'osm');
      expect(aire.nomAffiche, 'Aire sans nom');
    });

    // Une hauteur inconnue n'est pas un feu vert.
    test('sans hauteur connue, on ne dit pas que ça passe', () {
      const aire = AireModel(id: 'x', position: LatLng(0, 0), source: 'osm');
      expect(aire.passeAvecHauteur(3.0), isNull);
    });

    test('avec une hauteur connue, le verdict est net', () {
      const aire = AireModel(
          id: 'x', position: LatLng(0, 0), source: 'osm', maxHeightM: 2.8);
      expect(aire.passeAvecHauteur(2.5), isTrue);
      expect(aire.passeAvecHauteur(3.2), isFalse);
    });

    test('un aller-retour par SQLite conserve les champs', () {
      const aire = AireModel(
        id: 'osm:node:1', position: LatLng(43.6, 1.44), source: 'osm',
        name: 'Aire', capacity: 12, maxHeightM: 3.2,
        services: AireServices({'eau': true}),
      );
      final relue = AireModel.depuisLigneSqlite(aire.versLigneSqlite());
      expect(relue.name, 'Aire');
      expect(relue.capacity, 12);
      expect(relue.maxHeightM, 3.2);
      expect(relue.services['eau'], isTrue);
    });
  });
}
