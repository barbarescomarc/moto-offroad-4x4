// test/providers/map_provider_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:moto_offroad/providers/map_provider.dart';

void main() {
  group('navigationTileUrl', () {
    test('rend le fond clair en journée', () {
      final mapProv = MapProvider();
      final url = mapProv.navigationTileUrl(now: () => DateTime(2026, 1, 1, 12));
      expect(url, contains('World_Light_Gray_Base'));
    });

    test('rend le fond sombre la nuit', () {
      final mapProv = MapProvider();
      final url = mapProv.navigationTileUrl(now: () => DateTime(2026, 1, 1, 23));
      expect(url, contains('World_Dark_Gray_Base'));
    });
  });

  group('navigationLabelsOverlayUrl', () {
    test('rend les labels clairs en journée, assortis au fond', () {
      final mapProv = MapProvider();
      final url = mapProv.navigationLabelsOverlayUrl(now: () => DateTime(2026, 1, 1, 12));
      expect(url, contains('World_Light_Gray_Reference'));
    });

    test('rend les labels sombres la nuit, assortis au fond', () {
      final mapProv = MapProvider();
      final url = mapProv.navigationLabelsOverlayUrl(now: () => DateTime(2026, 1, 1, 23));
      expect(url, contains('World_Dark_Gray_Reference'));
    });
  });

  group('fournisseurs de tuiles', () {
    // OSM a bloque l app le 2026-09-10 (« Access blocked — App is not
    // following the tile usage policy »). Le fond par defaut ne doit plus
    // jamais pointer vers un serveur benevole.
    test('le fond par defaut est l IGN, pas un serveur benevole', () {
      expect(MapProvider().activeLayer, MapLayer.ign);
    });

    // Decision du 2026-09-12 : un fond qu on ne peut pas emporter en sortie
    // n a pas sa place dans une app de tout-terrain. Seuls les fonds IGN
    // subsistent ; OSM, OpenTopoMap et la photo d Esri ont ete retires.
    test('toutes les couches proposees sont telechargeables hors ligne', () {
      expect(MapLayer.values, [MapLayer.photo, MapLayer.ign]);
      for (final c in MapLayer.values) {
        expect(c.autoriseTelechargementHorsLigne, isTrue,
            reason: 'aucun fond ne doit etre propose sans le hors-ligne');
        expect(c.tileUrl, contains('data.geopf.fr'),
            reason: 'seule la Geoplateforme IGN ne nous bloque pas');
      }
    });

    test('chaque couche declare la profondeur reellement servie', () {
      expect(MapLayer.ign.zoomNatifMax, 18);
      expect(MapLayer.photo.zoomNatifMax, 19);
    });

    // La photo d Esri manque a certains zooms ; celle de l IGN est la reponse
    // pour la France, et elle doit viser la Geoplateforme, pas un tiers.
    test('la photo aerienne vient de la Geoplateforme IGN', () {
      expect(MapLayer.photo.tileUrl, contains('data.geopf.fr'));
      expect(MapLayer.photo.tileUrl, contains('ORTHOIMAGERY.ORTHOPHOTOS'));
      expect(MapLayer.photo.label, 'Photo IGN');
    });
  });
}
