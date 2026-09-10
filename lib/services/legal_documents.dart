import 'package:flutter/services.dart' show rootBundle;

/// Point d'accès unique aux textes légaux embarqués dans l'application.
///
/// Le texte de loi vit dans `docs/legal/*.md`, versionné avec le code et
/// déclaré en ressource dans `pubspec.yaml` — jamais recopié en dur dans du
/// Dart, pour qu'une correction n'ait jamais à être faite à deux endroits.
class LegalDocuments {
  const LegalDocuments._();

  /// Version courante de la charte du pilote. C'est cette valeur que
  /// `accountRedirect` (voir `account_gate.dart`) compare à
  /// `AccountProvider.charteVersion` pour décider d'interposer
  /// `CharteScreen`, et celle que `RegisterScreen` envoie à l'inscription —
  /// un compte créé depuis cette version n'a donc jamais à repasser par
  /// l'écran.
  static const String charteVersion = '1.0';

  /// Charte du pilote : limites de la détection de chute et de la chaîne
  /// d'alerte, présentée à tout rider avant l'accès à la carte.
  static Future<String> charte() => rootBundle.loadString('docs/legal/charte-du-pilote.md');

  /// Conditions de publication et d'utilisation du catalogue partagé,
  /// présentées avant la première publication d'une trace.
  static Future<String> conditionsPublication() =>
      rootBundle.loadString('docs/legal/conditions-publication-traces.md');
}
