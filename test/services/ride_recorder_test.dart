import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:moto_offroad/services/location_service.dart';
import 'package:moto_offroad/services/ride_recorder.dart';

final _t0 = DateTime(2026, 9, 2, 10, 0, 0);

GpsSnapshot _gps(double speedKmh, int secondsFromStart) => GpsSnapshot(
  position:       LatLng(44.0 + secondsFromStart * 0.0001, 6.0),
  accuracyMeters: 4,
  altitudeMeters: 300,
  speedKmh:       speedKmh,
  headingDeg:     90,
  timestamp:      _t0.add(Duration(seconds: secondsFromStart)),
);

// Alimente l'enregistreur pendant [seconds] secondes, un échantillon par
// seconde, à vitesse et vibration constantes.
void _feed(RideRecorder rec, {
  required double speedKmh,
  required double vibration,
  required int seconds,
  int from = 0,
}) {
  for (int s = from; s < from + seconds; s++) {
    rec.onSample(gps: _gps(speedKmh, s), vibrationLevel: vibration);
  }
}

RideRecorder _recorder({bool autoPause = true, double pauseSpeed = 2}) =>
    RideRecorder(
      rideId: 'r1',
      config: RecorderConfig(
        pauseSpeedKmh:       pauseSpeed,
        vibrationThreshold:  0.12,
        pauseDelay:          const Duration(seconds: 30),
        autoPauseEnabled:    autoPause,
      ),
    );

