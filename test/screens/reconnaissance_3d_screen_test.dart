import 'package:flutter_test/flutter_test.dart';
import 'package:moto_offroad/screens/map3d/reconnaissance_3d_screen.dart';

void main() {
  group('adresse de la reconnaissance 3D', () {
    // La 3D doit s ouvrir la ou le rider regardait : si la position n est pas
    // transmise, il atterrit ailleurs et doit se re-reperer.
    test('porte la position, l echelle et le fond', () {
      final a = Reconnaissance3dScreen.adresse(
        longitude: 0.593, latitude: 42.79, zoom: 12.5, fond: 'topo',
      );
      expect(a, startsWith('assets/carte3d/index.html#'));
      expect(a, contains('lon=0.59300'));
      expect(a, contains('lat=42.79000'));
      expect(a, contains('zoom=12.50'));
      expect(a, contains('fond=topo'));
    });

    test('la photo aerienne est le fond par defaut', () {
      final a = Reconnaissance3dScreen.adresse(longitude: 1, latitude: 2, zoom: 3);
      expect(a, contains('fond=photo'));
    });

    // Une longitude negative (Pays basque) ne doit pas casser le fragment.
    test('accepte une longitude negative', () {
      final a = Reconnaissance3dScreen.adresse(
        longitude: -1.6353, latitude: 43.3092, zoom: 11,
      );
      expect(a, contains('lon=-1.63530'));
    });
  });
}
