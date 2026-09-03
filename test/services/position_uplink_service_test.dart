import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:moto_offroad/services/location_service.dart';
import 'package:moto_offroad/services/position_uplink_service.dart';

GpsSnapshot _snap() => GpsSnapshot(
  position: const LatLng(45, 5), accuracyMeters: 5, altitudeMeters: 100,
  speedKmh: 20, headingDeg: 0, timestamp: DateTime.now(),
);

class _FakeSender {
  final List<List<GpsSnapshot>> calls = [];
  bool succeed = true;
  Future<bool> call({
    required String sessionId, required String deviceKey, required String memberId,
    required List<GpsSnapshot> points,
  }) async {
    calls.add(points);
    return succeed;
  }
}

void main() {
  test('buffered points are sent and cleared on the next tick when successful', () async {
    final sender = _FakeSender();
    final controller = StreamController<GpsSnapshot>();
    final service = PositionUplinkService(sendPositions: sender.call);

    service.start(
      positions: controller.stream,
      sessionId: 's1', deviceKey: 'dk', memberId: 'm1',
      interval: const Duration(milliseconds: 20),
    );
    controller.add(_snap());
    controller.add(_snap());
    await Future.delayed(const Duration(milliseconds: 60));

    expect(sender.calls, isNotEmpty);
    expect(sender.calls.first.length, 2);

    service.stop();
    await controller.close();
  });

  test('a failed send keeps the points for the next tick', () async {
    final sender = _FakeSender()..succeed = false;
    final controller = StreamController<GpsSnapshot>();
    final service = PositionUplinkService(sendPositions: sender.call);

    service.start(
      positions: controller.stream,
      sessionId: 's1', deviceKey: 'dk', memberId: 'm1',
      interval: const Duration(milliseconds: 20),
    );
    controller.add(_snap());
    await Future.delayed(const Duration(milliseconds: 70));

    expect(sender.calls.length, greaterThan(1));
    // le point du premier échec réapparaît dans un appel suivant
    expect(sender.calls.last, isNotEmpty);

    service.stop();
    await controller.close();
  });

  test('stop() cancels the timer and the subscription', () async {
    final sender = _FakeSender();
    final controller = StreamController<GpsSnapshot>();
    final service = PositionUplinkService(sendPositions: sender.call);

    service.start(
      positions: controller.stream,
      sessionId: 's1', deviceKey: 'dk', memberId: 'm1',
      interval: const Duration(milliseconds: 20),
    );
    service.stop();
    final callsAtStop = sender.calls.length;
    controller.add(_snap());
    await Future.delayed(const Duration(milliseconds: 60));

    expect(sender.calls.length, callsAtStop);
    await controller.close();
  });

  test('an empty buffer sends nothing', () async {
    final sender = _FakeSender();
    final controller = StreamController<GpsSnapshot>();
    final service = PositionUplinkService(sendPositions: sender.call);

    service.start(
      positions: controller.stream,
      sessionId: 's1', deviceKey: 'dk', memberId: 'm1',
      interval: const Duration(milliseconds: 20),
    );
    await Future.delayed(const Duration(milliseconds: 50));

    expect(sender.calls, isEmpty);
    service.stop();
    await controller.close();
  });
}
