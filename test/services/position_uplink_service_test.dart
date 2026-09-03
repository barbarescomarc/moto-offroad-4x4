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

  test('overlapping ticks do not double-send while a send is in flight', () async {
    final completer = Completer<bool>();
    var callCount = 0;
    Future<bool> slowSender({
      required String sessionId, required String deviceKey, required String memberId,
      required List<GpsSnapshot> points,
    }) async {
      callCount++;
      if (callCount == 1) return completer.future; // le premier appel reste bloqué
      return true;
    }
    final controller = StreamController<GpsSnapshot>();
    final service = PositionUplinkService(sendPositions: slowSender);
    service.start(
      positions: controller.stream,
      sessionId: 's1', deviceKey: 'dk', memberId: 'm1',
      interval: const Duration(milliseconds: 20),
    );

    controller.add(_snap());
    await Future.delayed(const Duration(milliseconds: 30)); // le premier tick démarre et reste en attente
    controller.add(_snap());
    await Future.delayed(const Duration(milliseconds: 80)); // plusieurs ticks auraient dû se produire sans le verrou

    expect(callCount, 1); // aucun second envoi tant que le premier n'est pas résolu

    completer.complete(true);
    await Future.delayed(const Duration(milliseconds: 30));

    service.stop();
    await controller.close();
  });

  test('a send still in flight when stop() is called does not corrupt a later restart', () async {
    final completer = Completer<bool>();
    var firstCall = true;
    Future<bool> sender({
      required String sessionId, required String deviceKey, required String memberId,
      required List<GpsSnapshot> points,
    }) async {
      if (firstCall) {
        firstCall = false;
        return completer.future;
      }
      return true;
    }
    final controllerA = StreamController<GpsSnapshot>();
    final service = PositionUplinkService(sendPositions: sender);
    service.start(
      positions: controllerA.stream,
      sessionId: 's1', deviceKey: 'dk', memberId: 'm1',
      interval: const Duration(milliseconds: 20),
    );
    controllerA.add(_snap());
    await Future.delayed(const Duration(milliseconds: 30));

    service.stop(); // le premier envoi est toujours en attente

    final controllerB = StreamController<GpsSnapshot>();
    service.start(
      positions: controllerB.stream,
      sessionId: 's2', deviceKey: 'dk2', memberId: 'm2',
      interval: const Duration(milliseconds: 20),
    );
    controllerB.add(_snap());
    await Future.delayed(const Duration(milliseconds: 10));

    completer.complete(true); // le premier envoi se résout enfin, après le redémarrage — ne doit rien casser

    await Future.delayed(const Duration(milliseconds: 40));

    service.stop();
    await controllerA.close();
    await controllerB.close();
  });
}