void main() {
  test('au départ l enregistreur est à l arrêt', () {
    expect(_recorder().state, RecorderState.idle);
  });

  test('tant qu il est à l arrêt, les échantillons sont ignorés', () {
    final rec = _recorder();
    _feed(rec, speedKmh: 40, vibration: 2, seconds: 5);
    expect(rec.pointCount, 0);
  });

  test('en roulage les points s accumulent sur le segment 0', () {
    final rec = _recorder()..start();
    _feed(rec, speedKmh: 40, vibration: 2, seconds: 10);
    expect(rec.state, RecorderState.recording);
    expect(rec.pointCount, 10);
    expect(rec.segment, 0);
  });

  test('immobile moins de 30 s, l enregistrement continue', () {
    final rec = _recorder()..start();
    _feed(rec, speedKmh: 0, vibration: 0.01, seconds: 20);
    expect(rec.state, RecorderState.recording);
  });

  test('immobile 30 s, la pause automatique se déclenche', () {
    final rec = _recorder()..start();
    _feed(rec, speedKmh: 0, vibration: 0.01, seconds: 31);
    expect(rec.state, RecorderState.paused);
    expect(rec.pauseReason, PauseReason.auto);
  });

  test('en pause, plus aucun point n est enregistré', () {
    final rec = _recorder()..start();
    _feed(rec, speedKmh: 0, vibration: 0.01, seconds: 31);
    final countAtPause = rec.pointCount;
    _feed(rec, speedKmh: 0, vibration: 0.01, seconds: 60, from: 31);
    expect(rec.pointCount, countAtPause);
  });

  test('franchissement lent moteur tournant : pas de pause', () {
    // Sous 2 km/h pendant 2 minutes, mais le téléphone vibre.
    final rec = _recorder()..start();
    _feed(rec, speedKmh: 1.5, vibration: 0.9, seconds: 120);
    expect(rec.state, RecorderState.recording);
    expect(rec.pointCount, 120);
  });

  test('la reprise après pause automatique ouvre un nouveau segment', () {
    final rec = _recorder()..start();
    _feed(rec, speedKmh: 0, vibration: 0.01, seconds: 31);
    expect(rec.state, RecorderState.paused);

    rec.onSample(gps: _gps(12, 200), vibrationLevel: 1.5);
    expect(rec.state, RecorderState.recording);
    expect(rec.segment, 1);
    expect(rec.takePending().last.segment, 1);
  });

  test('sous le seuil de reprise, la pause automatique tient', () {
    final rec = _recorder()..start();
    _feed(rec, speedKmh: 0, vibration: 0.01, seconds: 31);
    rec.onSample(gps: _gps(2.5, 200), vibrationLevel: 1.5); // seuil de reprise = 3
    expect(rec.state, RecorderState.paused);
  });

  test('pause automatique désactivée : aucune pause même immobile', () {
    final rec = _recorder(autoPause: false)..start();
    _feed(rec, speedKmh: 0, vibration: 0.01, seconds: 300);
    expect(rec.state, RecorderState.recording);
  });

  test('une pause manuelle ne se termine pas toute seule', () {
    final rec = _recorder()..start();
    _feed(rec, speedKmh: 40, vibration: 2, seconds: 5);
    rec.pauseManually();
    expect(rec.pauseReason, PauseReason.manual);

    // Le pilote marche à 4 km/h vers le restaurant : rien ne doit reprendre.
    _feed(rec, speedKmh: 4, vibration: 1.2, seconds: 60, from: 5);
    expect(rec.state, RecorderState.paused);
  });

  test('la reprise manuelle ouvre aussi un nouveau segment', () {
    final rec = _recorder()..start();
    _feed(rec, speedKmh: 40, vibration: 2, seconds: 5);
    rec.pauseManually();
    rec.resumeManually();
    expect(rec.state, RecorderState.recording);
    expect(rec.segment, 1);
  });

  test('le seuil de pause configurable à 5 km/h est respecté', () {
    final rec = _recorder(pauseSpeed: 5)..start();
    _feed(rec, speedKmh: 4, vibration: 0.01, seconds: 31);
    expect(rec.state, RecorderState.paused);
  });

  test('takePending vide le tampon', () {
    final rec = _recorder()..start();
    _feed(rec, speedKmh: 40, vibration: 2, seconds: 4);
    expect(rec.takePending().length, 4);
    expect(rec.takePending(), isEmpty);
    expect(rec.pointCount, 4); // le compteur total ne se vide pas
  });

  test('stop ramène à l état initial', () {
    final rec = _recorder()..start();
    _feed(rec, speedKmh: 40, vibration: 2, seconds: 4);
    rec.stop();
    expect(rec.state, RecorderState.idle);
  });

  // ── Perte de signal (forêt, tunnel, gorge) ────────────────
  // Sans cette coupure, le point d'avant et celui d'après le trou seraient
  // reliés d'un trait à travers la montagne.

  test('une perte de signal prolongée ouvre un nouveau segment', () {
    final rec = _recorder();
    rec.start();
    _feed(rec, speedKmh: 40, vibration: 0.5, seconds: 5);
    expect(rec.segment, 0);

    // Retour du signal 3 minutes plus tard.
    rec.onSample(gps: _gps(40, 185), vibrationLevel: 0.5);

    expect(rec.segment, 1);
    expect(rec.gapSegments, contains(1));
  });

  test('une coupure plus courte que le seuil ne coupe pas la trace', () {
    final rec = _recorder();
    rec.start();
    _feed(rec, speedKmh: 40, vibration: 0.5, seconds: 5);

    rec.onSample(gps: _gps(40, 60), vibrationLevel: 0.5);

    expect(rec.segment, 0);
    expect(rec.gapSegments, isEmpty);
  });

  test('la reprise après pause n est pas comptée comme une perte de signal', () {
    final rec = _recorder();
    rec.start();
    _feed(rec, speedKmh: 40, vibration: 0.5, seconds: 5);
    rec.pauseManually();

    // Le pilote déjeune une heure, puis repart.
    rec.resumeManually();
    rec.onSample(gps: _gps(40, 3600), vibrationLevel: 0.5);

    expect(rec.segment, 1, reason: 'la reprise ouvre un segment, une seule fois');
    expect(rec.gapSegments, isEmpty,
        reason: 'ce trou est une pause voulue, pas une perte de signal');
  });

  test('le seuil de coupure est configurable', () {
    final rec = RideRecorder(
      rideId: 'r1',
      config: const RecorderConfig(signalGapDelay: Duration(seconds: 30)),
    );
    rec.start();
    _feed(rec, speedKmh: 40, vibration: 0.5, seconds: 3);

    rec.onSample(gps: _gps(40, 50), vibrationLevel: 0.5);

    expect(rec.segment, 1);
  });
}
