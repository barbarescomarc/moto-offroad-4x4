import '../providers/account_provider.dart';

/// Chemins accessibles sans compte : les écrans du compte lui-même.
const Set<String> accountRoutes = {'/bienvenue', '/inscription', '/connexion', '/mot-de-passe-oublie'};
const String verificationRoute = '/verification';

/// Règle d'accès à l'application. Fonction pure : c'est la décision la plus
/// lourde de conséquences du lot, elle se teste sans monter d'interface.
///
/// [graceActive] n'est vrai que pour une installation antérieure aux comptes,
/// et seulement pendant ses trente premiers jours — voir `GraceWindow`.
String? accountRedirect({
  required AccountStatus status,
  required String location,
  required bool graceActive,
}) {
  final surEcranDeCompte = accountRoutes.contains(location);

  switch (status) {
    case AccountStatus.chargement:
      return null;

    case AccountStatus.deconnecte:
      if (surEcranDeCompte) return null;
      if (graceActive) return null;
      return '/bienvenue';

    case AccountStatus.nonVerifie:
      // Le délai de grâce ne s'applique pas ici : un compte a été créé, son
      // adresse doit être confirmée.
      return location == verificationRoute ? null : verificationRoute;

    case AccountStatus.connecte:
      if (surEcranDeCompte || location == verificationRoute) return '/';
      return null;
  }
}
