// test/services/speed_camera_service_test.dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:moto_offroad/services/speed_camera_service.dart';

Map<String, dynamic> _node(double lat, double lon) => {
      'type': 'node',
      'lat': lat,
      'lon': lon,
      'tags': {'highway': 'speed_camera'},
    };

void main() {
  const position = LatLng(44.0, 6.0);

  group('fetchNearbyCameras', () {
    test('parse les nœuds renvoyés par Overpass', () async {
      final body = jsonEncode({
        'elements': [_node(44.01, 6.0), _node(44.02, 6.01)],
      });
      final service = SpeedCameraService(client: MockClient((_) async => http.Response(body, 200)));

      final cameras = await service.fetchNearbyCameras(position);

      expect(cameras, [const LatLng(44.01, 6.0), const LatLng(44.02, 6.01)]);
    });

    test('renvoie une liste vide sur une réponse HTTP en erreur', () async {
      final service = SpeedCameraService(client: MockClient((_) async => http.Response('', 500)));

      final cameras = await service.fetchNearbyCameras(position);

      expect(cameras, isEmpty);
    });

    test('renvoie une liste vide sans lever d\'exception en cas de panne réseau', () async {
      final service = SpeedCameraService(client: MockClient((_) async => throw Exception('offline')));

      final cameras = await service.fetchNearbyCameras(position);

      expect(cameras, isEmpty);
    });
  });
}
