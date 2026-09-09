import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../app/theme.dart';
import '../models/poi.dart';
import '../providers/fuel_poi_provider.dart';
import 'glass_control.dart';

/// Bouton « stations à proximité » de la colonne de contrôles de la carte.
///
/// Cherche les stations-service et réparateurs moto autour du pilote, à la
/// demande — pensé pour le besoin urgent, panne sèche ou mécanique.
class FuelPoiButton extends StatefulWidget {
  const FuelPoiButton({
    super.key,
    required this.currentCenter,
    required this.radiusKm,
    this.onResults,
  });

  /// Lu au moment de l'appui : la position du pilote change pendant qu'il roule.
  final LatLng Function() currentCenter;
  final int radiusKm;

  /// Appelé quand une recherche aboutit. Sans lui, le pilote appuie, l'icône
  /// change de couleur, et les stations restent hors cadre — de son point de
  /// vue, il ne s'est rien passé. La carte s'en sert pour se recadrer.
  final void Function(List<PoiModel> resultats)? onResults;

  @override
  State<FuelPoiButton> createState() => _FuelPoiButtonState();
}

class _FuelPoiButtonState extends State<FuelPoiButton> {
  Future<void> _chercher() async {
    final poi = context.read<FuelPoiProvider>();
    await poi.searchAround(widget.currentCenter(), radiusKm: widget.radiusKm);
    if (!mounted) return;
    if (poi.results.isNotEmpty) widget.onResults?.call(poi.results);
  }

  @override
  Widget build(BuildContext context) {
    final poi = context.watch<FuelPoiProvider>();

    // Pile plutôt que colonne : l'indicateur se superpose au coin du bouton
    // au lieu de le pousser vers le bas. Un bouton qui se déplace quand
    // l'erreur s'affiche se fait rater au second appui.
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        GestureDetector(
          key: const Key('bouton-stations-proximite'),
          // Pendant une recherche, l'appui est ignoré : sans cela un pilote
          // impatient empilerait les requêtes Overpass, qui limite le débit.
          onTap: poi.loading ? null : _chercher,
          child: GlassPuck(
            icon: poi.loading ? Icons.hourglass_top : Icons.local_gas_station,
            color: AppColors.orange,
            active: poi.results.isNotEmpty,
          ),
        ),
        if (poi.unavailable)
          Positioned(
            top: -2,
            right: -2,
            child: Icon(
              Icons.cloud_off,
              key: const Key('stations-indisponible'),
              size: 16,
              color: AppColors.orange,
            ),
          ),
      ],
    );
  }
}
