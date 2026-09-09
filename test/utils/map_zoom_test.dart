import 'package:flutter_test/flutter_test.dart';
import 'package:moto_offroad/utils/map_zoom.dart';

void main() {
  test('un rayon de 20 km tient a l ecran au zoom 11', () {
    expect(zoomPourRayonKm(20), 11);
  });

  test('doubler le rayon recule d un niveau de zoom', () {
    expect(zoomPourRayonKm(40), 10);
    expect(zoomPourRayonKm(10), 12);
  });

  test('le zoom reste dans des bornes utilisables', () {
    // Trop loin, le pilote ne distingue plus rien ; trop pres, la recherche
    // parait vide alors que les stations sont juste hors cadre.
    expect(zoomPourRayonKm(2000), greaterThanOrEqualTo(6));
    expect(zoomPourRayonKm(1), lessThanOrEqualTo(14));
  });
}
