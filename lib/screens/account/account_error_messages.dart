import '../../services/account_api_client.dart';

/// Longueur minimale du mot de passe, vérifiée côté application avant tout
/// appel réseau — le serveur applique la même règle (voir
/// `AccountApiClient._errorFor`), mais la refuser localement évite un aller-
/// retour inutile et donne une réponse instantanée au rider.
const int kMinPasswordLength = 10;

/// Message lisible pour chaque cause d'échec identifiée par [AccountError].
///
/// Point unique de traduction des erreurs de compte : les cinq écrans du
/// dossier `account/` l'appellent tous, plutôt que de recopier ces phrases
/// chacun de leur côté. Une panne réseau doit toujours être nommée comme
/// telle (voir `AccountError.reseau`) : jamais confondue avec un refus du
/// serveur, jamais passée sous silence.
String messagePour(AccountError erreur) {
  switch (erreur) {
    case AccountError.reseau:
      return 'Une connexion internet est nécessaire pour continuer. Réessaie.';
    case AccountError.adresseDejaPrise:
      return 'Cette adresse est déjà inscrite. Connecte-toi plutôt.';
    case AccountError.motDePasseTropCourt:
      return 'Mot de passe de $kMinPasswordLength caractères minimum.';
    case AccountError.adresseInvalide:
      return 'Cette adresse ne semble pas valide.';
    case AccountError.identifiants:
      return 'Adresse ou mot de passe incorrect.';
    case AccountError.tropDeTentatives:
      return 'Trop de tentatives. Patiente quelques minutes avant de réessayer.';
    case AccountError.inconnue:
      return 'Une erreur est survenue. Réessaie.';
  }
}
