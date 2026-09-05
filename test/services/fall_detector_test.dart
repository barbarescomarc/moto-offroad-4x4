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

  test('no GPS ever received: a big shock, changed orientation, and idle-level vibration together fire', () async {
    final accel = StreamController<List<double>>();
    final positions = StreamController<GpsSnapshot>();
    var fired = false;
    final detector = FallDetector(
      accelerometer: accel.stream, positions: positions.stream,
      shockThreshold: () => 10.0,
      stopWindow: const Duration(milliseconds: 80),
      settleDelay: const Duration(milliseconds: 20),
      stopSpeedKmh: 3.0, tiltMaxDeg: 5.0,
      noGpsShockMultiplier: 2.0,
      noGpsTiltFromRidingDeg: 20.0,
      idleVibrationLevel: () => 1.0,
      idleVibrationMultiplier: 1.5,
      vibrationWindowSize: 3,
    );
    detector.start(onFallDetected: () => fired = true);

    accel.add([0, 0, 9.8]);        // orientation de conduite, avant le choc
    await Future.delayed(const Duration(milliseconds: 5));
    accel.add([25, 0, 0]);         // choc bien au-dessus du seuil sans GPS (10*2.0=20)
    await Future.delayed(const Duration(milliseconds: 10));
    accel.add([0, 9.8, 0]);        // en cours de stabilisation, avant la fin du delai
    await Future.delayed(const Duration(milliseconds: 15)); // origine capturee ici : [0,9.8,0]
    accel.add([0, 9.8, 0]);        // tient, meme magnitude — vide la secousse du choc de la fenetre glissante
    await Future.delayed(const Duration(milliseconds: 10));
    accel.add([0, 9.8, 0]);        // encore la meme — vibrations au niveau du ralenti (ecart-type nul)

    await Future.delayed(const Duration(milliseconds: 50)); // laisse le reste de la fenetre s'ecouler

    expect(fired, isTrue);
    detector.stop();
    await accel.close();
    await positions.close();
  });

  test('no GPS ever received: a shock below the no-GPS threshold does not fire, even with the other two signals', () async {
    final accel = StreamController<List<double>>();
    final positions = StreamController<GpsSnapshot>();
    var fired = false;
    final detector = FallDetector(
      accelerometer: accel.stream, positions: positions.stream,
      shockThreshold: () => 10.0,
      stopWindow: const Duration(milliseconds: 80),
      settleDelay: const Duration(milliseconds: 20),
      stopSpeedKmh: 3.0, tiltMaxDeg: 5.0,
      noGpsShockMultiplier: 2.0,
      noGpsTiltFromRidingDeg: 20.0,
      idleVibrationLevel: () => 1.0,
      idleVibrationMultiplier: 1.5,
      vibrationWindowSize: 3,
    );
    detector.start(onFallDetected: () => fired = true);

    accel.add([0, 0, 9.8]);
    await Future.delayed(const Duration(milliseconds: 5));
    accel.add([15, 0, 0]);         // magnitude 15 : depasse le seuil normal (10) mais pas 10*2.0=20
    await Future.delayed(const Duration(milliseconds: 10));
    accel.add([0, 9.8, 0]);
    await Future.delayed(const Duration(milliseconds: 15)); // origine : [0,9.8,0]
    accel.add([0, 9.8, 0]);
    await Future.delayed(const Duration(milliseconds: 10));
    accel.add([0, 9.8, 0]);

    await Future.delayed(const Duration(milliseconds: 50));

    expect(fired, isFalse);
    detector.stop();
    await accel.close();
    await positions.close();
  });

  test('no GPS ever received: settling into the same orientation as riding does not fire', () async {
    final accel = StreamController<List<double>>();
    final positions = StreamController<GpsSnapshot>();
    var fired = false;
    final detector = FallDetector(
      accelerometer: accel.stream, positions: positions.stream,
      shockThreshold: () => 10.0,
      stopWindow: const Duration(milliseconds: 80),
      settleDelay: const Duration(milliseconds: 20),
      stopSpeedKmh: 3.0, tiltMaxDeg: 5.0,
      noGpsShockMultiplier: 2.0,
      noGpsTiltFromRidingDeg: 20.0,
      idleVibrationLevel: () => 1.0,
      idleVibrationMultiplier: 1.5,
      vibrationWindowSize: 3,
    );
    detector.start(onFallDetected: () => fired = true);

    accel.add([0, 0, 9.8]);        // orientation de conduite
    await Future.delayed(const Duration(milliseconds: 5));
    accel.add([25, 0, 0]);         // choc bien au-dessus du seuil sans GPS
    await Future.delayed(const Duration(milliseconds: 10));
    accel.add([0, 0, 9.8]);        // se stabilise dans LA MEME orientation que la conduite
    await Future.delayed(const Duration(milliseconds: 15)); // origine : [0,0,9.8] — identique a la conduite
    accel.add([0, 0, 9.8]);
    await Future.delayed(const Duration(milliseconds: 10));
    accel.add([0, 0, 9.8]);

    await Future.delayed(const Duration(milliseconds: 50));

    expect(fired, isFalse);
    detector.stop();
    await accel.close();
    await positions.close();
  });

  test('no GPS ever received: vibration still at riding level after settling does not fire', () async {
    final accel = StreamController<List<double>>();
    final positions = StreamController<GpsSnapshot>();
    var fired = false;
    final detector = FallDetector(
      accelerometer: accel.stream, positions: positions.stream,
      shockThreshold: () => 10.0,
      stopWindow: const Duration(milliseconds: 80),
      settleDelay: const Duration(milliseconds: 20),
      stopSpeedKmh: 3.0, tiltMaxDeg: 5.0,
      noGpsShockMultiplier: 2.0,
      noGpsTiltFromRidingDeg: 20.0,
      idleVibrationLevel: () => 1.0,
      idleVibrationMultiplier: 1.5,
      vibrationWindowSize: 3,
    );
    detector.start(onFallDetected: () => fired = true);

    accel.add([0, 0, 9.8]);        // orientation de conduite
    await Future.delayed(const Duration(milliseconds: 5));
    accel.add([25, 0, 0]);         // choc bien au-dessus du seuil sans GPS
    await Future.delayed(const Duration(milliseconds: 10));
    accel.add([0, 9.8, 0]);        // en cours de stabilisation
    await Future.delayed(const Duration(milliseconds: 15)); // origine : [0,9.8,0]
    accel.add([0, 9.8, 0]);        // meme direction que l'origine (angle 0, ne coupe pas la fenetre)
    await Future.delayed(const Duration(milliseconds: 10));
    accel.add([0, 15, 0]);         // meme direction, magnitude tres differente : vibration
    await Future.delayed(const Duration(milliseconds: 5));
    accel.add([0, 5, 0]);          // idem
    await Future.delayed(const Duration(milliseconds: 5));
    accel.add([0, 16, 0]);         // idem — les 3 derniers echantillons de la fenetre glissante ont un ecart-type eleve

    await Future.delayed(const Duration(milliseconds: 35));

    expect(fired, isFalse);
    detector.stop();
    await accel.close();
    await positions.close();
  });
}
