// ── Comparaison de numéros de téléphone ──────────────────────
//
// Un contact peut être enregistré en écriture internationale (+33 6 …) et
// appeler en écriture nationale (06 …). Comparer les 9 derniers chiffres
// rend les deux équivalentes sans avoir à connaître les indicatifs pays.
class PhoneNumberMatcher {
  static const int _significantDigits = 9;

  /// Retire tout ce qui n'est pas un chiffre, puis ne garde que la fin
  /// significative du numéro.
  static String normalize(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length <= _significantDigits) return digits;
    return digits.substring(digits.length - _significantDigits);
  }

  /// Vrai si les deux numéros désignent la même ligne. Un numéro vide —
  /// appel masqué, ou permission READ_CALL_LOG refusée — ne correspond à rien.
  static bool matches(String a, String b) {
    final na = normalize(a);
    final nb = normalize(b);
    if (na.isEmpty || nb.isEmpty) return false;
    return na == nb;
  }
}
