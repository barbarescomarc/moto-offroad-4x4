import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moto_offroad/providers/map_provider.dart';
import 'package:moto_offroad/services/map_tile_cache.dart';

void main() {
  group('fournisseur de tuiles', () {
    // Regression du 2026-09-11 : un fournisseur unique partage par toutes les
    // couches fermait son client HTTP des qu une seule couche disparaissait
    // (TileLayer.dispose appelle tileProvider.dispose, et FMTC ferme le client
    // qu il a lui-meme fabrique). Plus aucune tuile ne se telechargeait
    // ensuite : changer de fond de carte ne faisait plus rien.
    test('chaque couche recoit sa propre instance', () {
      final a = MapTileCache.provider('ign');
      final b = MapTileCache.provider('ign');
      expect(identical(a, b), isFalse,
          reason: 'deux TileLayer ne doivent jamais partager un fournisseur');
    });

    test('le client HTTP est fourni par nous, donc jamais ferme par FMTC', () {
      final a = MapTileCache.provider('ign');
      final b = MapTileCache.provider('ign');
      expect(identical(a.httpClient, b.httpClient), isTrue,
          reason: 'un client unique et durable, partage par tous les fournisseurs');
    });
  });

  // Regression du 2026-09-13 : passer en satellite ne repeignait rien, et
  // dezoomer beaucoup ne laissait que l ombrage a l ecran.
  //
  // Flutter garde les images decodees dans un ImageCache global. La clef de
  // cette memoire, pour une tuile FMTC, c est (coordonnees, fournisseur) —
  // l URL de la tuile n en fait PAS partie. Deux fournisseurs dont tous les
  // champs sont egaux sont donc interchangeables : la tuile (15/16515/11965)
  // du fond topo et celle de la photo aerienne partageaient une seule entree.
  // La premiere couche a decoder la tuile gagnait, et les autres recevaient
  // son image sans jamais interroger ni le cache disque ni le reseau.
  //
  // Le champ urlTransformer, compare par identite, porte donc l identite de
  // la couche : une instance stable par couche, distincte d une couche a l
  // autre.
  group('memoire image de Flutter', () {
    const tuile = TileCoordinates(16515, 11965, 15);

    ImageProvider imageDe(String couche, String url) =>
        MapTileCache.provider(couche).getImage(tuile, TileLayer(urlTemplate: url));

    test('deux fonds differents ne partagent pas une entree', () {
      expect(
        imageDe('photo', MapLayer.photo.tileUrl) ==
            imageDe('ign', MapLayer.ign.tileUrl),
        isFalse,
      );
    });

    test('l ombrage ne prend pas la place du fond', () {
      expect(
        imageDe('estompage', MapProvider.estompageUrl) ==
            imageDe('photo', MapLayer.photo.tileUrl),
        isFalse,
      );
    });

    // Le revers : une meme couche doit garder une entree stable d une
    // reconstruction a l autre, sinon chaque rebuild rechargerait tout.
    test('un meme fond garde son entree entre deux reconstructions', () {
      expect(
        imageDe('photo', MapLayer.photo.tileUrl) ==
            imageDe('photo', MapLayer.photo.tileUrl),
        isTrue,
      );
    });
  });
}
