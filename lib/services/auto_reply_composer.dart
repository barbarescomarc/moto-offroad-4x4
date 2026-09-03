import 'location_service.dart';

// ── Composition du SMS d'auto-réponse ────────────────────────
class AutoReplyComposer {
  /// Assemble le texte envoyé au correspondant.
  ///
  /// Si la position est demandée mais indisponible — GPS pas encore accroché,
  /// tunnel, permission refusée — le message part malgré tout en le signalant.
  /// Un SMS de sécurité muet serait pire qu'un SMS incomplet.
  static String compose({
    required String message,
    required bool attachPosition,
    GpsSnapshot? snapshot,
  }) {
    if (!attachPosition) return message;

    if (snapshot == null) {
      return '$message\n\n(position indisponible pour le moment)';
    }

    return '$message\n\n'
        'Je suis ici :\n'
        '${snapshot.sosText}\n\n'
        '${snapshot.googleMapsUrl}';
  }
}
