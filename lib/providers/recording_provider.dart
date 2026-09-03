import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
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
  // Statistiques tenues à jour point par point. Les recalculer sur toute la
  // liste à chaque rafraîchissement coûtait ~15 ms pour 60 000 points sur un
  // ordinateur de bureau — bien plus sur un téléphone posé au soleil sur un
  // guidon, et à chaque point GPS. On accumule donc au fil de l'eau.
  RidePoint? _lastPoint;
  double _distanceMeters = 0;
  int _movingSeconds = 0;
  double _maxSpeedKmh = 0;
  DateTime? _firstTs;
  DateTime? _lastTs;
  int _statsPointCount = 0;

  static const _calc = Distance();

  // Mêmes règles que RideStats.fromPoints : distance et temps de roulage ne
  // s'accumulent qu'à l'intérieur d'un segment, la vitesse maximale sur tous
  // les points. Deux segments ne sont jamais reliés.
  void _accumulate(RidePoint p) {
    _statsPointCount++;
    _firstTs ??= p.timestamp;
    _lastTs = p.timestamp;
    if (p.speedKmh > _maxSpeedKmh) _maxSpeedKmh = p.speedKmh;

    final prev = _lastPoint;
    if (prev != null && prev.segment == p.segment) {
      _distanceMeters += _calc(prev.position, p.position);
      _movingSeconds += p.timestamp.difference(prev.timestamp).inSeconds;
    }
    _lastPoint = p;
  }

  void _resetStats() {
    _lastPoint = null;
    _distanceMeters = 0;
    _movingSeconds = 0;
    _maxSpeedKmh = 0;
    _firstTs = null;
    _lastTs = null;
    _statsPointCount = 0;
  }

  RideStats get liveStats {
    if (_statsPointCount < 2) return RideStats.empty;
    return RideStats(
      distanceMeters: _distanceMeters,
      totalTime:      _lastTs!.difference(_firstTs!),
      movingTime:     Duration(seconds: _movingSeconds),
      maxSpeedKmh:    _maxSpeedKmh,
      avgSpeedKmh:    _movingSeconds == 0
          ? 0.0
          : (_distanceMeters / _movingSeconds) * 3.6,
    );
  }

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
    _unsaved.clear();
    _resetStats();
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
  // Les points quittent le tampon de l'enregistreur AVANT d'atteindre la base.
  // Si l'écriture échoue (disque plein, base verrouillée), on les garde ici
  // pour le prochain essai : sans ce filet ils n'existeraient plus qu'en
  // mémoire et la trace serait vide à l'arrivée, sans que rien ne prévienne.
  final List<RidePoint> _unsaved = [];

  // Les écritures sont mises à la queue leu leu. La minuterie et le seuil de
  // points peuvent déclencher deux flush qui se chevauchent ; sans cette file,
  // le second retirerait de _unsaved des points que le premier n'a pas encore
  // écrits. Chaque appelant attend son propre tour — stopRide en dépend pour
  // ne pas clôturer la sortie avant que les derniers points soient en base.
  Future<void> _queue = Future.value();

  bool get hasUnsavedPoints => _unsaved.isNotEmpty;

  Future<void> flush() {
    final rec = _recorder;
    if (rec == null) return Future.value();

    // Partie synchrone : les statistiques du bandeau suivent les points dès
    // qu'ils sont relevés, sans attendre l'écriture en base.
    final fresh = rec.takePending();
    if (fresh.isNotEmpty) {
      _written.addAll(fresh);
      _unsaved.addAll(fresh);
      for (final p in fresh) {
        _accumulate(p);
      }
    }
    if (_unsaved.isEmpty) return Future.value();

    _queue = _queue.then((_) => _writePending());
    return _queue;
  }

  Future<void> _writePending() async {
    if (_unsaved.isEmpty) return;
    final batch = List<RidePoint>.from(_unsaved);
    try {
      await _repo.appendPoints(batch);
    } on Exception {
      // Rien n'est retiré : le prochain flush réessaiera avec ces points.
      notifyListeners();
      return;
    }
    // Seuls les points écrits quittent la file ; ceux arrivés pendant
    // l'écriture restent en queue pour le tour suivant.
    _unsaved.removeRange(0, batch.length);
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
      stats:   liveStats,
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
