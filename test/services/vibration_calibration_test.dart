import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moto_offroad/services/vibration_calibration.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sans calibration, le seuil par défaut s applique', () {
    const cal = VibrationCalibration();
    expect(cal.isCalibrated, isFalse);
    expect(cal.threshold, VibrationCalibration.defaultThreshold);
  });

  test('le seuil se place à 35 % de l écart entre les deux mesures', () {
    const cal = VibrationCalibration(stillLevel: 0.02, idleLevel: 0.32);
    expect(cal.isCalibrated, isTrue);
    expect(cal.threshold, closeTo(0.125, 0.001));
  });

  test('une calibration incohérente retombe sur le seuil par défaut', () {
    // Le ralenti ne peut pas produire moins de vibration que l arrêt moteur.
    const cal = VibrationCalibration(stillLevel: 0.40, idleLevel: 0.10);
    expect(cal.isCalibrated, isFalse);
    expect(cal.threshold, VibrationCalibration.defaultThreshold);
  });

  test('une mesure seule ne suffit pas à calibrer', () {
    const cal = VibrationCalibration(stillLevel: 0.02);
    expect(cal.isCalibrated, isFalse);
  });

  test('la calibration survit à un enregistrement puis relecture', () async {
    SharedPreferences.setMockInitialValues({});
    await const VibrationCalibration(stillLevel: 0.05, idleLevel: 0.45).save();
    final loaded = await VibrationCalibration.load();
    expect(loaded.stillLevel, 0.05);
    expect(loaded.idleLevel, 0.45);
    expect(loaded.threshold, closeTo(0.19, 0.001));
  });

  test('sans rien en mémoire, load renvoie une calibration vide', () async {
    SharedPreferences.setMockInitialValues({});
    final loaded = await VibrationCalibration.load();
    expect(loaded.isCalibrated, isFalse);
  });
}
