import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:moto_offroad/services/account_storage.dart';

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
}
