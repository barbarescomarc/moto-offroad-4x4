import 'phone_number_matcher.dart';

// ── Faut-il répondre à cet appel ? ───────────────────────────
//
// Deux garde-fous encadrent la fonction (spec §9.1) :
//   — elle ne s'active que pendant une sortie, sinon le téléphone posé sur une
//     table répondrait « je roule » à tout le monde ;
//   — elle ne répond qu'aux contacts de confiance, sinon la position GPS
//     partirait vers des démarcheurs.
class AutoReplyPolicy {
  final bool enabled;
  final bool allCallers;
  final bool riding;
  final List<String> trustedPhones;

  const AutoReplyPolicy({
    required this.enabled,
    required this.allCallers,
    required this.riding,
    required this.trustedPhones,
  });

  bool shouldReply(String callerNumber) {
    if (!enabled || !riding) return false;

    // Numéro masqué, ou permission READ_CALL_LOG refusée : aucun destinataire
    // possible, et aucun moyen de savoir à qui on parlerait.
    if (PhoneNumberMatcher.normalize(callerNumber).isEmpty) return false;

    if (allCallers) return true;
    return trustedPhones.any((p) => PhoneNumberMatcher.matches(p, callerNumber));
  }
}
