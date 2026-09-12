import 'package:flutter_test/flutter_test.dart';
import 'package:moto_offroad/utils/echelle_distance.dart';

void main() {
  group('palier de la règle graduée', () {
    test('prend le plus grand palier qui tient dans la largeur', () {
      // 100 px de large à 3 m/px = 300 m disponibles : le palier 200 m tient,
      // le palier 500 m déborderait.
      expect(
        palierPourLargeur(metresParPixel: 3, largeurMaxPixels: 100),
        200,
      );
    });

    test('tombe juste quand la largeur vaut exactement un palier', () {
      expect(
        palierPourLargeur(metresParPixel: 1, largeurMaxPixels: 500),
        500,
      );
    });

    test('garde le plus petit palier plutôt que rien quand tout déborde', () {
      expect(
        palierPourLargeur(metresParPixel: 0.001, largeurMaxPixels: 100),
        paliersEchelle.first,
      );
    });

    test('monte jusqu au dernier palier sur une carte très dézoomée', () {
      expect(
        palierPourLargeur(metresParPixel: 100000, largeurMaxPixels: 100),
        paliersEchelle.last,
      );
    });
  });

  group('mise en forme des distances', () {
    test('sous le kilomètre, des mètres entiers', () {
      expect(formaterDistance(200), '200 m');
    });

    test('la bascule se fait à 1000 m pile', () {
      expect(formaterDistance(999), '999 m');
      expect(formaterDistance(1000), '1 km');
    });

    test('une décimale, avec la virgule française', () {
      expect(formaterDistance(2500), '2,5 km');
    });

    test('au dela de 10 km la décimale ne sert plus', () {
      expect(formaterDistance(12500), '13 km');
    });
  });

  group('arrondi de lecture', () {
    test('deux chiffres significatifs', () {
      expect(arrondirPourLecture(237), 240);
      expect(arrondirPourLecture(1234), 1200);
    });

    test('laisse intactes les valeurs deja rondes', () {
      expect(arrondirPourLecture(500), 500);
    });

    test('descend sous le metre sans casser', () {
      expect(arrondirPourLecture(0.47), closeTo(0.47, 0.005));
    });

    test('une distance nulle ne fait pas boucler le calcul', () {
      expect(arrondirPourLecture(0), 0);
    });
  });
}
