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
  // accès au SOS. `timeout` est injectable pour ce test précisément : une
  // borne réelle mais très courte prouve le comportement sans faire durer
  // le test (pas de fake_async, absent des dépendances du dépôt).
  test('me() ne pend pas indefiniment sur un serveur qui ne repond jamais', () async {
    final api = AccountApiClient(
      baseUrl: 'https://exemple.test',
      // Le gestionnaire ne complète jamais : simule une connexion qui
      // traîne (TCP/TLS en cours), pas une panne immédiate.
      client: MockClient((_) => Completer<http.Response>().future),
      timeout: const Duration(milliseconds: 20),
    );

    final res = await api.me(token: 'jeton-abc');
    expect(res.error, AccountError.reseau);
  });

  // Critique 2 de la revue finale : acceptCharte() passe par _voidCall et
  // est desormais la seule sortie du mur de la charte, donc du chemin vers
  // le SOS. La meme borne que me() lui est indispensable, pour exactement le
  // meme portail captif : une connexion qui ne repond jamais, plutot qu une
  // panne franche.
  test('acceptCharte() ne pend pas indefiniment sur un serveur qui ne repond jamais', () async {
    final api = AccountApiClient(
      baseUrl: 'https://exemple.test',
      client: MockClient((_) => Completer<http.Response>().future),
      timeout: const Duration(milliseconds: 20),
    );

    final res = await api.acceptCharte(token: 'jeton-abc', version: '1.0');
    expect(res.error, AccountError.reseau);
  });

  // Suivi 1 de la revue finale : un 400 ne vaut refus de fond que s il vient
  // de NOTRE API (objet JSON portant `error`). Un portail captif, un proxy
  // ou un WAF qui repond 400 est une panne du chemin reseau, pas un refus —
  // et AccountProvider.acceptCharte fait du refus le seul echec qui laisse
  // le mur de la charte en place, donc le SOS ferme.
  test('un 400 qui ne vient pas de notre API n est pas pris pour un refus', () async {
    final api = AccountApiClient(
      baseUrl: 'https://exemple.test',
      client: MockClient((_) async => http.Response(
            '<html><body>Connectez-vous au reseau Wi-Fi</body></html>',
            400,
            headers: {'content-type': 'text/html'},
          )),
    );
    final res = await api.acceptCharte(token: 'jeton-abc', version: '1.0');
    expect(res.error, AccountError.inconnue);
  });

  test('un 400 a corps vide n est pas pris pour un refus non plus', () async {
    final api = AccountApiClient(
      baseUrl: 'https://exemple.test',
      client: MockClient((_) async => http.Response('', 400)),
    );
    final res = await api.acceptCharte(token: 'jeton-abc', version: '1.0');
    expect(res.error, AccountError.inconnue);
  });

  test('un 400 de notre API reste un refus de fond', () async {
    final api = clientQuiRepond(400, {'error': 'version de charte inconnue'});
    final res = await api.acceptCharte(token: 'jeton-abc', version: '1.0');
    expect(res.error, AccountError.adresseInvalide);
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
