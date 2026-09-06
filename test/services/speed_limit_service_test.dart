// test/services/speed_limit_service_test.dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:moto_offroad/services/speed_limit_service.dart';

Map<String, dynamic> _overpassResponse(List<Map<String, dynamic>> elements) => {
      'elements': elements,
    };

Map<String, dynamic> _way({
  required String maxspeed,
  required List<List<double>> latLngs, // [lat, lon]
}) =>
    {
      'type': 'way',
      'tags': {'highway': 'primary', 'maxspeed': maxspeed},
      'geometry': latLngs.map((p) => {'lat': p[0], 'lon': p[1]}).toList(),
    };

void main() {
  const position = LatLng(44.0, 6.0);

  group('fetchSpeedLimitKmh', () {
    test('renvoie la limite de la route la plus proche', () async {
      final body = jsonEncode(_overpassResponse([
        _way(maxspeed: '90', latLngs: [
          [44.0, 6.0],
          [44.001, 6.001],
        ]),
      ]));
      final service = SpeedLimitService(client: MockClient((_) async => http.Response(body, 200)));

      final limit = await service.fetchSpeedLimitKmh(position);

      expect(limit, 90);
    });

    test('retient la route la plus proche parmi plusieurs', () async {
      final body = jsonEncode(_overpassResponse([
        _way(maxspeed: '110', latLngs: [
          [44.005, 6.005],
          [44.006, 6.006],
        ]),
        _way(maxspeed: '50', latLngs: [
          [44.0, 6.0],
          [44.0001, 6.0001],
        ]),
      ]));
      final service = SpeedLimitService(client: MockClient((_) async => http.Response(body, 200)));

      final limit = await service.fetchSpeedLimitKmh(position);

      expect(limit, 50);
    });

    test('ignore un tag maxspeed non numérique (ex. FR:urban)', () async {
      final body = jsonEncode(_overpassResponse([
        _way(maxspeed: 'FR:urban', latLngs: [
          [44.0, 6.0],
          [44.001, 6.001],
        ]),
      ]));
      final service = SpeedLimitService(client: MockClient((_) async => http.Response(body, 200)));

      final limit = await service.fetchSpeedLimitKmh(position);

      expect(limit, isNull);
    });

    test('ignore une route trop éloignée de la position', () async {
      final body = jsonEncode(_overpassResponse([
        _way(maxspeed: '90', latLngs: [
          [44.01, 6.01],
          [44.011, 6.011],
        ]),
      ]));
      final service = SpeedLimitService(client: MockClient((_) async => http.Response(body, 200)));

      final limit = await service.fetchSpeedLimitKmh(position);

      expect(limit, isNull);
    });

    test('renvoie null sur une réponse HTTP en erreur', () async {
      final service = SpeedLimitService(client: MockClient((_) async => http.Response('', 500)));

      final limit = await service.fetchSpeedLimitKmh(position);

      expect(limit, isNull);
    });

    test('renvoie null sans lever d\'exception en cas de panne réseau', () async {
      final service = SpeedLimitService(client: MockClient((_) async => throw Exception('offline')));

      final limit = await service.fetchSpeedLimitKmh(position);

      expect(limit, isNull);
    });
  });
}
