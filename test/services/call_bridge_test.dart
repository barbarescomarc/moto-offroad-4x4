import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moto_offroad/services/call_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('app.motooffroad/call');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'sendSms') return true;
      if (call.method == 'hasPermissions') return true;
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('sendSms transmet le numéro et le texte au natif', () async {
    final ok = await CallBridge().sendSms('+33612345678', 'Je roule');
    expect(ok, isTrue);
    expect(calls.single.method, 'sendSms');
    expect(calls.single.arguments['phone'], '+33612345678');
    expect(calls.single.arguments['text'], 'Je roule');
  });

  test('showBanner transmet au plus trois libellés', () async {
    await CallBridge().showBanner(['a', 'b', 'c', 'd'], '0612345678');
    expect(calls.single.method, 'showBanner');
    expect((calls.single.arguments['labels'] as List).length, 3);
    expect(calls.single.arguments['number'], '0612345678');
  });

  test('hasPermissions interroge le natif', () async {
    expect(await CallBridge().hasPermissions(), isTrue);
    expect(calls.single.method, 'hasPermissions');
  });

  test('un echec natif sur sendSms renvoie false au lieu de lever', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'SMS_FAILED');
    });
    expect(await CallBridge().sendSms('0612345678', 'Je roule'), isFalse);
  });

  group('events', () {
    const eventChannel = MethodChannel('app.motooffroad/call_events');
    const codec = StandardMethodCodec();

    setUp(() {
      // 'listen' / 'cancel' sont les appels internes émis par
      // receiveBroadcastStream() : on les accepte sans rien faire.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(eventChannel, (call) async => null);
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(eventChannel, null);
    });

    Future<void> pushEvent(Map<String, dynamic> data) {
      final envelope = codec.encodeSuccessEnvelope(data);
      return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage('app.motooffroad/call_events', envelope, (_) {});
    }

    test(
        'quick_reply devient CallEventType.quickReply avec son index, '
        'incoming reste incoming avec index -1, un type inconnu retombe '
        'sur incoming', () async {
      final received = <CallEvent>[];
      final subscription = CallBridge().events.listen(received.add);
      addTearDown(subscription.cancel);

      // Laisse receiveBroadcastStream() enregistrer son handler (l'appel
      // 'listen' interne est asynchrone) avant de pousser des événements.
      await Future<void>.delayed(Duration.zero);

      await pushEvent({'type': 'quick_reply', 'number': '0612345678', 'index': 2});
      await pushEvent({'type': 'incoming', 'number': '0687654321'});
      await pushEvent({'type': 'bogus', 'number': '0600000000'});
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(3));

      expect(received[0].type, CallEventType.quickReply);
      expect(received[0].number, '0612345678');
      expect(received[0].index, 2);

      expect(received[1].type, CallEventType.incoming);
      expect(received[1].number, '0687654321');
      expect(received[1].index, -1);

      expect(received[2].type, CallEventType.incoming);
    });
  });
}
