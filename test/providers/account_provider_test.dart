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

/// Simule la panne d'`AccountStorage.readToken` (voir account_storage_test.dart
/// pour la même classe, côté stockage).
class _StockageEnPanneALaLecture extends FlutterSecureStorage {
  const _StockageEnPanneALaLecture();

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      throw Exception('BadPaddingException (jeu de test)');
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('sans jeton stocke le rider est deconnecte', () async {
    final p = provider(MockClient((_) async => http.Response('{}', 200)));
    await p.restore();
    expect(p.status, AccountStatus.deconnecte);
    expect(p.lastError, isNull);
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

  test('jeton revoque au demarrage, une session est a renouveler, pas deconnecte', () async {
    // Le scénario du C1 de la revue finale : réinitialisation de mot de
    // passe côté serveur (donc révocation de toutes les sessions), le rider
    // ne doit PAS se retrouver mur-à-mur comme un premier lancement — voir
    // accountRedirect et le chapitre 6.5 de la spec.
    await AccountStorage().writeToken('jeton');
    final p = provider(MockClient((_) async => http.Response('{}', 401)));
    await p.restore();
    expect(p.status, AccountStatus.sessionARenouveler);
    expect(p.status, isNot(AccountStatus.deconnecte));
    expect(await AccountStorage().readToken(), isNull);
    expect(p.lastError, AccountError.identifiants);
  });

  test('une panne du stockage securise a la lecture mene aussi a une session a renouveler', () async {
    // flutter_secure_storage peut lever (BadPaddingException) au lieu de
    // rendre null, par exemple quand une sauvegarde restaure une entrée
    // chiffrée sans la clé Keystore correspondante. restore() ne doit ni
    // rester bloqué en "chargement" pour toujours, ni traiter ça comme un
    // tout premier lancement.
    final p = AccountProvider(
      api: AccountApiClient(baseUrl: 'https://exemple.test', client: MockClient((_) async => http.Response('{}', 200))),
      storage: AccountStorage(storage: const _StockageEnPanneALaLecture()),
    );
    await p.restore();
    expect(p.status, AccountStatus.sessionARenouveler);
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

  test('refreshVerification efface une erreur precedente des qu il reussit', () async {
    var enPanne = false;
    final p = provider(MockClient((req) async {
      if (req.url.path.endsWith('/register')) {
        return http.Response(jsonEncode({'token': 'jeton', 'verified': false}), 201);
      }
      if (enPanne) throw Exception('reseau coupe');
      return http.Response(jsonEncode({'email': 'rider@example.test', 'verified': false}), 200);
    }));
    await p.register(email: 'rider@example.test', password: 'dix caracteres');

    enPanne = true;
    await p.refreshVerification();
    expect(p.lastError, AccountError.reseau);

    enPanne = false;
    await p.refreshVerification();
    expect(p.lastError, isNull,
        reason: 'un succes doit effacer une erreur precedente, sinon une simple panne '
            'passagere continuerait d etre affichee indefiniment');
  });

  test('resendVerification memorise la cause d un echec (ex: trop de tentatives)', () async {
    final p = provider(MockClient((req) async {
      if (req.url.path.endsWith('/register')) {
        return http.Response(jsonEncode({'token': 'jeton', 'verified': false}), 201);
      }
      return http.Response('{}', 429);
    }));
    await p.register(email: 'rider@example.test', password: 'dix caracteres');

    final ok = await p.resendVerification();
    expect(ok, isFalse);
    expect(p.lastError, AccountError.tropDeTentatives);
  });

  test('forgotPassword memorise la cause d un echec reseau', () async {
    final p = provider(MockClient((_) async => throw Exception('reseau coupe')));
    final ok = await p.forgotPassword('rider@example.test');
    expect(ok, isFalse);
    expect(p.lastError, AccountError.reseau);
  });

  test('la deconnexion efface le jeton et mene a deconnecte, pas a sessionARenouveler', () async {
    // deconnecte reste réservé aux gestes explicites du rider (logout,
    // deleteAccount) — jamais à une révocation côté serveur, voir le test
    // "jeton révoqué au démarrage" ci-dessus qui prouve l'autre branche.
    final p = provider(MockClient((_) async =>
        http.Response(jsonEncode({'token': 'jeton', 'verified': true}), 201)));
    await p.register(email: 'rider@example.test', password: 'dix caracteres');
    await p.logout();
    expect(p.status, AccountStatus.deconnecte);
    expect(p.status, isNot(AccountStatus.sessionARenouveler));
    expect(await AccountStorage().readToken(), isNull);
  });
}
