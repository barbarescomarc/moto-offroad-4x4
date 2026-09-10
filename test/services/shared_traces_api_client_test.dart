import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moto_offroad/models/shared_trace.dart';
import 'package:moto_offroad/services/shared_traces_api_client.dart';

SharedTracesApiClient clientAvec(MockClient mock, {String? jeton = 'jeton'}) =>
    SharedTracesApiClient(client: mock, baseUrl: 'https://exemple.test', readToken: () async => jeton);

void main() {
  test('publish envoie la fiche et rend l identifiant', () async {
    late http.Request capturee;
    final api = clientAvec(MockClient((req) async {
      capturee = req;
      return http.Response('{"id":"t42"}', 201);
    }));

    final id = await api.publish(
      name: 'Boucle', description: 'Pistes', authorName: 'Marco31',
      vehicle: TraceVehicle.quatreQuatre, difficulty: TraceDifficulty.facile, gpx: '<gpx/>',
    );

    expect(id, 't42');
    expect(capturee.headers['authorization'], 'Bearer jeton');
    final corps = jsonDecode(capturee.body) as Map<String, dynamic>;
    expect(corps['vehicle'], '4x4');
    expect(corps['difficulty'], 'facile');
    expect(corps['gpx'], '<gpx/>');
  });

  // Sans licenceVersion, le serveur refuse la publication (400 « conditions
  // de publication non acceptees ») : le client doit toujours l'envoyer.
  test('publish envoie toujours la version de la licence acceptee', () async {
    late http.Request capturee;
    final api = clientAvec(MockClient((req) async {
      capturee = req;
      return http.Response('{"id":"t1"}', 201);
    }));

    await api.publish(
      name: 'Boucle', description: 'Pistes', authorName: 'Marco31',
      vehicle: TraceVehicle.moto, difficulty: TraceDifficulty.facile, gpx: '<gpx/>',
    );

    final corps = jsonDecode(capturee.body) as Map<String, dynamic>;
    expect(corps['licenceVersion'], SharedTracesApiClient.licenceVersion);
    expect(SharedTracesApiClient.licenceVersion, '1.0');
  });

  test('list transmet le point de reference, le rayon et les filtres', () async {
    late Uri appelee;
    final api = clientAvec(MockClient((req) async {
      appelee = req.url;
      return http.Response(jsonEncode({'total': 1, 'traces': [{
        'id': 't1', 'name': 'Boucle', 'authorName': 'Marco31', 'vehicle': 'moto',
        'difficulty': 'moyen', 'distanceM': 12000.0, 'elevationGainM': 300.0, 'durationS': 3600,
        'recordedAt': 1000, 'publishedAt': 2000, 'downloadCount': 3,
        'startLat': 43.6, 'startLng': 1.44, 'distanceFromRefM': 11000,
      }]}), 200);
    }));

    final traces = await api.list(lat: 43.6, lng: 1.44, radiusKm: 25, vehicle: TraceVehicle.moto);

    expect(appelee.queryParameters['lat'], '43.6');
    expect(appelee.queryParameters['rayon'], '25');
    expect(appelee.queryParameters['engin'], 'moto');
    expect(traces.single.name, 'Boucle');
    expect(traces.single.downloadCount, 3);
    expect(traces.single.vehicle, TraceVehicle.moto);
  });

  test('detail rend la description et l apercu', () async {
    final api = clientAvec(MockClient((_) async => http.Response(jsonEncode({
      'id': 't1', 'name': 'Boucle', 'authorName': 'Marco31', 'vehicle': 'mixte',
      'difficulty': 'difficile', 'distanceM': 12000.0, 'downloadCount': 0,
      'startLat': 43.6, 'startLng': 1.44, 'publishedAt': 2000,
      'description': 'Deux gues', 'preview': [[43.6, 1.44], [43.61, 1.45]],
    }), 200)));

    final fiche = await api.detail('t1');

    expect(fiche.description, 'Deux gues');
    expect(fiche.preview.length, 2);
    expect(fiche.preview.first.latitude, 43.6);
  });

  test('downloadGpx rend le fichier tel quel', () async {
    final api = clientAvec(MockClient((_) async => http.Response('<gpx>ici</gpx>', 200)));
    expect(await api.downloadGpx('t1'), '<gpx>ici</gpx>');
  });

  test('une erreur du serveur est traduite pour l affichage', () async {
    final api = clientAvec(MockClient((_) async => http.Response('{"error":"quota de publications atteint"}', 429)));

    expect(
      () => api.publish(name: 'B', description: 'D', authorName: 'M',
          vehicle: TraceVehicle.moto, difficulty: TraceDifficulty.moyen, gpx: '<gpx/>'),
      throwsA(isA<SharedTracesException>()
          .having((e) => e.statusCode, 'statusCode', 429)
          .having((e) => e.message, 'message', contains('publications'))),
    );
  });

  test('sans jeton, l appel echoue avant de partir', () async {
    final api = clientAvec(MockClient((_) async => http.Response('', 200)), jeton: null);
    expect(() => api.mine(), throwsA(isA<SharedTracesException>().having((e) => e.statusCode, 'statusCode', 401)));
  });
}
