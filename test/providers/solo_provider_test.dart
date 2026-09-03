import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moto_offroad/providers/solo_provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moto_offroad/services/tracker_api_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('les contacts survivent à un rechargement', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SoloProvider();
    await s.loadContacts();
    await s.addContact(name: 'Claire', phone: '+33600000000', relation: 'Sœur');

    final reloaded = SoloProvider();
    await reloaded.loadContacts();
    expect(reloaded.contacts.length, 1);
    expect(reloaded.contacts.first.name, 'Claire');
    expect(reloaded.contacts.first.phone, '+33600000000');
  });

  test('la suppression est persistée elle aussi', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SoloProvider();
    await s.loadContacts();
    await s.addContact(name: 'Claire', phone: '+33600000000', relation: 'Sœur');
    await s.removeContact(s.contacts.first.id);

    final reloaded = SoloProvider();
    await reloaded.loadContacts();
    expect(reloaded.contacts, isEmpty);
  });

  test('la limite de trois contacts est conservée', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SoloProvider();
    await s.loadContacts();
    for (int i = 0; i < 5; i++) {
      await s.addContact(name: 'C$i', phone: '060000000$i', relation: 'Ami');
    }
    expect(s.contacts.length, 3);
  });

  test('activate() creates a real hub session and exposes the real tracking URL', () async {
    SharedPreferences.setMockInitialValues({});
    final client = MockClient((req) async {
      if (req.url.path == '/api/sessions') {
        return http.Response(
          '{"sessionId":"s1","ownerKey":"ok","deviceKey":"dk","memberId":"m1","watchToken":"tok123"}',
          201,
        );
      }
      return http.Response('', 404);
    });
    final s = SoloProvider(trackerClient: TrackerApiClient(client: client, baseUrl: 'https://example.test'));
    await s.loadContacts();
    await s.addContact(name: 'Claire', phone: '0600000000', relation: 'Sœur');

    final ok = await s.activate([s.contacts.first.id]);

    expect(ok, isTrue);
    expect(s.soloActive, isTrue);
    expect(s.trackingUrl, 'https://motooffroad.duckdns.org/s/tok123');
    expect(s.sessionId, 's1');
    expect(s.deviceKey, 'dk');
    expect(s.memberId, 'm1');
  });

  test('activate() fails cleanly (no fake link) when the hub is unreachable', () async {
    SharedPreferences.setMockInitialValues({});
    final client = MockClient((_) async => throw Exception('offline'));
    final s = SoloProvider(trackerClient: TrackerApiClient(client: client, baseUrl: 'https://example.test'));
    await s.loadContacts();
    await s.addContact(name: 'Claire', phone: '0600000000', relation: 'Sœur');

    final ok = await s.activate([s.contacts.first.id]);

    expect(ok, isFalse);
    expect(s.soloActive, isFalse);
    expect(s.trackingUrl, isNull);
  });

  test('deactivate() ends the hub session and clears local session identifiers', () async {
    SharedPreferences.setMockInitialValues({});
    var endCalled = false;
    final client = MockClient((req) async {
      if (req.url.path == '/api/sessions') {
        return http.Response(
          '{"sessionId":"s1","ownerKey":"ok","deviceKey":"dk","memberId":"m1","watchToken":"tok"}',
          201,
        );
      }
      if (req.url.path.endsWith('/end')) {
        endCalled = true;
        return http.Response('{}', 200);
      }
      return http.Response('', 404);
    });
    final s = SoloProvider(trackerClient: TrackerApiClient(client: client, baseUrl: 'https://example.test'));
    await s.loadContacts();
    await s.addContact(name: 'Claire', phone: '0600000000', relation: 'Sœur');
    await s.activate([s.contacts.first.id]);

    s.deactivate();
    await Future.delayed(Duration.zero); // laisse le endSession() fire-and-forget se lancer

    expect(endCalled, isTrue);
    expect(s.sessionId, isNull);
    expect(s.trackingUrl, isNull);
  });
}
