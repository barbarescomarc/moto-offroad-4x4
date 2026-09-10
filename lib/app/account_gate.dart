import '../providers/account_provider.dart';
import '../services/legal_documents.dart';

/// Chemins accessibles sans compte : les écrans du compte lui-même.
const Set<String> accountRoutes = {'/bienvenue', '/inscription', '/connexion', '/mot-de-passe-oublie'};
const String verificationRoute = '/verification';

/// Écran de la charte du pilote (Tâche 23B) : mur interposé entre la
/// vérification d'adresse et le reste de l'application, y compris pour un
/// rider inscrit avant l'existence de cette fonctionnalité (charteVersion
/// `null` côté serveur — voir `AccountProvider.charteVersion`).
const String charteRoute = '/charte';

/// Règle d'accès à l'application. Fonction pure : c'est la décision la plus
/// lourde de conséquences du lot, elle se teste sans monter d'interface.
///
/// [graceActive] n'est vrai que pour une installation antérieure aux comptes,
/// et seulement pendant ses trente premiers jours — voir `GraceWindow`.
String? accountRedirect({
  required AccountStatus status,
  required String location,
  required bool graceActive,
  String? charteVersion,
}) {
  final surEcranDeCompte = accountRoutes.contains(location);

  switch (status) {
    case AccountStatus.chargement:
      return null;

    case AccountStatus.deconnecte:
      if (surEcranDeCompte) return null;
      if (graceActive) return null;
      return '/bienvenue';

    case AccountStatus.sessionARenouveler:
      // Jeton révoqué côté serveur, mais rien ne se ferme pour autant :
      // carte, GPS, SOS et détection de chute restent accessibles (chapitre
      // 6.5 de la spec). Ne jamais rediriger — y compris depuis /connexion,
      // que le rider doit pouvoir atteindre s'il choisit de se reconnecter
      // de lui-même.
      return null;

    case AccountStatus.nonVerifie:
      // Le délai de grâce ne s'applique pas ici : un compte a été créé, son
      // adresse doit être confirmée.
      return location == verificationRoute ? null : verificationRoute;

    case AccountStatus.connecte:
      if (surEcranDeCompte || location == verificationRoute) return '/';
      // La charte est un mur au même titre que la vérification d'adresse,
      // juste après elle : tant qu'elle n'est pas acceptée dans sa version
      // courante, rien d'autre n'est atteignable — carte comprise. Ne
      // jamais monter la carte avant cette vérification : son initState
      // demanderait aussitôt la permission de localisation (correctif I7,
      // voir _MapGate dans router.dart), avant même que ce mur ait pu
      // s'appliquer.
      if (charteVersion != LegalDocuments.charteVersion) {
        return location == charteRoute ? null : charteRoute;
      }
      if (location == charteRoute) return '/';
      return null;
  }
}

/// Quel bandeau non bloquant afficher dans `MainShell`, s'il y en a un.
///
/// Fonction pure, sur le modèle d'[accountRedirect] : les deux besoins qui
/// justifient un bandeau (délai de grâce et session à renouveler) partagent
/// le même mécanisme d'affichage (voir `AccountBanner`), mais jamais en
/// même temps — une session à renouveler suppose un compte déjà créé, le
/// délai de grâce ne concerne que les installations qui n'en ont aucun.
enum AccountBannerKind { aucun, sessionExpiree, delaiDeGrace }

AccountBannerKind accountBannerKind({
  required AccountStatus status,
  required bool graceActive,
}) {
  if (status == AccountStatus.sessionARenouveler) return AccountBannerKind.sessionExpiree;
  // `graceActive` seul ne suffit pas : c'est une échéance calculée une fois
  // à l'installation (voir GraceWindow), indépendante du compte — elle reste
  // vraie pendant tout le reste des trente jours même après l'inscription.
  // Sans cette garde sur le statut, un rider qui vient de créer son compte
  // continuait de voir le bandeau à chaque lancement, avec un bouton qui le
  // renvoyait simplement sur la carte : harcelé pour une chose déjà faite.
  if (status == AccountStatus.deconnecte && graceActive) return AccountBannerKind.delaiDeGrace;
  return AccountBannerKind.aucun;
}
