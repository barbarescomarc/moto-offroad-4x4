import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:moto_offroad/providers/quick_reply_provider.dart';
import 'package:moto_offroad/services/auto_reply_policy.dart';
import 'package:moto_offroad/services/auto_reply_service.dart';
import 'package:moto_offroad/services/call_bridge.dart';
import 'package:moto_offroad/services/location_service.dart';

// Double du pont : enregistre ce qui aurait été envoyé au natif.
class FakeCallBridge implements CallBridge {
  final _controller = StreamController<CallEvent>.broadcast();
  final sentSms = <List<String>>[];
  final banners = <List<String>>[];
  bool bannerHidden = false;
  bool failSends = false;

  @override
  Stream<CallEvent> get events => _controller.stream;

  void emit(CallEvent e) => _controller.add(e);

  @override
  Future<bool> sendSms(String phone, String text) async {
    sentSms.add([phone, text]);
    return !failSends;
  }

  @override
  Future<void> showBanner(List<String> labels, String number) async =>
      banners.add(labels);

  @override
  Future<void> hideBanner() async => bannerHidden = true;

  @override
  Future<bool> hasPermissions() async => true;

  @override
  Future<bool> requestPermissions() async => true;
}

GpsSnapshot _snapshot() => GpsSnapshot(
  position:       const LatLng(45.1, 6.6),
  accuracyMeters: 8, altitudeMeters: 1840, speedKmh: 0, headingDeg: 0,
  timestamp:      DateTime.utc(2026, 9, 3),
);

void main() {
  late FakeCallBridge bridge;

  AutoReplyService build({
    bool riding = true,
    bool enabled = true,
    List<String> trustedPhones = const ['+33612345678'],
    void Function(String message)? onSendFailed,
  }) {
    bridge = FakeCallBridge();
    return AutoReplyService(
      bridge: bridge,
      policyBuilder: () => AutoReplyPolicy(
        enabled: enabled, allCallers: false, riding: riding,
        trustedPhones: trustedPhones,
      ),
      messageBuilder: () => 'Je roule',
      attachPositionBuilder: () => true,
      repliesBuilder: () => QuickReplyProvider.defaults,
      positionProvider: () async => _snapshot(),
      onSendFailed: onSendFailed,
    );
  }

  test('un appel d un contact de confiance déclenche le SMS automatique', () async {
    final service = build();
    service.start();
    bridge.emit(const CallEvent(type: CallEventType.incoming, number: '0612345678'));
    await Future<void>.delayed(Duration.zero);

    expect(bridge.sentSms.length, 1);
    expect(bridge.sentSms.single[0], '0612345678');
    expect(bridge.sentSms.single[1], startsWith('Je roule'));
    expect(bridge.sentSms.single[1], contains('maps.google.com'));
  });

  test('un appel refusé par la politique n envoie rien', () async {
    final service = build(riding: false);
    service.start();
    bridge.emit(const CallEvent(type: CallEventType.incoming, number: '0612345678'));
    await Future<void>.delayed(Duration.zero);

    expect(bridge.sentSms, isEmpty);
    expect(bridge.banners, isEmpty);
  });

  test('un appel accepté affiche aussi le bandeau de réponses rapides', () async {
    final service = build();
    service.start();
    bridge.emit(const CallEvent(type: CallEventType.incoming, number: '0612345678'));
    await Future<void>.delayed(Duration.zero);

    expect(bridge.banners.single.length, 3);
    expect(bridge.banners.single.first, 'Je roule, je ne peux pas répondre');
  });

  test('une pression sur une réponse rapide envoie ce texte-là', () async {
    final service = build();
    service.start();
    bridge.emit(const CallEvent(
      type: CallEventType.quickReply, number: '0612345678', index: 2));
    await Future<void>.delayed(Duration.zero);

    expect(bridge.sentSms.single[1], "Tout va bien, j'arrive");
    expect(bridge.sentSms.single[1], isNot(contains('maps.google.com')));
  });

  test(
    'une pression sur une réponse rapide envoie le SMS même pour un numéro '
    'non approuvé, alors qu un appel entrant du même numéro ne déclenche rien',
    () async {
      final service = build(trustedPhones: const []);
      service.start();

      bridge.emit(const CallEvent(
        type: CallEventType.quickReply, number: '0699999999', index: 0));
      await Future<void>.delayed(Duration.zero);
      expect(bridge.sentSms.length, 1);
      expect(bridge.sentSms.single[0], '0699999999');

      bridge.emit(const CallEvent(
        type: CallEventType.incoming, number: '0699999999'));
      await Future<void>.delayed(Duration.zero);
      expect(bridge.sentSms.length, 1); // toujours un seul envoi
    },
  );

  test(
    'une pression sur une réponse rapide envoie le SMS même si le pilote ne '
    'roule pas, alors qu un appel entrant dans la même situation ne déclenche rien',
    () async {
      final service = build(riding: false);
      service.start();

      bridge.emit(const CallEvent(
        type: CallEventType.quickReply, number: '0612345678', index: 0));
      await Future<void>.delayed(Duration.zero);
      expect(bridge.sentSms.length, 1);
      expect(bridge.sentSms.single[0], '0612345678');

      bridge.emit(const CallEvent(
        type: CallEventType.incoming, number: '0612345678'));
      await Future<void>.delayed(Duration.zero);
      expect(bridge.sentSms.length, 1); // toujours un seul envoi
    },
  );

  test('un échec d envoi sur un appel entrant est signalé, pas avalé', () async {
    final failures = <String>[];
    final service = build(onSendFailed: failures.add);
    bridge.failSends = true;
    service.start();
    bridge.emit(const CallEvent(type: CallEventType.incoming, number: '0612345678'));
    await Future<void>.delayed(Duration.zero);

    expect(bridge.sentSms.length, 1); // la tentative a bien eu lieu
    expect(failures.length, 1);
    expect(failures.single, contains('0612345678'));
  });

  test('un échec d envoi sur une réponse rapide est signalé, pas avalé', () async {
    final failures = <String>[];
    final service = build(onSendFailed: failures.add);
    bridge.failSends = true;
    service.start();
    bridge.emit(const CallEvent(
      type: CallEventType.quickReply, number: '0612345678', index: 0));
    await Future<void>.delayed(Duration.zero);

    expect(bridge.sentSms.length, 1);
    expect(failures.length, 1);
    expect(failures.single, contains('0612345678'));
  });

  test('un envoi réussi ne déclenche aucun signalement d échec', () async {
    final failures = <String>[];
    final service = build(onSendFailed: failures.add);
    service.start();
    bridge.emit(const CallEvent(type: CallEventType.incoming, number: '0612345678'));
    await Future<void>.delayed(Duration.zero);

    expect(failures, isEmpty);
  });

  test('après stop, plus rien n est envoyé', () async {
    final service = build();
    service.start();
    service.stop();
    bridge.emit(const CallEvent(type: CallEventType.incoming, number: '0612345678'));
    await Future<void>.delayed(Duration.zero);

    expect(bridge.sentSms, isEmpty);
  });
}
