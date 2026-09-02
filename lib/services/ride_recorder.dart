import '../models/ride.dart';
import 'location_service.dart';
import 'vibration_calibration.dart';

// ── États et causes de pause ─────────────────────────────────
enum RecorderState { idle, recording, paused }
enum PauseReason { none, auto, manual }

// ── Réglages de l'enregistreur ───────────────────────────────
class RecorderConfig {
  final double pauseSpeedKmh;       // 2 ou 5 selon le réglage du pilote
  final double vibrationThreshold;  // issu de la calibration
  final Duration pauseDelay;
  final bool autoPauseEnabled;

  const RecorderConfig({
    this.pauseSpeedKmh      = 2,
    this.vibrationThreshold = VibrationCalibration.defaultThreshold,
    this.pauseDelay         = const Duration(seconds: 30),
    this.autoPauseEnabled   = true,
  });

  // Hystérésis : sans écart entre pause et reprise, une vitesse oscillant
  // autour du seuil ferait alterner les deux états en boucle.
  double get resumeSpeedKmh => pauseSpeedKmh + 1;
}

// ── Machine à états — ne lit ni n'écrit rien ─────────────────
class RideRecorder {
  RideRecorder({required this.rideId, required this.config});

  final String rideId;
  final RecorderConfig config;

  RecorderState _state = RecorderState.idle;
  PauseReason _pauseReason = PauseReason.none;
  int _segment = 0;
  int _seq = 0;
  DateTime? _stillSince;
  final List<RidePoint> _pending = [];

  RecorderState get state => _state;
  PauseReason get pauseReason => _pauseReason;
  int get segment => _segment;
  int get pointCount => _seq;

  // ── Cycle de vie ─────────────────────────────────────────
  void start() {
    _state = RecorderState.recording;
    _pauseReason = PauseReason.none;
    _stillSince = null;
  }

  void stop() {
    _state = RecorderState.idle;
    _pauseReason = PauseReason.none;
    _stillSince = null;
  }

  void pauseManually() {
    if (_state != RecorderState.recording) return;
    _state = RecorderState.paused;
    _pauseReason = PauseReason.manual;
    _stillSince = null;
  }

  void resumeManually() {
    if (_state != RecorderState.paused) return;
    _resume();
  }

  // ── Réception d'un échantillon ───────────────────────────
  void onSample({required GpsSnapshot gps, required double vibrationLevel}) {
    switch (_state) {
      case RecorderState.idle:
        return;

      case RecorderState.paused:
        // Seule une pause automatique se termine d'elle-même. Une pause
        // manuelle attend une reprise manuelle : sinon marcher jusqu'au
        // restaurant relancerait l'enregistrement.
        if (_pauseReason == PauseReason.auto &&
            gps.speedKmh > config.resumeSpeedKmh) {
          _resume();
          _append(gps);
        }
        return;

      case RecorderState.recording:
        final isStill = gps.speedKmh < config.pauseSpeedKmh &&
            vibrationLevel < config.vibrationThreshold;

        if (config.autoPauseEnabled && isStill) {
          _stillSince ??= gps.timestamp;
          if (gps.timestamp.difference(_stillSince!) >= config.pauseDelay) {
            _state = RecorderState.paused;
            _pauseReason = PauseReason.auto;
            _stillSince = null;
            return;
          }
        } else {
          _stillSince = null;
        }
        _append(gps);
    }
  }

  // ── Tampon d'écriture ────────────────────────────────────
  List<RidePoint> takePending() {
    final batch = List<RidePoint>.from(_pending);
    _pending.clear();
    return batch;
  }

  // ── Interne ──────────────────────────────────────────────
  void _resume() {
    _segment++;
    _state = RecorderState.recording;
    _pauseReason = PauseReason.none;
    _stillSince = null;
  }

  void _append(GpsSnapshot gps) {
    _pending.add(RidePoint(
      rideId:    rideId,
      seq:       _seq++,
      segment:   _segment,
      lat:       gps.position.latitude,
      lng:       gps.position.longitude,
      altitude:  gps.altitudeMeters,
      speedKmh:  gps.speedKmh,
      timestamp: gps.timestamp,
    ));
  }
}
