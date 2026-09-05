import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:moto_offroad/services/location_service.dart';
import 'package:moto_offroad/services/tracker_api_client.dart';

void main() {
  group('createSoloSession', () {
    test('parses a successful response', () async {
      final client = MockClient((req) async {
        expect(req.url.path, '/api/sessions');
        return http.Response(
          '{"sessionId":"s1","ownerKey":"ok","deviceKey":"dk","memberId":"m1","watchToken":"tok"}',
          201,
        );
      });
      final api = TrackerApiClient(client: client, baseUrl: 'https://example.test');
      final result = await api.createSoloSession(
        name: 'Marc', immobileAfterSec: 1800,
        pilotEmail: 'marc@example.test', contactEmails: ['claire@example.test'],
      );
      expect(result, isNotNull);
      expect(result!.watchToken, 'tok');
      expect(result.sessionId, 's1');
    });

    test('returns null on network failure', () async {
      final client = MockClient((_) async => throw Exception('offline'));
      final api = TrackerApiClient(client: client, baseUrl: 'https://example.test');
      final result = await api.createSoloSession(
        name: 'Marc', immobileAfterSec: 1800,
        pilotEmail: 'marc@example.test', contactEmails: ['claire@example.test'],
      );
      expect(result, isNull);
    });

    test('returns null on a non-2xx response', () async {
      final client = MockClient((_) async => http.Response('{}', 400));
      final api = TrackerApiClient(client: client, baseUrl: 'https://example.test');
      final result = await api.createSoloSession(
        name: 'Marc', immobileAfterSec: 1800,
        pilotEmail: 'marc@example.test', contactEmails: ['claire@example.test'],
      );
      expect(result, isNull);
    });

    test('createSoloSession sends pilotEmail, contactEmails, and deadmanAfterSec', () async {
      Map<String, dynamic>? capturedBody;
      final client = MockClient((req) async {
        capturedBody = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(
          '{"sessionId":"s1","ownerKey":"ok","deviceKey":"dk","memberId":"m1","watchToken":"tok"}',
          201,
        );
      });
      final api = TrackerApiClient(client: client, baseUrl: 'https://example.test');
      await api.createSoloSession(
        name: 'Marc', immobileAfterSec: 1800, deadmanAfterSec: 600,
        pilotEmail: 'marc@example.test', contactEmails: ['claire@example.test', 'jean@example.test'],
      );
      expect(capturedBody!['pilotEmail'], 'marc@example.test');
      expect(capturedBody!['contactEmails'], ['claire@example.test', 'jean@example.test']);
      expect(capturedBody!['deadmanAfterSec'], 600);
    });
  });

  group('sendPositions', () {
    test('returns true when the server accepts the batch', () async {
      final client = MockClient((_) async => http.Response('{"accepted":1}', 200));
      final api = TrackerApiClient(client: client, baseUrl: 'https://example.test');
      final ok = await api.sendPositions(
        sessionId: 's1', deviceKey: 'dk', memberId: 'm1',
        points: [GpsSnapshot(
          position: const LatLng(45, 5), accuracyMeters: 5, altitudeMeters: 100,
          speedKmh: 30, headingDeg: 90, timestamp: DateTime.now(),
        )],
      );
      expect(ok, isTrue);
    });

    test('returns false without throwing when offline', () async {
      final client = MockClient((_) async => throw Exception('offline'));
      final api = TrackerApiClient(client: client, baseUrl: 'https://example.test');
      final ok = await api.sendPositions(
        sessionId: 's1', deviceKey: 'dk', memberId: 'm1',
        points: [GpsSnapshot(
          position: const LatLng(45, 5), accuracyMeters: 5, altitudeMeters: 100,
          speedKmh: 30, headingDeg: 90, timestamp: DateTime.now(),
        )],
      );
      expect(ok, isFalse);
    });
  });

  group('fetchPeers', () {
    test('parses peers and excludes nothing itself (server already excludes caller)', () async {
      final client = MockClient((_) async => http.Response(
        '{"peers":[{"memberId":"m2","name":"Claire","color":"#1565C0","lat":45.2,"lng":5.8,"speedKmh":40,"lastSeen":1000}],"rally":null}',
        200,
      ));
      final api = TrackerApiClient(client: client, baseUrl: 'https://example.test');
      final result = await api.fetchPeers(sessionId: 's1', deviceKey: 'dk', memberId: 'm1');
      expect(result.peers.length, 1);
      expect(result.peers.first.name, 'Claire');
      expect(result.peers.first.position, const LatLng(45.2, 5.8));
      expect(result.rally, isNull);
      expect(result.ok, isTrue);
    });

    test('parses the rally point when the server has one', () async {
      final client = MockClient((_) async => http.Response(
        '{"peers":[],"rally":{"lat":45.5,"lng":6.1}}',
        200,
      ));
      final api = TrackerApiClient(client: client, baseUrl: 'https://example.test');
      final result = await api.fetchPeers(sessionId: 's1', deviceKey: 'dk', memberId: 'm1');
      expect(result.rally, const LatLng(45.5, 6.1));
    });

    test('returns an empty result on failure', () async {
      final client = MockClient((_) async => http.Response('', 500));
      final api = TrackerApiClient(client: client, baseUrl: 'https://example.test');
      final result = await api.fetchPeers(sessionId: 's1', deviceKey: 'dk', memberId: 'm1');
      expect(result.peers, isEmpty);
      expect(result.rally, isNull);
      expect(result.ok, isFalse);
    });
  });

  group('sendAlert', () {
    test('returns true on success', () async {
      final client = MockClient((req) async {
        expect(req.url.path, '/api/sessions/s1/alert');
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body['kind'], 'fall');
        return http.Response('{}', 200);
      });
      final api = TrackerApiClient(client: client, baseUrl: 'https://example.test');
      final ok = await api.sendAlert(sessionId: 's1', deviceKey: 'dk', memberId: 'm1', kind: 'fall');
      expect(ok, isTrue);
    });

    test('returns false on network failure without throwing', () async {
      final client = MockClient((_) async => throw Exception('offline'));
      final api = TrackerApiClient(client: client, baseUrl: 'https://example.test');
      final ok = await api.sendAlert(sessionId: 's1', deviceKey: 'dk', memberId: 'm1', kind: 'sos');
      expect(ok, isFalse);
    });
  });

  group('subscribeNewsletter', () {
    test('returns true on success', () async {
      final client = MockClient((req) async {
        expect(req.url.path, '/api/newsletter/subscribe');
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body['email'], 'marc@example.test');
        expect(body['source'], 'pilot');
        return http.Response('{}', 200);
      });
      final api = TrackerApiClient(client: client, baseUrl: 'https://example.test');
      final ok = await api.subscribeNewsletter(email: 'marc@example.test', source: 'pilot');
      expect(ok, isTrue);
    });

    test('returns false on network failure without throwing', () async {
      final client = MockClient((_) async => throw Exception('offline'));
      final api = TrackerApiClient(client: client, baseUrl: 'https://example.test');
      final ok = await api.subscribeNewsletter(email: 'marc@example.test', source: 'pilot');
      expect(ok, isFalse);
    });
  });

  group('unsubscribeNewsletter', () {
    test('returns true on success', () async {
      final client = MockClient((req) async {
        expect(req.url.path, '/api/newsletter/unsubscribe');
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body['email'], 'marc@example.test');
        return http.Response('{}', 200);
      });
      final api = TrackerApiClient(client: client, baseUrl: 'https://example.test');
      final ok = await api.unsubscribeNewsletter(email: 'marc@example.test');
      expect(ok, isTrue);
    });

    test('returns false on network failure without throwing', () async {
      final client = MockClient((_) async => throw Exception('offline'));
      final api = TrackerApiClient(client: client, baseUrl: 'https://example.test');
      final ok = await api.unsubscribeNewsletter(email: 'marc@example.test');
      expect(ok, isFalse);
    });
  });
}
