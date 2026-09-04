// ── Verrou d'abonnement ───────────────────────────────────────
//
// Une seule question : ce canal est-il déverrouillé ? Répond toujours non
// tant qu'aucun système d'abonnement n'existe. Brancher l'abonnement plus
// tard consistera à changer cette réponse, pas à restructurer la chaîne
// d'alerte qui l'appelle.
class AlertChannelUnlock {
  bool isUnlocked(String channel) => false;
}
