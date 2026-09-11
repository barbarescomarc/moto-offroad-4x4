import 'package:flutter_test/flutter_test.dart';
import 'package:moto_offroad/services/map_tile_cache.dart';

void main() {
  group('fournisseur de tuiles', () {
    // Regression du 2026-09-11 : un fournisseur unique partage par toutes les
    // couches fermait son client HTTP des qu une seule couche disparaissait
    // (TileLayer.dispose appelle tileProvider.dispose, et FMTC ferme le client
    // qu il a lui-meme fabrique). Plus aucune tuile ne se telechargeait
    // ensuite : changer de fond de carte ne faisait plus rien.
    test('chaque couche recoit sa propre instance', () {
      final a = MapTileCache.provider();
      final b = MapTileCache.provider();
      expect(identical(a, b), isFalse,
          reason: 'deux TileLayer ne doivent jamais partager un fournisseur');
    });

    test('le client HTTP est fourni par nous, donc jamais ferme par FMTC', () {
      final a = MapTileCache.provider();
      final b = MapTileCache.provider();
      expect(identical(a.httpClient, b.httpClient), isTrue,
          reason: 'un client unique et durable, partage par tous les fournisseurs');
    });
  });
}
