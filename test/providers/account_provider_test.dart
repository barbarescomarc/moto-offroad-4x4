import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moto_offroad/providers/account_provider.dart';
import 'package:moto_offroad/services/account_api_client.dart';
import 'package:moto_offroad/services/account_storage.dart';

AccountProvider provider(http.Client client) => AccountProvider(
      api: AccountApiClient(baseUrl: 'https://exemple.test', client: client),
      storage: AccountStorage(),
    );

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('sans jeton stocke le rider est deconnecte', () async {
    final p = provider(MockClient((_) async => http.Response('{}', 200)));
    await p.restore();
    expect(p.status, AccountStatus.deconnecte);
  });

  test('serveur injoignable au demarrage, le rider avec jeton reste connecte', () async {
    // Jeton déjà présent, comme au retour d'une sortie précédente.
    await AccountStorage().writeToken('jeton');
    final p = provider(MockClient((_) async => throw Exception('reseau coupe')));
    await p.restore();
    expect(p.status, AccountStatus.connecte);
    expect(await AccountStorage().readToken(), 'jeton',
        reason: 'garder le statut sans garder le jeton ne servirait a rien');
  });

  test('jeton revoque au demarrage, le rider est deconnecte', () async {
    await AccountStorage().writeToken('jeton');
    final p = provider(MockClient((_) async => http.Response('{}', 401)));
    await p.restore();
    expect(p.status, AccountStatus.deconnecte);
    expect(await AccountStorage().readToken(), isNull);
  });

  test('une inscription laisse le rider non verifie', () async {
    final p = provider(MockClient((_) async =>
        http.Response(jsonEncode({'token': 'jeton', 'verified': false}), 201)));
    final ok = await p.register(email: 'rider@example.test', password: 'dix caracteres');
    expect(ok, isTrue);
    expect(p.status, AccountStatus.nonVerifie);
    expect(await AccountStorage().readToken(), 'jeton');
  });

  test('la verification confirmee fait passer a connecte', () async {
    final p = provider(MockClient((req) async {
      if (req.url.path.endsWith('/register')) {
        return http.Response(jsonEncode({'token': 'jeton', 'verified': false}), 201);
      }
      return http.Response(jsonEncode({'email': 'rider@example.test', 'verified': true}), 200);
    }));
    await p.register(email: 'rider@example.test', password: 'dix caracteres');
    expect(await p.refreshVerification(), isTrue);
    expect(p.status, AccountStatus.connecte);
  });

  test('une panne reseau ne deconnecte jamais un rider connecte', () async {
    var enPanne = false;
    final p = provider(MockClient((req) async {
      if (enPanne) throw Exception('reseau coupe');
      if (req.url.path.endsWith('/register')) {
        return http.Response(jsonEncode({'token': 'jeton', 'verified': true}), 201);
      }
      return http.Response(jsonEncode({'email': 'rider@example.test', 'verified': true}), 200);
    }));
    await p.register(email: 'rider@example.test', password: 'dix caracteres');
    expect(p.status, AccountStatus.connecte);

    enPanne = true;
    await p.refreshVerification();
    expect(p.status, AccountStatus.connecte, reason: 'le reseau absent ne verrouille pas l application');
  });

  test('la deconnexion efface le jeton', () async {
    final p = provider(MockClient((_) async =>
        http.Response(jsonEncode({'token': 'jeton', 'verified': true}), 201)));
    await p.register(email: 'rider@example.test', password: 'dix caracteres');
    await p.logout();
    expect(p.status, AccountStatus.deconnecte);
    expect(await AccountStorage().readToken(), isNull);
  });
}
