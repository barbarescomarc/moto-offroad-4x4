import 'package:flutter_test/flutter_test.dart';
import 'package:moto_offroad/services/alert_channel_unlock.dart';

void main() {
  test('sms gateway and voice call are always locked', () {
    final unlock = AlertChannelUnlock();
    expect(unlock.isUnlocked('sms_gateway'), isFalse);
    expect(unlock.isUnlocked('voice_call'), isFalse);
  });

  test('an unknown channel name is also locked, not an error', () {
    final unlock = AlertChannelUnlock();
    expect(unlock.isUnlocked('anything'), isFalse);
  });
}
