import 'dart:convert';
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
    await s.addContact(name: 'Claire', phone: '+33600000000', relation: 'Sœur', email: 'claire@example.test');

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
    await s.addContact(name: 'Claire', phone: '+33600000000', relation: 'Sœur', email: 'claire@example.test');
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
      await s.addContact(name: 'C$i', phone: '060000000$i', relation: 'Ami', email: 'c$i@example.test');
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
    await s.addContact(name: 'Claire', phone: '0600000000', relation: 'Sœur', email: 'claire@example.test');

    final ok = await s.activate([s.contacts.first.id], pilotEmail: 'marc@example.test');

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
    await s.addContact(name: 'Claire', phone: '0600000000', relation: 'Sœur', email: 'claire@example.test');

    final ok = await s.activate([s.contacts.first.id], pilotEmail: 'marc@example.test');

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
    await s.addContact(name: 'Claire', phone: '0600000000', relation: 'Sœur', email: 'claire@example.test');
    await s.activate([s.contacts.first.id], pilotEmail: 'marc@example.test');

    s.deactivate();
    await Future.delayed(Duration.zero); // laisse le endSession() fire-and-forget se lancer

    expect(endCalled, isTrue);
    expect(s.sessionId, isNull);
    expect(s.trackingUrl, isNull);
  });

  test('a contact stores and reloads its email', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SoloProvider();
    await s.loadContacts();
    await s.addContact(name: 'Claire', phone: '+33600000000', relation: 'Sœur', email: 'claire@example.test');

    final reloaded = SoloProvider();
    await reloaded.loadContacts();
    expect(reloaded.contacts.first.email, 'claire@example.test');
  });

  test('updateContact persists edited fields and reloads correctly', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SoloProvider();
    await s.loadContacts();
    await s.addContact(name: 'Claire', phone: '+33600000000', relation: 'Sœur', email: '');
    final id = s.contacts.first.id;

    await s.updateContact(
      id: id, name: 'Claire Martin', phone: '+33611111111',
      email: 'claire.martin@example.test', relation: 'Conjointe',
    );

    final reloaded = SoloProvider();
    await reloaded.loadContacts();
    expect(reloaded.contacts.length, 1);
    expect(reloaded.contacts.first.id, id);
    expect(reloaded.contacts.first.name, 'Claire Martin');
    expect(reloaded.contacts.first.phone, '+33611111111');
    expect(reloaded.contacts.first.email, 'claire.martin@example.test');
    expect(reloaded.contacts.first.relation, 'Conjointe');
  });

  test('updateContact with an unknown id is a no-op', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SoloProvider();
    await s.loadContacts();
    await s.addContact(name: 'Claire', phone: '+33600000000', relation: 'Sœur', email: 'claire@example.test');
    final before = s.contacts.map((c) => c.toJson()).toList();

    await s.updateContact(
      id: 'not-a-real-id', name: 'Ghost', phone: '0000000000',
      email: 'ghost@example.test', relation: 'Personne',
    );

    expect(s.contacts.map((c) => c.toJson()).toList(), before);
  });

  test('updateContact does not reorder the contact list', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SoloProvider();
    await s.loadContacts();
    await s.addContact(name: 'Claire', phone: '0600000000', relation: 'Sœur', email: 'claire@example.test');
    await s.addContact(name: 'Jean', phone: '0600000001', relation: 'Ami', email: 'jean@example.test');
    await s.addContact(name: 'Léa', phone: '0600000002', relation: 'Amie', email: 'lea@example.test');
    final jeanId = s.contacts[1].id;

    await s.updateContact(
      id: jeanId, name: 'Jean Dupont', phone: '0600000099',
      email: 'jean.dupont@example.test', relation: 'Frère',
    );

    expect(s.contacts[0].name, 'Claire');
    expect(s.contacts[1].id, jeanId);
    expect(s.contacts[1].name, 'Jean Dupont');
    expect(s.contacts[2].name, 'Léa');
  });

  test('deadmanThresholdMin defaults to 15 and can be changed', () {
    final s = SoloProvider();
    expect(s.deadmanThresholdMin, 15);
    s.setDeadmanThreshold(20);
    expect(s.deadmanThresholdMin, 20);
  });

  test('activate() sends the pilot email and every selected contact email to the hub', () async {
    SharedPreferences.setMockInitialValues({});
    Map<String, dynamic>? capturedBody;
    final client = MockClient((req) async {
      capturedBody = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(
        '{"sessionId":"s1","ownerKey":"ok","deviceKey":"dk","memberId":"m1","watchToken":"tok"}',
        201,
      );
    });
    final s = SoloProvider(trackerClient: TrackerApiClient(client: client, baseUrl: 'https://example.test'));
    await s.loadContacts();
    await s.addContact(name: 'Claire', phone: '0600000000', email: 'claire@example.test', relation: 'Sœur');
    await s.addContact(name: 'Jean', phone: '0600000001', email: 'jean@example.test', relation: 'Ami');

    final ok = await s.activate([s.contacts.first.id], pilotEmail: 'marc@example.test');

    expect(ok, isTrue);
    expect(capturedBody!['pilotEmail'], 'marc@example.test');
    expect(capturedBody!['contactEmails'], ['claire@example.test']); // seul le contact sélectionné, pas Jean
    expect(capturedBody!['deadmanAfterSec'], 15 * 60); // valeur par défaut de deadmanThresholdMin
  });

  test('activate() fails without contacting the hub if the pilot email is empty', () async {
    SharedPreferences.setMockInitialValues({});
    var hubCalled = false;
    final client = MockClient((req) async { hubCalled = true; return http.Response('', 500); });
    final s = SoloProvider(trackerClient: TrackerApiClient(client: client, baseUrl: 'https://example.test'));
    await s.loadContacts();
    await s.addContact(name: 'Claire', phone: '0600000000', email: 'claire@example.test', relation: 'Sœur');

    final ok = await s.activate([s.contacts.first.id], pilotEmail: '');

    expect(ok, isFalse);
    expect(hubCalled, isFalse);
    expect(s.soloActive, isFalse);
  });
}
