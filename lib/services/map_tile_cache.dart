// lib/services/map_tile_cache.dart
import 'dart:io';

import 'package:http/http.dart';
import 'package:http/io_client.dart';
import 'package:flutter/foundation.dart';
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

  // Client HTTP partagé, construit ici et jamais ailleurs.
  //
  // C'est le coeur du correctif du 2026-09-11. Un FMTCTileProvider qui
  // fabrique lui-même son client le FERME quand flutter_map le détruit
  // (`TileLayer.dispose()` appelle `tileProvider.dispose()`). Avec un
  // fournisseur unique partagé par toutes les couches, la disparition d'une
  // seule d'entre elles — la surcouche de libellés du satellite, par exemple,
  // qui n'existe que sur ce fond — fermait le client de TOUTES les autres :
  // plus aucune tuile ne pouvait être téléchargée, seules celles déjà en
  // cache s'affichaient, et changer de fond ne semblait plus rien faire.
  //
  // En fournissant nous-mêmes le client, FMTC sait qu'il ne lui appartient
  // pas et ne le ferme jamais (`_wasClientAutomaticallyGenerated`). Chaque
  // couche peut alors avoir son propre fournisseur sans se saborder l'une
  // l'autre.
  static final Client _httpClient = IOClient(HttpClient()..userAgent = null);

  // Un fournisseur par couche de tuiles : ils partagent le même cache et le
  // même client, mais chacun a son cycle de vie. Ne jamais réutiliser la même
  // instance sur deux TileLayer.
  // Témoin de diagnostic (temporaire, 2026-09-11). FMTC y dépose le sort de
  // chaque tuile : venue du réseau, servie par le cache, ou en erreur. Sert à
  // comprendre pourquoi un changement de fond de carte ne repeint pas les
  // tuiles déjà affichées. À retirer une fois la cause établie.
  static final ValueNotifier<TileLoadingInterceptorMap> diagnostic =
      ValueNotifier({});

  // Identité de couche — une instance stable par fond de carte.
  //
  // C'est le coeur du correctif du 2026-09-13. Flutter conserve les images
  // déjà décodées dans un `ImageCache` global, et la clé d'une tuile FMTC est
  // le couple (coordonnées, fournisseur) : l'URL de la tuile n'en fait pas
  // partie. Or `FMTCTileProvider` compare ses champs, pas son identité — deux
  // fournisseurs configurés à l'identique sont donc égaux. La tuile
  // 15/16515/11965 de la photo aérienne, du fond topo et de l'ombrage
  // partageaient ainsi une seule et même entrée : la première couche à
  // décoder cette tuile gagnait, et les autres recevaient son image sans
  // jamais interroger le cache disque ni le réseau. Basculer en satellite ne
  // repeignait rien, et très dézoomé il ne restait que l'ombrage à l'écran.
  //
  // `urlTransformer` est le seul champ de l'égalité comparé par identité de
  // fonction. Il porte donc ici le nom de la couche, sans rien transformer :
  // deux couches distinctes donnent des fournisseurs inégaux (entrées
  // séparées), deux reconstructions d'une même couche donnent des
  // fournisseurs égaux (entrée conservée, pas de rechargement inutile).
  static final Map<String, String Function(String)> _identites = {};

  static String Function(String) _identiteDe(String couche) =>
      _identites.putIfAbsent(couche, () => (url) => url);

  static FMTCTileProvider provider(String couche) => FMTCTileProvider(
        stores: const {storeName: BrowseStoreStrategy.readUpdateCreate},
        httpClient: _httpClient,
        tileLoadingInterceptor: diagnostic,
        urlTransformer: _identiteDe(couche),
      );

  // Taille en Ko (kibioctets, unité native de FMTC) et nombre de tuiles.
  static Future<({double sizeKb, int tileCount})> stats() async {
    final all = await const FMTCStore(storeName).stats.all;
    return (sizeKb: all.size, tileCount: all.length);
  }

  static Future<void> clear() => const FMTCStore(storeName).manage.reset();
}
