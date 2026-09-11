import 'package:flutter/material.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';

import '../services/map_tile_cache.dart';

/// Bandeau de diagnostic temporaire (2026-09-11).
///
/// Affiche le sort des tuiles de carte telles que FMTC les rapporte : combien
/// sont venues du réseau, combien du cache, combien ont échoué, et l'hôte
/// réellement interrogé. Sert à comprendre pourquoi changer de fond de carte
/// ne repeint pas les tuiles déjà à l'écran. À retirer une fois la cause
/// établie.
class TileDiagnosticOverlay extends StatelessWidget {
  const TileDiagnosticOverlay({super.key, required this.couche});

  /// Nom de la couche actuellement choisie, pour vérifier qu'il change bien.
  final String couche;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TileLoadingInterceptorMap>(
      valueListenable: MapTileCache.diagnostic,
      builder: (context, tuiles, _) {
        var reseau = 0, cache = 0, erreurs = 0;
        String? hote;
        String? derniereErreur;

        for (final t in tuiles.values) {
          if (t.error != null) {
            erreurs++;
            derniereErreur = t.error!.error.toString();
          } else if (t.resultPath == TileLoadingInterceptorResultPath.fetchedFromNetwork) {
            reseau++;
          } else {
            cache++;
          }
          hote ??= Uri.tryParse(t.networkUrl)?.host;
        }

        return IgnorePointer(
          child: Container(
            margin: const EdgeInsets.all(6),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('couche : $couche · tuiles : ${tuiles.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 11)),
                Text('réseau $reseau · cache $cache · erreurs $erreurs',
                    style: const TextStyle(color: Colors.white70, fontSize: 11)),
                if (hote != null)
                  Text(hote, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                if (derniereErreur != null)
                  Text(
                    derniereErreur.length > 60
                        ? '${derniereErreur.substring(0, 60)}…'
                        : derniereErreur,
                    style: const TextStyle(color: Colors.orangeAccent, fontSize: 10),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
