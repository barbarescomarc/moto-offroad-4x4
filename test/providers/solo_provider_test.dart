import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moto_offroad/providers/solo_provider.dart';

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
}
