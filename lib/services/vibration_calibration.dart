import 'package:shared_preferences/shared_preferences.dart';

// ── Calibration des vibrations ───────────────────────────────
// Un seul jeu de mesures, refait quand le pilote change de moto ou de
// position de téléphone.
class VibrationCalibration {
  static const String _kStill = 'vibration_still_level';
  static const String _kIdle  = 'vibration_idle_level';

  // Seuil retenu tant que le pilote n'a pas calibré.
  static const double defaultThreshold = 0.12;

  // Position du seuil entre les deux mesures. Volontairement bas :
  // en cas de doute, on continue d'enregistrer.
  static const double _ratio = 0.35;

  // Repli non calibré pour un niveau de vibration « au ralenti » (utilisé
  // par FallDetector quand rien n'est calibré). Remonte le ratio utilisé
  // pour choisir defaultThreshold plutôt que de réutiliser ce seuil de choc
  // tel quel comme s'il était déjà un niveau de vibration : le seuil est
  // délibérément à _ratio du ralenti, pas au ralenti lui-même — le
  // réutiliser directement rendrait le repli ~3x trop strict.
  static const double defaultIdleLevel = defaultThreshold / _ratio;

  final double? stillLevel;   // moteur coupé
  final double? idleLevel;    // moteur au ralenti

  const VibrationCalibration({this.stillLevel, this.idleLevel});

  bool get isCalibrated =>
      stillLevel != null && idleLevel != null && idleLevel! > stillLevel!;

  double get threshold => isCalibrated
      ? stillLevel! + (idleLevel! - stillLevel!) * _ratio
      : defaultThreshold;

  // ── Persistance ──────────────────────────────────────────
  static Future<VibrationCalibration> load() async {
    final prefs = await SharedPreferences.getInstance();
    return VibrationCalibration(
      stillLevel: prefs.getDouble(_kStill),
      idleLevel:  prefs.getDouble(_kIdle),
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    if (stillLevel != null) await prefs.setDouble(_kStill, stillLevel!);
    if (idleLevel  != null) await prefs.setDouble(_kIdle,  idleLevel!);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kStill);
    await prefs.remove(_kIdle);
  }
}
