import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/ride.dart';
import '../services/location_service.dart';
import '../services/ride_recorder.dart';
import '../services/ride_recording_service.dart';
import '../services/ride_repository.dart';
import '../services/vibration_meter.dart';

// ── Provider — orchestration de l'enregistrement ─────────────
class RecordingProvider extends ChangeNotifier {
  RecordingProvider({
    required RideRepository repository,
    RideRecordingService? service,
  })  : _repo = repository,
        _service = service;

  static const Duration _flushInterval = Duration(seconds: 5);
  static const int _flushPointCount = 10;
  static const Duration _reminderAfter = Duration(minutes: 15);
  static const double _reminderSpeedKmh = 10;

  final RideRepository _repo;
  final RideRecordingService? _service;
  final _uuid = const Uuid();
  final _meter = VibrationMeter();

  RideRecorder? _recorder;
  Ride? _currentRide;
  Timer? _flushTimer;
  final List<RidePoint> _written = [];
  DateTime? _slowSince;
  DateTime? _lastSampleAt;
  bool _reminderShown = false;

  RecorderState get state => _recorder?.state ?? RecorderState.idle;
  bool get isRecording => state == RecorderState.recording;
  bool get isPaused    => state == RecorderState.paused;
  PauseReason get pauseReason => _recorder?.pauseReason ?? PauseReason.none;
  Ride? get currentRide => _currentRide;

  // Rappel pour le pilote : « Toujours en balade ? »
  bool get shouldRemindPause => _reminderShown == false && _slowSince != null &&
      (_lastSampleAt ?? DateTime.now()).difference(_slowSince!) >= _reminderAfter;

  void acknowledgeReminder() {
    _reminderShown = true;
    notifyListeners();
  }

  // Statistiques recalculées sur les points déjà écrits : la liste d'une
  // sortie de 4 h reste en mémoire, mais le calcul est linéaire et n'a lieu
  // qu'à l'affichage.
  RideStats get liveStats => RideStats.fromPoints(_written);

  // ── Démarrage ────────────────────────────────────────────
  Future<void> startRide({
    required String name,
    required RecorderConfig config,
  }) async {
    final ride = Ride(
      id:        _uuid.v4(),
      name:      name,
      startedAt: DateTime.now(),
      source:    RideSource.recorded,
      status:    RideStatus.recording,
      stats:     RideStats.empty,
    );
    await _repo.insertRide(ride);

    _currentRide = ride;
    _written.clear();
    _meter.reset();
    _slowSince = null;
    _reminderShown = false;
    _recorder = RideRecorder(rideId: ride.id, config: config)..start();

    await _service?.start(
      title: 'Enregistrement en cours',
      text:  '0,0 km · 00:00',
    );

    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(_flushInterval, (_) => flush());
    notifyListeners();
  }

  // ── Entrées capteurs ─────────────────────────────────────
  void onAccelerometer(double x, double y, double z) {
    _meter.addSample(VibrationMeter.magnitudeOf(x, y, z));
  }

  void onGpsSample(GpsSnapshot gps) {
    final rec = _recorder;
    if (rec == null) return;

    final before = rec.state;
    rec.onSample(gps: gps, vibrationLevel: _meter.level);
    _lastSampleAt = gps.timestamp;

    // Gestion du rappel « Toujours en balade ? »
    if (rec.state == RecorderState.recording) {
      if (gps.speedKmh < _reminderSpeedKmh) {
        _slowSince ??= gps.timestamp;
      } else {
        _slowSince = null;
        _reminderShown = false;
      }
    }

    if (rec.pointCount - _written.length >= _flushPointCount) {
      flush();
    }
    if (rec.state != before) {
      _updateNotification();
    }
    notifyListeners();
  }

  // ── Pause ────────────────────────────────────────────────
  Future<void> togglePause() async {
    final rec = _recorder;
    if (rec == null) return;
    if (rec.state == RecorderState.recording) {
      rec.pauseManually();
    } else if (rec.state == RecorderState.paused) {
      rec.resumeManually();
    }
    await flush();
    await _updateNotification();
    notifyListeners();
  }

  // ── Écriture par lots ────────────────────────────────────
  Future<void> flush() async {
    final rec = _recorder;
    if (rec == null) return;
    final batch = rec.takePending();
    if (batch.isEmpty) return;
    _written.addAll(batch);
    await _repo.appendPoints(batch);
    await _updateNotification();
  }

  // ── Arrêt ────────────────────────────────────────────────
  Future<Ride?> stopRide() async {
    final rec = _recorder;
    final ride = _currentRide;
    if (rec == null || ride == null) return null;

    await flush();
    rec.stop();
    _flushTimer?.cancel();
    _flushTimer = null;

    final finished = ride.copyWith(
      status:  RideStatus.finished,
      endedAt: DateTime.now(),
      stats:   RideStats.fromPoints(_written),
    );
    await _repo.updateRide(finished);
    await _service?.stop();

    _recorder = null;
    _currentRide = null;
    notifyListeners();
    return finished;
  }

  // ── Notification ─────────────────────────────────────────
  Future<void> _updateNotification() async {
    if (_service == null || _recorder == null) return;
    final s = liveStats;
    final d = s.totalTime;
    final duree = '${d.inHours.toString().padLeft(2, '0')}:'
        '${(d.inMinutes % 60).toString().padLeft(2, '0')}';
    final km = s.distanceKm.toStringAsFixed(1).replaceAll('.', ',');
    final etat = isPaused ? ' · en pause' : '';
    await _service?.updateNotification(
      title: 'Enregistrement en cours',
      text:  '$km km · $duree$etat',
    );
  }

  @override
  void dispose() {
    _flushTimer?.cancel();
    // Arrêter le service de notification d'avant-plan si en cours d'enregistrement
    _service?.stop().ignore();
    super.dispose();
  }
}
