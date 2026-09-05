import 'package:flutter_test/flutter_test.dart';
import 'package:moto_offroad/services/fall_thresholds.dart';
import 'package:moto_offroad/services/vibration_calibration.dart';

void main() {
  test('uncalibrated falls back to exactly 4g', () {
    const cal = VibrationCalibration();
    expect(shockThresholdMs2(cal), closeTo(4.0 * 9.81, 0.001));
  });

  test('a calibration at the default idle level matches the 4g fallback', () {
    final cal = VibrationCalibration(
      stillLevel: VibrationCalibration.defaultThreshold * 0.3,
      idleLevel: VibrationCalibration.defaultThreshold,
    );
    expect(shockThresholdMs2(cal), closeTo(4.0 * 9.81, 0.01));
  });

  test('a noisier bike (higher idle level) raises the threshold, bounded at 3x', () {
    final cal = VibrationCalibration(
      stillLevel: VibrationCalibration.defaultThreshold * 0.3,
      idleLevel: VibrationCalibration.defaultThreshold * 100, // extrême, pour tester la borne
    );
    expect(shockThresholdMs2(cal), closeTo(4.0 * 9.81 * 3.0, 0.01));
  });

  test('a quieter bike (lower idle level) lowers the threshold, bounded at 0.5x', () {
    final cal = VibrationCalibration(
      stillLevel: 0.001,
      idleLevel: VibrationCalibration.defaultThreshold * 0.01, // extrême, pour tester la borne
    );
    expect(shockThresholdMs2(cal), closeTo(4.0 * 9.81 * 0.5, 0.01));
  });
}
