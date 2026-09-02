import 'package:flutter_test/flutter_test.dart';
import 'package:moto_offroad/models/ride.dart';
import 'package:moto_offroad/services/gpx_service.dart';
import 'package:moto_offroad/services/ride_export_service.dart';

Ride _ride() => Ride(
  id:        'r1',
  name:      'Sortie du Ventoux',
  startedAt: DateTime.utc(2026, 9, 2, 8, 0),
  endedAt:   DateTime.utc(2026, 9, 2, 12, 0),
  source:    RideSource.recorded,
  status:    RideStatus.finished,
  stats:     RideStats.empty,
);

List<RidePoint> _points() => [
  RidePoint(rideId: 'r1', seq: 0, segment: 0, lat: 44.1, lng: 5.2,
      altitude: 800, speedKmh: 30, timestamp: DateTime.utc(2026, 9, 2, 8, 0)),
  RidePoint(rideId: 'r1', seq: 1, segment: 0, lat: 44.2, lng: 5.3,
      altitude: 1200, speedKmh: 25, timestamp: DateTime.utc(2026, 9, 2, 9, 0)),
];

void main() {
  test('la conversion garde le nom, les points et les altitudes', () {
    final trace = RideExportService().toTraceModel(_ride(), _points());
    expect(trace.name, 'Sortie du Ventoux');
    expect(trace.points.length, 2);
    expect(trace.points.first.elevation, 800);
    expect(trace.points.first.position.latitude, 44.1);
  });

  test('le GPX produit contient les coordonnées et le nom', () {
    final gpx = RideExportService().toGpx(_ride(), _points());
    expect(gpx, contains('<gpx'));
    expect(gpx, contains('44.1'));
    expect(gpx, contains('5.3'));
    expect(gpx, contains('Sortie du Ventoux'));
  });

  test('une sortie sans point produit un GPX valide mais vide', () {
    final gpx = RideExportService().toGpx(_ride(), []);
    expect(gpx, contains('<gpx'));
  });

  // Le GPX exporté sert à alimenter un logiciel PC : s il n est pas relisible,
  // personne ne s en aperçoit avant d avoir perdu une trace. On repasse donc
  // la sortie de l export dans le lecteur d import.
  test('aller-retour export puis import : points et coordonnées conservés', () {
    final gpx = RideExportService().toGpx(_ride(), _points());

    final relu = GpxService().loadFromString(gpx, source: 'test');

    expect(relu, isNotNull);
    expect(relu!.points.length, _points().length);
    expect(relu.name, 'Sortie du Ventoux');
    for (var i = 0; i < _points().length; i++) {
      expect(relu.points[i].position.latitude,
          closeTo(_points()[i].lat, 0.000001));
      expect(relu.points[i].position.longitude,
          closeTo(_points()[i].lng, 0.000001));
      expect(relu.points[i].elevation, closeTo(_points()[i].altitude!, 0.001));
    }
  });
}
