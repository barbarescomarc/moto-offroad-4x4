import 'package:flutter_test/flutter_test.dart';
import 'package:moto_offroad/app/account_gate.dart';
import 'package:moto_offroad/providers/account_provider.dart';
import 'package:moto_offroad/services/legal_documents.dart';

void main() {
  // charteVersion accepté par défaut : tous les tests de ce fichier, écrits
  // avant la Tâche 23B, portent sur d'autres règles que la charte — ce
  // deuxième mur ne doit pas les faire dévier vers charteRoute. Les tests
  // dédiés à la charte, plus bas, le font varier explicitement.
  String? gate(AccountStatus s, String loc, {bool grace = false, String? charte = LegalDocuments.charteVersion}) =>
      accountRedirect(status: s, location: loc, graceActive: grace, charteVersion: charte);

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

  // Une session à renouveler (jeton révoqué par le serveur, ex. après une
  // réinitialisation de mot de passe) ne doit jamais fermer l'accès à
  // l'application : ni la carte, ni le SOS, ni la détection de chute. Voir
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
  // un (voir AccountBanner et le chapitre 7.2 de la spec pour le délai de
  // grâce, le chapitre 6.5 pour la session à renouveler).
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

  test('le delai de grace actif affiche son bandeau pour un rider deconnecte', () {
    expect(
      accountBannerKind(status: AccountStatus.deconnecte, graceActive: true),
      AccountBannerKind.delaiDeGrace,
    );
  });

  // Re-revue de branche : le bandeau ne regardait que graceActive, sans
  // tenir compte du statut. Parcours réel qui en résultait : installation
  // ancienne → bandeau → le rider clique « Créer mon compte » → connecte —
  // et le bandeau revenait quand même à chaque lancement pendant le reste
  // des trente jours, avec un bouton qui le renvoyait juste sur la carte.
  // On le harcelait pour une chose déjà faite.
  test('un rider connecte avec un delai de grace encore actif ne voit aucun bandeau', () {
    expect(
      accountBannerKind(status: AccountStatus.connecte, graceActive: true),
      AccountBannerKind.aucun,
    );
  });

  test('le delai de grace ne beneficie qu a un rider deconnecte, quel que soit l autre statut', () {
    for (final statut in AccountStatus.values) {
      if (statut == AccountStatus.sessionARenouveler || statut == AccountStatus.deconnecte) {
        continue;
      }
      expect(
        accountBannerKind(status: statut, graceActive: true),
        AccountBannerKind.aucun,
        reason: '$statut avec un delai actif ne doit afficher aucun bandeau',
      );
    }
  });

  test('aucun bandeau sans session a renouveler ni delai de grace actif', () {
    for (final statut in AccountStatus.values) {
      if (statut == AccountStatus.sessionARenouveler) continue;
      expect(accountBannerKind(status: statut, graceActive: false), AccountBannerKind.aucun);
    }
  });

  // ── Charte du pilote (Tâche 23B) ──────────────────────────────
  //
  // La charte s'interpose au même niveau que la vérification d'adresse,
  // mais après elle : un rider connecté (adresse vérifiée) dont le compte
  // n'a pas la version courante de la charte (y compris `null`, cas d'un
  // compte créé avant cette fonctionnalité) est retenu sur charteRoute,
  // carte comprise.
  test('un rider connecte sans charte acceptee est retenu sur l ecran de la charte', () {
    expect(gate(AccountStatus.connecte, '/', charte: null), charteRoute);
    expect(gate(AccountStatus.connecte, '/sos', charte: null), charteRoute);
  });

  test('une version de charte perimee retient aussi le rider', () {
    expect(gate(AccountStatus.connecte, '/', charte: '0.9'), charteRoute);
  });

  test('sur l ecran de la charte lui meme, aucune redirection tant qu elle n est pas acceptee', () {
    expect(gate(AccountStatus.connecte, charteRoute, charte: null), isNull);
  });

  test('une charte acceptee dans sa version courante laisse passer vers la carte', () {
    expect(gate(AccountStatus.connecte, '/', charte: LegalDocuments.charteVersion), isNull);
  });

  test('une charte deja acceptee ne fait pas revenir sur son propre ecran', () {
    expect(gate(AccountStatus.connecte, charteRoute, charte: LegalDocuments.charteVersion), '/');
  });

  // Priorité des murs : un compte non vérifié n'atteint jamais la charte,
  // même sans l'avoir acceptée — il doit d'abord confirmer son adresse.
  test('un compte non verifie est retenu sur la verification, pas sur la charte', () {
    expect(gate(AccountStatus.nonVerifie, '/', charte: null), '/verification');
  });

  // Correctif I7 (lot A) : une session à renouveler ne doit jamais fermer
  // l'accès à la carte, au SOS, au solo ni à la détection de chute — la
  // charte ne doit pas devenir un nouveau mur pour cet état, quelle que
  // soit sa valeur.
  test('une session a renouveler n est jamais bloquee par la charte', () {
    expect(gate(AccountStatus.sessionARenouveler, '/', charte: null), isNull);
    expect(gate(AccountStatus.sessionARenouveler, '/sos', charte: null), isNull);
  });
}
