// lib/utils/map_zoom.dart
import 'dart:math' as math;

/// Niveau de zoom auquel un rayon de recherche tient à l'écran.
///
/// Après une recherche de stations, la carte doit montrer ce qu'elle vient de
/// trouver : au zoom d'une rue, des résultats répartis sur vingt kilomètres
/// sont tous hors cadre, et le pilote conclut que rien n'a fonctionné.
///
/// Référence : un rayon de 20 km tient au zoom 11 sur un écran de téléphone.
/// Chaque doublement du rayon recule d'un niveau, la largeur couverte doublant
/// à chaque niveau de zoom.
int zoomPourRayonKm(int rayonKm) {
  const rayonReference = 20;
  const zoomReference = 11;

  final rayon = rayonKm <= 0 ? rayonReference : rayonKm;
  final zoom = zoomReference - (math.log(rayon / rayonReference) / math.ln2);

  // Bornes : au-delà on ne distingue plus rien, en deçà la recherche paraît
  // vide alors que les résultats sont juste hors cadre.
  return zoom.round().clamp(6, 14);
}
