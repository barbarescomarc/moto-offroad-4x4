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

  void start({
    required Stream<GpsSnapshot> positions,
    required String sessionId,
    required String deviceKey,
    required String memberId,
    required Duration interval,
  }) {
    stop();
    _sub = positions.listen((snap) {
      _buffer.add(snap);
      if (_buffer.length > _maxBuffered) _buffer.removeAt(0);
    });
    _timer = Timer.periodic(interval, (_) async {
      if (_buffer.isEmpty) return;
      final batch = List<GpsSnapshot>.from(_buffer);
      final ok = await _send(
        sessionId: sessionId, deviceKey: deviceKey, memberId: memberId, points: batch,
      );
      if (ok) _buffer.removeRange(0, batch.length);
    });
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    _timer?.cancel();
    _timer = null;
    _buffer.clear();
  }
}
