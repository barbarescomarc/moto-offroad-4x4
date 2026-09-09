import 'package:flutter_test/flutter_test.dart';
import 'package:moto_offroad/app/account_gate.dart';
import 'package:moto_offroad/providers/account_provider.dart';

void main() {
  String? gate(AccountStatus s, String loc, {bool grace = false}) =>
      accountRedirect(status: s, location: loc, graceActive: grace);

  test('pendant le chargement rien ne bouge', () {
    expect(gate(AccountStatus.chargement, '/'), isNull);
  });

  test('un rider deconnecte est renvoye a l accueil du compte', () {
    expect(gate(AccountStatus.deconnecte, '/'), '/bienvenue');
  });

  test('un rider deconnecte peut atteindre les ecrans de compte', () {
    expect(gate(AccountStatus.deconnecte, '/bienvenue'), isNull);
    expect(gate(AccountStatus.deconnecte, '/inscription'), isNull);
    expect(gate(AccountStatus.deconnecte, '/connexion'), isNull);
  });

  test('un compte non verifie est retenu sur l ecran d attente', () {
    expect(gate(AccountStatus.nonVerifie, '/'), '/verification');
    expect(gate(AccountStatus.nonVerifie, '/verification'), isNull);
    expect(gate(AccountStatus.nonVerifie, '/bienvenue'), '/verification');
  });

  test('un rider connecte ne voit plus les ecrans de compte', () {
    expect(gate(AccountStatus.connecte, '/bienvenue'), '/');
    expect(gate(AccountStatus.connecte, '/verification'), '/');
    expect(gate(AccountStatus.connecte, '/'), isNull);
  });

  test('le delai de grace laisse passer un rider sans compte', () {
    expect(gate(AccountStatus.deconnecte, '/', grace: true), isNull);
    expect(gate(AccountStatus.deconnecte, '/rides', grace: true), isNull);
  });

  test('le delai de grace ne s applique pas a un compte non verifie', () {
    expect(gate(AccountStatus.nonVerifie, '/', grace: true), '/verification');
  });
}
