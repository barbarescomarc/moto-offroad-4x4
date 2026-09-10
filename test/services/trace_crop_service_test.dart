import 'package:flutter_test/flutter_test.dart';
import 'package:moto_offroad/models/ride.dart';
import 'package:moto_offroad/services/trace_crop_service.dart';

List<RidePoint> pointsFactices(int n) => List.generate(n, (i) => RidePoint(
      rideId: 'r1', seq: i, segment: 0,
      lat: 43.60 + i * 0.001, lng: 1.44, altitude: 150 + i.toDouble(), speedKmh: 30,
      timestamp: DateTime(2026, 9, 1, 8, i),
    ));

final ride = Ride(
  id: 'r1', name: 'Sortie du dimanche', startedAt: DateTime(2026, 9, 1, 8),
  source: RideSource.recorded, status: RideStatus.finished, stats: RideStats.empty,
);

void main() {
  test('le GPX publie ne contient que l intervalle retenu', () {
    final gpx = TraceCropService.cropToGpx(ride, pointsFactices(10),
        startIndex: 3, endIndex: 6, name: 'Boucle publiee');

    expect('lat="'.allMatches(gpx).length, 4); // 3, 4, 5 et 6
    expect(gpx.contains('43.603'), isTrue);
    expect(gpx.contains('43.600'), isFalse); // le depart devant chez soi a saute
    expect(gpx.contains('43.609'), isFalse);
    expect(gpx.contains('Boucle publiee'), isTrue);
  });

  test('recadrer ne touche pas les points d origine', () {
    final points = pointsFactices(10);
    TraceCropService.cropToGpx(ride, points, startIndex: 2, endIndex: 5, name: 'B');
    expect(points.length, 10);
    expect(points.first.lat, 43.60);
  });

  test('des bornes incoherentes sont refusees', () {
    final points = pointsFactices(10);
    expect(() => TraceCropService.cropToGpx(ride, points, startIndex: 5, endIndex: 5, name: 'B'),
        throwsArgumentError);
    expect(() => TraceCropService.cropToGpx(ride, points, startIndex: -1, endIndex: 4, name: 'B'),
        throwsArgumentError);
    expect(() => TraceCropService.cropToGpx(ride, points, startIndex: 0, endIndex: 10, name: 'B'),
        throwsArgumentError);
  });

  test('la distance de l intervalle est plus courte que celle de la trace entiere', () {
    final points = pointsFactices(10);
    final totale = TraceCropService.distanceOf(points, 0, 9);
    final partielle = TraceCropService.distanceOf(points, 3, 6);
    expect(partielle, lessThan(totale));
    expect(partielle, greaterThan(0));
  });
}
