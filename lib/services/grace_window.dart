import 'package:shared_preferences/shared_preferences.dart';

/// CODE TEMPORAIRE — à supprimer quand les installations antérieures aux
/// comptes auront quitté le parc (versions < 1.7.0). Retirer alors cette
/// classe, son appel dans `main.dart` et le paramètre `graceActive` de
/// `accountRedirect`.
///
/// Un rider qui utilise l'application depuis des semaines ne doit pas trouver
/// un mur d'inscription au départ d'une sortie, sans avertissement. La version
/// qui introduit les comptes reconnaît son installation à ses données locales
/// et lui laisse trente jours.
///
/// Échéance strictement locale, donc contournable en reculant l'horloge de
/// l'appareil. C'est assumé : ce délai est une politesse envers les riders
/// fidèles, pas un contrôle d'accès — ne pas chercher à le durcir.
class GraceWindow {
  static const String _kDeadline = 'account_grace_deadline_ms';
  static const Duration duration = Duration(days: 30);

  DateTime? _deadline;

  DateTime? get deadline => _deadline;

  bool get active {
    final echeance = _deadline;
    return echeance != null && DateTime.now().isBefore(echeance);
  }

  Future<void> evaluate({required bool hasLegacyData, DateTime? now}) async {
    final maintenant = now ?? DateTime.now();
    final prefs = await SharedPreferences.getInstance();

    // Une installation neuve ne recoit aucun delai, meme si une echeance
    // trainait dans les preferences : la sauvegarde automatique Android les
    // restaure lors d'une reinstallation, et un delai ressuscite ainsi serait
    // le moyen de contourner le mur d'inscription.
    if (!hasLegacyData) {
      await prefs.remove(_kDeadline);
      _deadline = null;
      return;
    }

    final stocke = prefs.getInt(_kDeadline);
    if (stocke != null) {
      _deadline = DateTime.fromMillisecondsSinceEpoch(stocke);
    } else {
      _deadline = maintenant.add(duration);
      await prefs.setInt(_kDeadline, _deadline!.millisecondsSinceEpoch);
    }

    if (!maintenant.isBefore(_deadline!)) _deadline = null;
  }
}

/// Instance unique, évaluée une fois dans `main.dart` et lue par le
/// `redirect` du routeur. Elle disparaît avec le reste du code temporaire.
final GraceWindow graceWindow = GraceWindow();
