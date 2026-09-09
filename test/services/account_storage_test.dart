import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:moto_offroad/services/account_storage.dart';

/// Simule un stockage sécurisé en panne (ex : `BadPaddingException` sur
/// Android après restauration d'une sauvegarde sans la clé Keystore
/// correspondante) : chaque opération lève, comme le ferait le plugin réel
/// dans ce scénario, plutôt que de rendre `null` silencieusement.
class _StockageEnPanne extends FlutterSecureStorage {
  const _StockageEnPanne();

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

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      throw Exception('ecriture en echec (jeu de test)');

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      throw Exception('effacement en echec (jeu de test)');
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('un jeton ecrit est relu', () async {
    final storage = AccountStorage();
    await storage.writeToken('jeton-abc');
    expect(await storage.readToken(), 'jeton-abc');
  });

  test('sans jeton la lecture rend null', () async {
    expect(await AccountStorage().readToken(), isNull);
  });

  test('l effacement retire le jeton', () async {
    final storage = AccountStorage();
    await storage.writeToken('jeton-abc');
    await storage.clear();
    expect(await storage.readToken(), isNull);
  });

  test('une panne du stockage a la lecture leve AccountStorageFailure, pas null', () async {
    // Distinction cruciale pour AccountProvider.restore() : une panne ne
    // doit jamais etre confondue avec une absence de jeton legitime.
    final storage = AccountStorage(storage: const _StockageEnPanne());
    await expectLater(storage.readToken(), throwsA(isA<AccountStorageFailure>()));
  });

  test('une panne du stockage a l ecriture ne leve rien', () async {
    // Ecriture au mieux : un jeton deja valide en memoire ne doit pas faire
    // planter register()/login() si seule sa persistance echoue.
    final storage = AccountStorage(storage: const _StockageEnPanne());
    await storage.writeToken('jeton-abc');
  });

  test('une panne du stockage a l effacement ne leve rien', () async {
    final storage = AccountStorage(storage: const _StockageEnPanne());
    await storage.clear();
  });
}
