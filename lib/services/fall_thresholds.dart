import 'vibration_calibration.dart';

// ── Seuil de choc pour la détection de chute ─────────────────
//
// 4g est le repli du spec quand rien n'est calibré. Une fois calibré, le
// seuil est mis à l'échelle du niveau de vibration au ralenti propre à la
// moto et au montage du téléphone : un ralenti plus bruyant exige un choc
// plus franc pour ne pas confondre les cahots du terrain avec une chute,
// et inversement. L'échelle est bornée [0.5, 3] pour qu'une calibration
// aberrante ne rende jamais la détection absurdement permissive ou
// hypersensible.
const double _fallbackG = 4.0;
const double _gravity = 9.81;

double shockThresholdMs2(VibrationCalibration calibration) {
  if (!calibration.isCalibrated) return _fallbackG * _gravity;
  final scale = (calibration.idleLevel! / VibrationCalibration.defaultThreshold).clamp(0.5, 3.0);
  return _fallbackG * _gravity * scale;
}
