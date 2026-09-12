import 'package:flutter_test/flutter_test.dart';
import 'package:moto_offroad/screens/map3d/reconnaissance_3d_screen.dart';

void main() {
  group('reconnaissance 3D', () {
    // Constate sur appareil le 2026-09-12 : l ecran restait sur sa roue.
    // `loadFlutterAsset` attend une cle de ressource ; un fragment d adresse
    // accroche derriere empeche la page de se charger.
    test('la ressource chargee ne porte ni fragment ni parametre', () {
      expect(Reconnaissance3dScreen.ressource, 'assets/carte3d/index.html');
      expect(Reconnaissance3dScreen.ressource, isNot(contains('#')));
      expect(Reconnaissance3dScreen.ressource, isNot(contains('?')));
    });

    // La position part ensuite par un appel a la page : sans elle, le rider
    // atterrit ailleurs et doit se re-reperer.
    test('l ordre de position porte le centre, l echelle et le fond', () {
      final o = Reconnaissance3dScreen.ordreDePosition(
        longitude: 0.593, latitude: 42.79, zoom: 12.5, fond: 'topo',
      );
      expect(o, 'allerA(0.59300, 42.79000, 12.50, "topo")');
    });

    test('la photo aerienne est le fond par defaut', () {
      final o = Reconnaissance3dScreen.ordreDePosition(
        longitude: 1, latitude: 2, zoom: 3,
      );
      expect(o, endsWith('"photo")'));
    });

    // Le Pays basque est a l ouest de Greenwich.
    test('accepte une longitude negative', () {
      final o = Reconnaissance3dScreen.ordreDePosition(
        longitude: -1.6353, latitude: 43.3092, zoom: 11,
      );
      expect(o, startsWith('allerA(-1.63530,'));
    });
  });
}
