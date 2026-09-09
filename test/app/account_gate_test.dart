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

  // Une session a renouveler (jeton revoque par le serveur, ex. apres une
  // reinitialisation de mot de passe) ne doit jamais fermer l'acces a
  // l'application : ni la carte, ni le SOS, ni la detection de chute. Voir
  // le chapitre 6.5 de la spec et AccountProvider.restore().
  test('une session a renouveler ne redirige nulle part', () {
    expect(gate(AccountStatus.sessionARenouveler, '/'), isNull);
    expect(gate(AccountStatus.sessionARenouveler, '/sos'), isNull);
    expect(gate(AccountStatus.sessionARenouveler, '/solo'), isNull);
    expect(gate(AccountStatus.sessionARenouveler, '/fall-countdown'), isNull);
  });

  test('une session a renouveler peut malgre tout atteindre l ecran de connexion', () {
    expect(gate(AccountStatus.sessionARenouveler, '/connexion'), isNull);
  });

  // accountBannerKind : quel bandeau MainShell doit afficher, s'il y en a
  // un (voir AccountBanner et le chapitre 7.2 de la spec pour le delai de
  // grace, le chapitre 6.5 pour la session a renouveler).
  test('sessionARenouveler prime, peu importe le delai de grace', () {
    expect(
      accountBannerKind(status: AccountStatus.sessionARenouveler, graceActive: true),
      AccountBannerKind.sessionExpiree,
    );
    expect(
      accountBannerKind(status: AccountStatus.sessionARenouveler, graceActive: false),
      AccountBannerKind.sessionExpiree,
    );
  });

  test('le delai de grace actif affiche son bandeau hors session a renouveler', () {
    expect(
      accountBannerKind(status: AccountStatus.deconnecte, graceActive: true),
      AccountBannerKind.delaiDeGrace,
    );
  });

  test('aucun bandeau sans session a renouveler ni delai de grace actif', () {
    for (final statut in AccountStatus.values) {
      if (statut == AccountStatus.sessionARenouveler) continue;
      expect(accountBannerKind(status: statut, graceActive: false), AccountBannerKind.aucun);
    }
  });
}
