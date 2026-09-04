import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:moto_offroad/services/fall_detector.dart';
import 'package:moto_offroad/services/location_service.dart';

GpsSnapshot _snap(double speedKmh) => GpsSnapshot(
  position: const LatLng(45, 5), accuracyMeters: 5, altitudeMeters: 100,
  speedKmh: speedKmh, headingDeg: 0, timestamp: DateTime.now(),
);

void main() {
  test('a shock followed by full stillness and no tilt for the whole window fires the callback', () async {
    final accel = StreamController<List<double>>();
    final positions = StreamController<GpsSnapshot>();
    var fired = false;
    final detector = FallDetector(
      accelerometer: accel.stream, positions: positions.stream,
      shockThreshold: () => 10.0,
      stopWindow: const Duration(milliseconds: 60),
      stopSpeedKmh: 3.0, tiltMaxDeg: 5.0,
    );
    detector.start(onFallDetected: () => fired = true);

    accel.add([0, 0, 9.8]);       // repos, sous le seuil
    await Future.delayed(const Duration(milliseconds: 5));
    accel.add([15, 0, 0]);        // choc : magnitude 15 > seuil 10
    await Future.delayed(const Duration(milliseconds: 5));
    positions.add(_snap(1.0));    // arrêt : sous 3 km/h
    accel.add([0, 0, 9.8]);       // même orientation que l'origine du choc

    await Future.delayed(const Duration(milliseconds: 80)); // laisse la fenêtre de 60ms s'écouler

    expect(fired, isTrue);
    detector.stop();
    await accel.close();
    await positions.close();
  });

  test('movement during the window cancels the detection', () async {
    final accel = StreamController<List<double>>();
    final positions = StreamController<GpsSnapshot>();
    var fired = false;
    final detector = FallDetector(
      accelerometer: accel.stream, positions: positions.stream,
      shockThreshold: () => 10.0,
      stopWindow: const Duration(milliseconds: 60),
    );
    detector.start(onFallDetected: () => fired = true);

    accel.add([15, 0, 0]); // choc
    await Future.delayed(const Duration(milliseconds: 10));
    positions.add(_snap(20.0)); // le pilote roule encore : pas une chute
    await Future.delayed(const Duration(milliseconds: 80));

    expect(fired, isFalse);
    detector.stop();
    await accel.close();
    await positions.close();
  });

  test('a tilt change during the window cancels the detection', () async {
    final accel = StreamController<List<double>>();
    final positions = StreamController<GpsSnapshot>();
    var fired = false;
    final detector = FallDetector(
      accelerometer: accel.stream, positions: positions.stream,
      shockThreshold: () => 10.0,
      stopWindow: const Duration(milliseconds: 60),
      tiltMaxDeg: 5.0,
    );
    detector.start(onFallDetected: () => fired = true);

    accel.add([0, 0, 9.8]);   // origine du choc : vertical
    await Future.delayed(const Duration(milliseconds: 5));
    accel.add([15, 0, 0]);    // choc (magnitude 15, la direction sert d'origine de tilt)
    await Future.delayed(const Duration(milliseconds: 10));
    positions.add(_snap(1.0)); // immobile
    accel.add([0, 15, 0]);     // orientation totalement différente : > 5° de l'origine
    await Future.delayed(const Duration(milliseconds: 80));

    expect(fired, isFalse);
    detector.stop();
    await accel.close();
    await positions.close();
  });

  test('a sub-threshold jolt never starts watching', () async {
    final accel = StreamController<List<double>>();
    final positions = StreamController<GpsSnapshot>();
    var fired = false;
    final detector = FallDetector(
      accelerometer: accel.stream, positions: positions.stream,
      shockThreshold: () => 10.0,
      stopWindow: const Duration(milliseconds: 30),
    );
    detector.start(onFallDetected: () => fired = true);

    accel.add([3, 0, 0]); // magnitude 3, sous le seuil de 10
    await Future.delayed(const Duration(milliseconds: 60));

    expect(fired, isFalse);
    detector.stop();
    await accel.close();
    await positions.close();
  });

  test('stop() prevents a callback from firing after a shock already in progress', () async {
    final accel = StreamController<List<double>>();
    final positions = StreamController<GpsSnapshot>();
    var fired = false;
    final detector = FallDetector(
      accelerometer: accel.stream, positions: positions.stream,
      shockThreshold: () => 10.0,
      stopWindow: const Duration(milliseconds: 30),
    );
    detector.start(onFallDetected: () => fired = true);

    accel.add([15, 0, 0]); // choc, la fenêtre de 30ms démarre
    await Future.delayed(const Duration(milliseconds: 5));
    detector.stop();
    await Future.delayed(const Duration(milliseconds: 60)); // largement au-delà de la fenêtre

    expect(fired, isFalse);
    await accel.close();
    await positions.close();
  });
}
