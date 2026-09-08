// lib/services/map_tile_cache.dart
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';

// Cache passif des tuiles de carte : toute tuile déjà affichée (n'importe
// quel fond — satellite, chemins, IGN, topo, ou le fond de navigation)
// reste disponible hors connexion ensuite. Pas de téléchargement explicite
// d'une zone (voir le mode d'emploi) : seulement ce qui a déjà été vu.
//
// Le radar pluie (RainViewer) n'est volontairement pas mis en cache : chaque
// relevé porte une URL horodatée unique, le mettre en cache remplirait le
// stockage de prévisions obsolètes sans jamais resservir hors-ligne.
class MapTileCache {
  MapTileCache._();

  static const String storeName = 'mapTiles';
  // Plafond généreux mais fini — évite une croissance illimitée du stockage
  // sur un usage purement passif (pas de téléchargement de zone entière).
  static const int _maxDatabaseSizeKb = 1000000; // ~1 Go

  static Future<void> initialize() async {
    await FMTCObjectBoxBackend().initialise(maxDatabaseSize: _maxDatabaseSizeKb);
    const store = FMTCStore(storeName);
    if (!await store.manage.ready) {
      await store.manage.create();
    }
  }

  // Construit une seule fois (voir la recommandation FMTC) et réutilisé par
  // toutes les couches de tuiles du fond de carte.
  static final FMTCTileProvider tileProvider = FMTCTileProvider(
    stores: const {storeName: BrowseStoreStrategy.readUpdateCreate},
  );

  // Taille en Ko (kibioctets, unité native de FMTC) et nombre de tuiles.
  static Future<({double sizeKb, int tileCount})> stats() async {
    final all = await const FMTCStore(storeName).stats.all;
    return (sizeKb: all.size, tileCount: all.length);
  }

  static Future<void> clear() => const FMTCStore(storeName).manage.reset();
}
