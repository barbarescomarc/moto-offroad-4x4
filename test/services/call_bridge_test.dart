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
}
