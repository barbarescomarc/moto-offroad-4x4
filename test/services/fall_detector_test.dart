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
  test('a shock followed by settling into a new orientation that holds fires the callback', () async {
    final accel = StreamController<List<double>>();
    final positions = StreamController<GpsSnapshot>();
    var fired = false;
    final detector = FallDetector(
      accelerometer: accel.stream, positions: positions.stream,
      shockThreshold: () => 10.0,
      stopWindow: const Duration(milliseconds: 80),
      settleDelay: const Duration(milliseconds: 20),
      stopSpeedKmh: 3.0, tiltMaxDeg: 5.0,
    );
    detector.start(onFallDetected: () => fired = true);

    accel.add([0, 0, 9.8]);        // repos avant le choc, orientation verticale
    await Future.delayed(const Duration(milliseconds: 5));
    accel.add([15, 0, 0]);         // choc : fenêtre de 80ms et délai de stabilisation de 20ms démarrent
    await Future.delayed(const Duration(milliseconds: 5));
    accel.add([9.8, 4, 2]);        // encore en mouvement juste après l'impact
    await Future.delayed(const Duration(milliseconds: 5));
    accel.add([0, 9.8, 0]);        // position d'arrivée atteinte, marge confortable avant la fin du délai de stabilisation
    await Future.delayed(const Duration(milliseconds: 15)); // le délai de stabilisation (nominal t=25) expire ici : origine = [0, 9.8, 0]
    positions.add(_snap(1.0));     // arrêt : sous 3 km/h
    accel.add([0, 9.8, 0]);        // même orientation que la position d'arrivée, marge apres l'expiration : ça tient

    await Future.delayed(const Duration(milliseconds: 60)); // laisse le reste de la fenêtre s'écouler

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

  test('continued movement after settling cancels the detection', () async {
    final accel = StreamController<List<double>>();
    final positions = StreamController<GpsSnapshot>();
    var fired = false;
    final detector = FallDetector(
      accelerometer: accel.stream, positions: positions.stream,
      shockThreshold: () => 10.0,
      stopWindow: const Duration(milliseconds: 80),
      settleDelay: const Duration(milliseconds: 20),
      stopSpeedKmh: 3.0, tiltMaxDeg: 5.0,
    );
    detector.start(onFallDetected: () => fired = true);

    accel.add([0, 0, 9.8]);        // repos avant le choc
    await Future.delayed(const Duration(milliseconds: 5));
    accel.add([15, 0, 0]);         // choc
    await Future.delayed(const Duration(milliseconds: 10));
    accel.add([0, 9.8, 0]);        // position d'arrivée, avant la fin du délai de stabilisation
    await Future.delayed(const Duration(milliseconds: 15)); // le délai de stabilisation expire ici : origine = [0, 9.8, 0]
    positions.add(_snap(1.0));     // arrêt : sous 3 km/h, ne doit pas annuler
    accel.add([9.8, 0, 0]);        // mouvement après stabilisation : orientation différente de l'origine (~90°)

    await Future.delayed(const Duration(milliseconds: 60));

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
