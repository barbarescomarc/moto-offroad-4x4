// test/services/location_service_test.dart
//
// Le service GPS ne doit pas se contenter de garder la dernière position :
// il doit la publier. Sans signal observable, l'affichage n'apprend jamais
// qu'une position plus récente existe.
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:moto_offroad/services/location_service.dart';

GpsSnapshot _releve(double lat) => GpsSnapshot(
      position: LatLng(lat, 1.44),
      accuracyMeters: 5,
      altitudeMeters: 300,
      speedKmh: 40,
      headingDeg: 90,
      timestamp: DateTime(2026, 9, 15, 12),
    );

void main() {
  test('une nouvelle position est publiee sur positionListenable', () {
    final service = LocationService();
    var notifications = 0;
    void ecouter() => notifications++;
    service.positionListenable.addListener(ecouter);
    addTearDown(() => service.positionListenable.removeListener(ecouter));

    service.debugSetLastSnapshot(_releve(43.61));

    expect(notifications, 1);
    expect(service.positionListenable.value?.position.latitude, 43.61);
    expect(service.lastSnapshot?.position.latitude, 43.61);
  });
}
