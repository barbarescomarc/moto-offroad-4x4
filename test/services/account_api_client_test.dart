import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moto_offroad/services/account_api_client.dart';

AccountApiClient clientQuiRepond(int code, Map<String, dynamic> body, {void Function(http.Request)? onRequest}) {
  return AccountApiClient(
    baseUrl: 'https://exemple.test',
    client: MockClient((req) async {
      onRequest?.call(req);
      return http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json'});
    }),
  );
}

void main() {
  test('une inscription reussie rend le jeton et l etat non verifie', () async {
    final api = clientQuiRepond(201, {'token': 'jeton-abc', 'verified': false, 'displayName': 'Marc'});
    final res = await api.register(email: 'rider@example.test', password: 'dix caracteres', displayName: 'Marc');
    expect(res.ok, isTrue);
    expect(res.value!.token, 'jeton-abc');
    expect(res.value!.verified, isFalse);
  });

  test('une adresse deja prise est distinguee', () async {
    final api = clientQuiRepond(409, {'error': 'adresse deja inscrite'});
    final res = await api.register(email: 'rider@example.test', password: 'dix caracteres');
    expect(res.error, AccountError.adresseDejaPrise);
  });

  test('un mot de passe trop court est distingue', () async {
    final api = clientQuiRepond(400, {'error': 'mot de passe de 10 caracteres minimum'});
    final res = await api.register(email: 'rider@example.test', password: 'court');
    expect(res.error, AccountError.motDePasseTropCourt);
  });

  test('une panne reseau est distinguee d un refus', () async {
    final api = AccountApiClient(
      baseUrl: 'https://exemple.test',
      client: MockClient((_) async => throw const SocketExceptionStub()),
    );
    final res = await api.login(email: 'rider@example.test', password: 'dix caracteres');
    expect(res.error, AccountError.reseau);
  });

  test('le jeton est envoye en Bearer sur les routes authentifiees', () async {
    late http.Request vue;
    final api = clientQuiRepond(200, {'email': 'rider@example.test', 'verified': true}, onRequest: (r) => vue = r);
    await api.me(token: 'jeton-abc');
    expect(vue.headers['authorization'], 'Bearer jeton-abc');
  });

  // Re-revue de branche, correctif I7 : me() gouverne l'écran de chargement
  // devant la carte ([_MapGate]) — sans borne, un réseau dégradé (portail
  // captif, TCP qui traîne) y bloquerait indéfiniment le rider, donc son
  // accès au SOS. `meTimeout` est injectable pour ce test précisément : une
  // borne réelle mais très courte prouve le comportement sans faire durer
  // le test (pas de fake_async, absent des dépendances du dépôt).
  test('me() ne pend pas indefiniment sur un serveur qui ne repond jamais', () async {
    final api = AccountApiClient(
      baseUrl: 'https://exemple.test',
      // Le gestionnaire ne complète jamais : simule une connexion qui
      // traîne (TCP/TLS en cours), pas une panne immédiate.
      client: MockClient((_) => Completer<http.Response>().future),
      meTimeout: const Duration(milliseconds: 20),
    );

    final res = await api.me(token: 'jeton-abc');
    expect(res.error, AccountError.reseau);
  });

  test('un 429 devient tropDeTentatives', () async {
    final api = clientQuiRepond(429, {'error': 'trop de tentatives'});
    final res = await api.login(email: 'rider@example.test', password: 'dix caracteres');
    expect(res.error, AccountError.tropDeTentatives);
  });
}

class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
