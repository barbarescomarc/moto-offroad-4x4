import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:moto_offroad/services/vibration_meter.dart';

void main() {
  test('sans échantillon le niveau est nul', () {
    expect(VibrationMeter().level, 0);
  });

  test('un signal constant donne un niveau nul même à forte magnitude', () {
    final meter = VibrationMeter(windowSize: 10);
    for (int i = 0; i < 10; i++) {
      meter.addSample(9.81);
    }
    expect(meter.level, closeTo(0, 0.0001));
  });

  test('un signal qui oscille donne un niveau non nul', () {
    final meter = VibrationMeter(windowSize: 10);
    for (int i = 0; i < 10; i++) {
      meter.addSample(i.isEven ? 9.6 : 10.0);
    }
    expect(meter.level, closeTo(0.2, 0.01));
  });

  test('la fenêtre glisse : le bruit ancien est oublié', () {
    final meter = VibrationMeter(windowSize: 10);
    for (int i = 0; i < 10; i++) {
      meter.addSample(i.isEven ? 5.0 : 15.0);
    }
    expect(meter.level, greaterThan(1));
    for (int i = 0; i < 10; i++) {
      meter.addSample(9.81);
    }
    expect(meter.level, closeTo(0, 0.0001));
  });

  test('reset vide la fenêtre', () {
    final meter = VibrationMeter(windowSize: 10);
    meter.addSample(1);
    meter.addSample(20);
    meter.reset();
    expect(meter.level, 0);
  });

  test('la magnitude combine les trois axes', () {
    expect(VibrationMeter.magnitudeOf(0, 0, 9.81), closeTo(9.81, 0.001));
    expect(VibrationMeter.magnitudeOf(3, 4, 0), closeTo(5, 0.001));
    expect(VibrationMeter.magnitudeOf(1, 1, 1), closeTo(sqrt(3), 0.001));
  });
}
