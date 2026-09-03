import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moto_offroad/providers/group_provider.dart';
import 'package:moto_offroad/services/location_service.dart';
import 'package:moto_offroad/services/tracker_api_client.dart';

void main() {
  test('maxMembers is 20', () {
    expect(GroupProvider.maxMembers, 20);
  });

  test('createSession succeeds and exposes the real join code', () async {
    final client = MockClient((req) async {
      if (req.url.path == '/api/sessions') {
        return http.Response(
          '{"sessionId":"s1","ownerKey":"ok","deviceKey":"dk","memberId":"m1","joinCode":"AB12CD"}',
          201,
        );
      }
      return http.Response('', 404);
    });
    final g = GroupProvider(trackerClient: TrackerApiClient(client: client, baseUrl: 'https://example.test'));

    final ok = await g.createSession('Marc');

    expect(ok, isTrue);
    expect(g.groupActive, isTrue);
    expect(g.sessionId, 'AB12CD');
    expect(g.inviteLink, 'https://motooffroad.duckdns.org/g/AB12CD');
    expect(g.members.length, 1);
    expect(g.members.first.name, 'Marc');
  });

  test('createSession failure leaves the group inactive', () async {
    final client = MockClient((_) async => throw Exception('offline'));
    final g = GroupProvider(trackerClient: TrackerApiClient(client: client, baseUrl: 'https://example.test'));

    final ok = await g.createSession('Marc');

    expect(ok, isFalse);
    expect(g.groupActive, isFalse);
  });

  test('joinSession succeeds and adds self as a member', () async {
    final client = MockClient((req) async {
      if (req.url.path.startsWith('/api/sessions/join/')) {
        return http.Response('{"sessionId":"s1","deviceKey":"dk","memberId":"m2","color":"#1565C0"}', 200);
      }
      return http.Response('', 404);
    });
    final g = GroupProvider(trackerClient: TrackerApiClient(client: client, baseUrl: 'https://example.test'));

    final ok = await g.joinSession('AB12CD', 'Claire');

    expect(ok, isTrue);
    expect(g.groupActive, isTrue);
    expect(g.members.single.name, 'Claire');
  });

  test('joinSession failure (bad code) leaves the group inactive', () async {
    final client = MockClient((_) async => http.Response('', 404));
    final g = GroupProvider(trackerClient: TrackerApiClient(client: client, baseUrl: 'https://example.test'));

    final ok = await g.joinSession('ZZZZZZ', 'Claire');

    expect(ok, isFalse);
    expect(g.groupActive, isFalse);
  });

  test('the creator leaving ends the session for everyone', () async {
    var endCalled = false;
    var leaveCalled = false;
    final client = MockClient((req) async {
      if (req.url.path == '/api/sessions') {
        return http.Response(
          '{"sessionId":"s1","ownerKey":"ok","deviceKey":"dk","memberId":"m1","joinCode":"AB12CD"}',
          201,
        );
      }
      if (req.url.path.endsWith('/end')) { endCalled = true; return http.Response('{}', 200); }
      if (req.method == 'DELETE') { leaveCalled = true; return http.Response('{}', 200); }
      return http.Response('', 404);
    });
    final g = GroupProvider(trackerClient: TrackerApiClient(client: client, baseUrl: 'https://example.test'));
    await g.createSession('Marc');

    g.leaveGroup();
    await Future.delayed(Duration.zero);

    expect(endCalled, isTrue);
    expect(leaveCalled, isFalse);
  });

  test('a joiner (not the creator) leaving only removes themselves', () async {
    var endCalled = false;
    var leaveCalled = false;
    final client = MockClient((req) async {
      if (req.url.path.startsWith('/api/sessions/join/')) {
        return http.Response('{"sessionId":"s1","deviceKey":"dk","memberId":"m2","color":"#1565C0"}', 200);
      }
      if (req.url.path.endsWith('/end')) { endCalled = true; return http.Response('{}', 200); }
      if (req.method == 'DELETE') { leaveCalled = true; return http.Response('{}', 200); }
      return http.Response('', 404);
    });
    final g = GroupProvider(trackerClient: TrackerApiClient(client: client, baseUrl: 'https://example.test'));
    await g.joinSession('AB12CD', 'Claire');

    g.leaveGroup();
    await Future.delayed(Duration.zero);

    expect(leaveCalled, isTrue);
    expect(endCalled, isFalse);
  });

  test('creator hub calls use the real session id, not the public join code', () async {
    String? capturedPath;
    final client = MockClient((req) async {
      if (req.url.path == '/api/sessions') {
        return http.Response(
          '{"sessionId":"s1","ownerKey":"ok","deviceKey":"dk","memberId":"m1","joinCode":"AB12CD"}',
          201,
        );
      }
      if (req.url.path.endsWith('/end')) {
        capturedPath = req.url.path;
        return http.Response('{}', 200);
      }
      return http.Response('', 404);
    });
    final g = GroupProvider(trackerClient: TrackerApiClient(client: client, baseUrl: 'https://example.test'));
    await g.createSession('Marc');

    expect(g.sessionId, 'AB12CD'); // affiché : le join code

    g.leaveGroup();
    await Future.delayed(Duration.zero);

    expect(capturedPath, '/api/sessions/s1/end'); // appel reseau : l'id interne reel, jamais le join code
  });

  test('toggleMySharing updates the real self member, not a stale sentinel', () async {
    final client = MockClient((req) async {
      if (req.url.path == '/api/sessions') {
        return http.Response(
          '{"sessionId":"s1","ownerKey":"ok","deviceKey":"dk","memberId":"m1","joinCode":"AB12CD"}',
          201,
        );
      }
      return http.Response('', 404);
    });
    final g = GroupProvider(trackerClient: TrackerApiClient(client: client, baseUrl: 'https://example.test'));
    await g.createSession('Marc');

    expect(g.members.single.isSharing, isTrue);
    g.toggleMySharing();
    expect(g.members.single.isSharing, isFalse);
  });

  test('startLiveSharing polls peers and merges them into members', () async {
    var peersCallCount = 0;
    final client = MockClient((req) async {
      if (req.url.path == '/api/sessions') {
        return http.Response(
          '{"sessionId":"s1","ownerKey":"ok","deviceKey":"dk","memberId":"m1","joinCode":"AB12CD"}',
          201,
        );
      }
      if (req.url.path.contains('/peers')) {
        peersCallCount++;
        return http.Response(
          '{"peers":[{"memberId":"m2","name":"Claire","color":"#1565C0","lat":45.2,"lng":5.8,"speedKmh":40,"lastSeen":${DateTime.now().millisecondsSinceEpoch}}],"rally":null}',
          200,
        );
      }
      if (req.url.path.contains('/positions')) {
        return http.Response('{"accepted":1}', 200);
      }
      return http.Response('', 404);
    });
    final g = GroupProvider(trackerClient: TrackerApiClient(client: client, baseUrl: 'https://example.test'));
    await g.createSession('Marc');

    final controller = StreamController<GpsSnapshot>();
    g.startLiveSharing(positions: controller.stream, pollInterval: const Duration(milliseconds: 20));
    await Future.delayed(const Duration(milliseconds: 60));

    expect(peersCallCount, greaterThan(0));
    expect(g.members.any((m) => m.id == 'm2' && m.name == 'Claire'), isTrue);

    g.leaveGroup();
    await controller.close();
  });

  test('leaveGroup stops the peer poll timer', () async {
    var peersCallCount = 0;
    final client = MockClient((req) async {
      if (req.url.path == '/api/sessions') {
        return http.Response(
          '{"sessionId":"s1","ownerKey":"ok","deviceKey":"dk","memberId":"m1","joinCode":"AB12CD"}',
          201,
        );
      }
      if (req.url.path.contains('/peers')) {
        peersCallCount++;
        return http.Response('{"peers":[],"rally":null}', 200);
      }
      return http.Response('', 404);
    });
    final g = GroupProvider(trackerClient: TrackerApiClient(client: client, baseUrl: 'https://example.test'));
    await g.createSession('Marc');
    final controller = StreamController<GpsSnapshot>();
    g.startLiveSharing(positions: controller.stream, pollInterval: const Duration(milliseconds: 20));
    await Future.delayed(const Duration(milliseconds: 30));

    g.leaveGroup();
    final countAtLeave = peersCallCount;
    await Future.delayed(const Duration(milliseconds: 60));

    expect(peersCallCount, countAtLeave);
    await controller.close();
  });

  test('a peer poll still in flight when leaveGroup is called does not repopulate members', () async {
    final completer = Completer<http.Response>();
    var peersRequested = false;
    final client = MockClient((req) async {
      if (req.url.path == '/api/sessions') {
        return http.Response(
          '{"sessionId":"s1","ownerKey":"ok","deviceKey":"dk","memberId":"m1","joinCode":"AB12CD"}',
          201,
        );
      }
      if (req.url.path.contains('/peers')) {
        peersRequested = true;
        return completer.future;
      }
      return http.Response('', 404);
    });
    final g = GroupProvider(trackerClient: TrackerApiClient(client: client, baseUrl: 'https://example.test'));
    await g.createSession('Marc');

    final controller = StreamController<GpsSnapshot>();
    g.startLiveSharing(positions: controller.stream, pollInterval: const Duration(milliseconds: 20));
    await Future.delayed(const Duration(milliseconds: 30)); // le premier tick a demarre et attend la reponse

    expect(peersRequested, isTrue);

    g.leaveGroup(); // le groupe est quitte pendant que fetchPeers est encore en vol

    completer.complete(http.Response(
      '{"peers":[{"memberId":"m2","name":"Claire","color":"#1565C0","lat":45.2,"lng":5.8,"speedKmh":40,"lastSeen":${DateTime.now().millisecondsSinceEpoch}}],"rally":null}',
      200,
    ));
    await Future.delayed(const Duration(milliseconds: 30));

    expect(g.groupActive, isFalse);
    expect(g.members, isEmpty); // ne doit pas etre repeuplee par la reponse tardive

    await controller.close();
  });
}
