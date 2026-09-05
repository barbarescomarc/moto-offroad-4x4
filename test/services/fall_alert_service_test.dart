import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:moto_offroad/providers/solo_provider.dart';
import 'package:moto_offroad/services/fall_alert_service.dart';
import 'package:moto_offroad/services/location_service.dart';

GpsSnapshot _snap() => GpsSnapshot(
  position: const LatLng(45, 5), accuracyMeters: 5, altitudeMeters: 100,
  speedKmh: 0, headingDeg: 0, timestamp: DateTime.now(),
);

void main() {
  test('sends an SMS to every trusted contact when the phone channel is enabled', () async {
    final sentSms = <String>[];
    final service = FallAlertService(
      sendSms: (phone, text) async { sentSms.add(phone); return true; },
      sendServerAlert: ({required kind}) async => true,
      phoneChannelEnabled: () => true,
      serverChannelEnabled: () => false,
      trustedContacts: () => [
        TrustedContact(id: '1', name: 'Claire', phone: '0600000000', email: 'c@x.test', relation: 'Sœur'),
        TrustedContact(id: '2', name: 'Jean', phone: '0600000001', email: 'j@x.test', relation: 'Ami'),
      ],
      positionProvider: () async => _snap(),
    );

    await service.sendFallAlert(kind: 'fall');

    expect(sentSms, ['0600000000', '0600000001']);
  });

  test('calls the server alert when the server channel is enabled', () async {
    var serverCalled = false;
    String? capturedKind;
    final service = FallAlertService(
      sendSms: (_, __) async => true,
      sendServerAlert: ({required kind}) async { serverCalled = true; capturedKind = kind; return true; },
      phoneChannelEnabled: () => false,
      serverChannelEnabled: () => true,
      trustedContacts: () => [],
      positionProvider: () async => _snap(),
    );

    await service.sendFallAlert(kind: 'sos');

    expect(serverCalled, isTrue);
    expect(capturedKind, 'sos');
  });

  test('neither channel fires when both are disabled', () async {
    var smsCalled = false;
    var serverCalled = false;
    final service = FallAlertService(
      sendSms: (_, __) async { smsCalled = true; return true; },
      sendServerAlert: ({required kind}) async { serverCalled = true; return true; },
      phoneChannelEnabled: () => false,
      serverChannelEnabled: () => false,
      trustedContacts: () => [
        TrustedContact(id: '1', name: 'Claire', phone: '0600000000', email: 'c@x.test', relation: 'Sœur'),
      ],
      positionProvider: () async => _snap(),
    );

    await service.sendFallAlert(kind: 'fall');

    expect(smsCalled, isFalse);
    expect(serverCalled, isFalse);
  });

  test('the SMS text includes the position link', () async {
    String? capturedText;
    final service = FallAlertService(
      sendSms: (phone, text) async { capturedText = text; return true; },
      sendServerAlert: ({required kind}) async => true,
      phoneChannelEnabled: () => true,
      serverChannelEnabled: () => false,
      trustedContacts: () => [
        TrustedContact(id: '1', name: 'Claire', phone: '0600000000', email: 'c@x.test', relation: 'Sœur'),
      ],
      positionProvider: () async => _snap(),
    );

    await service.sendFallAlert(kind: 'fall');

    expect(capturedText, contains('maps.google.com'));
  });

  test('a missing position still sends the SMS, without a broken link', () async {
    String? capturedText;
    final service = FallAlertService(
      sendSms: (phone, text) async { capturedText = text; return true; },
      sendServerAlert: ({required kind}) async => true,
      phoneChannelEnabled: () => true,
      serverChannelEnabled: () => false,
      trustedContacts: () => [
        TrustedContact(id: '1', name: 'Claire', phone: '0600000000', email: 'c@x.test', relation: 'Sœur'),
      ],
      positionProvider: () async => null,
    );

    await service.sendFallAlert(kind: 'fall');

    expect(capturedText, isNotNull);
    expect(capturedText, isNot(contains('maps.google.com')));
  });

  test('a failed SMS send is not counted as a notified contact', () async {
    final service = FallAlertService(
      sendSms: (phone, text) async => phone == '0600000000' ? false : true,
      sendServerAlert: ({required kind}) async => true,
      phoneChannelEnabled: () => true,
      serverChannelEnabled: () => false,
      trustedContacts: () => [
        TrustedContact(id: '1', name: 'Claire', phone: '0600000000', email: 'c@x.test', relation: 'Sœur'),
        TrustedContact(id: '2', name: 'Jean', phone: '0600000001', email: 'j@x.test', relation: 'Ami'),
      ],
      positionProvider: () async => _snap(),
    );

    final result = await service.sendFallAlert(kind: 'fall');

    expect(result.contactsNotified, 1);
  });

  test('phone channel enabled but no trusted contacts notifies zero contacts', () async {
    final service = FallAlertService(
      sendSms: (_, __) async => true,
      sendServerAlert: ({required kind}) async => true,
      phoneChannelEnabled: () => true,
      serverChannelEnabled: () => false,
      trustedContacts: () => [],
      positionProvider: () async => _snap(),
    );

    final result = await service.sendFallAlert(kind: 'fall');

    expect(result.contactsNotified, 0);
  });

  test('server channel enabled but the send fails reports serverNotified false', () async {
    final service = FallAlertService(
      sendSms: (_, __) async => true,
      sendServerAlert: ({required kind}) async => false,
      phoneChannelEnabled: () => false,
      serverChannelEnabled: () => true,
      trustedContacts: () => [],
      positionProvider: () async => _snap(),
    );

    final result = await service.sendFallAlert(kind: 'fall');

    expect(result.serverNotified, isFalse);
  });

  test('server channel disabled means the server alert is never attempted', () async {
    final service = FallAlertService(
      sendSms: (_, __) async => true,
      sendServerAlert: ({required kind}) async => true,
      phoneChannelEnabled: () => false,
      serverChannelEnabled: () => false,
      trustedContacts: () => [],
      positionProvider: () async => _snap(),
    );

    final result = await service.sendFallAlert(kind: 'fall');

    expect(result.serverNotified, isFalse);
  });
}
