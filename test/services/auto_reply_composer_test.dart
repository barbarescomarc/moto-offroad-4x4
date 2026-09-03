import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:moto_offroad/services/auto_reply_composer.dart';
import 'package:moto_offroad/services/location_service.dart';

GpsSnapshot _snapshot() => GpsSnapshot(
  position:       const LatLng(45.123456, 6.654321),
  accuracyMeters: 8,
  altitudeMeters: 1840,
  speedKmh:       0,
  headingDeg:     0,
  timestamp:      DateTime.utc(2026, 9, 3, 14, 30),
);

void main() {
  test('sans position, le message part seul', () {
    final text = AutoReplyComposer.compose(
      message: 'Je roule', attachPosition: false, snapshot: _snapshot(),
    );
    expect(text, 'Je roule');
  });

  test('avec position, coordonnées et lien Google Maps sont joints', () {
    final text = AutoReplyComposer.compose(
      message: 'Je roule, je suis ici', attachPosition: true, snapshot: _snapshot(),
    );
    expect(text, startsWith('Je roule, je suis ici'));
    expect(text, contains('45.123456'));
    expect(text, contains('https://maps.google.com/?q=45.123456,6.654321'));
  });

  test('position demandée mais GPS indisponible : le message part quand même', () {
    final text = AutoReplyComposer.compose(
      message: 'Je roule, je suis ici', attachPosition: true, snapshot: null,
    );
    expect(text, startsWith('Je roule, je suis ici'));
    expect(text, contains('position indisponible'));
    expect(text, isNot(contains('maps.google.com')));
  });

  test('le message reste sous la limite de 5 SMS concaténés', () {
    final text = AutoReplyComposer.compose(
      message: 'Je roule, je suis ici', attachPosition: true, snapshot: _snapshot(),
    );
    expect(text.length, lessThan(600));
  });
}
