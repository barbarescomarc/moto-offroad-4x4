import 'dart:async';
import 'location_service.dart';

typedef SendPositionsFn = Future<bool> Function({
  required String sessionId,
  required String deviceKey,
  required String memberId,
  required List<GpsSnapshot> points,
});

class PositionUplinkService {
  PositionUplinkService({required SendPositionsFn sendPositions}) : _send = sendPositions;

  static const int _maxBuffered = 200;

  final SendPositionsFn _send;
  final List<GpsSnapshot> _buffer = [];
  StreamSubscription<GpsSnapshot>? _sub;
  Timer? _timer;
  bool _sending = false;
  int _generation = 0;

  void start({
    required Stream<GpsSnapshot> positions,
    required String sessionId,
    required String deviceKey,
    required String memberId,
    required Duration interval,
  }) {
    stop();
    final generation = _generation;
    _sub = positions.listen((snap) {
      _buffer.add(snap);
      if (_buffer.length > _maxBuffered) _buffer.removeAt(0);
    });
    _timer = Timer.periodic(interval, (_) async {
      if (_sending || _buffer.isEmpty) return;
      _sending = true;
      final batch = List<GpsSnapshot>.from(_buffer);
      var ok = false;
      try {
        ok = await _send(
          sessionId: sessionId, deviceKey: deviceKey, memberId: memberId, points: batch,
        );
      } catch (_) {
        ok = false;
      }
      if (generation != _generation) return; // stop()/restart happened pendant l'envoi
      if (ok) _buffer.removeRange(0, batch.length);
      _sending = false;
    });
  }

  void stop() {
    _generation++; // invalide toute poursuite d'envoi encore en vol
    _sub?.cancel();
    _sub = null;
    _timer?.cancel();
    _timer = null;
    _sending = false;
    _buffer.clear();
  }
}
