import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../app/theme.dart';
import '../providers/fuel_poi_provider.dart';
import 'glass_control.dart';

/// Bouton « stations à proximité » de la colonne de contrôles de la carte.
///
/// Cherche les stations-service et réparateurs moto autour du pilote, à la
/// demande — pensé pour le besoin urgent, panne sèche ou mécanique.
class FuelPoiButton extends StatelessWidget {
  const FuelPoiButton({
    super.key,
    required this.currentCenter,
    required this.radiusKm,
  });

  /// Lu au moment de l'appui : la position du pilote change pendant qu'il roule.
  final LatLng Function() currentCenter;
  final int radiusKm;

  @override
  Widget build(BuildContext context) {
    final poi = context.watch<FuelPoiProvider>();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (poi.unavailable)
          Padding(
            key: const Key('stations-indisponible'),
            padding: const EdgeInsets.only(bottom: 4),
            child: Icon(Icons.cloud_off, size: 16, color: AppColors.orange),
          ),
        GestureDetector(
          key: const Key('bouton-stations-proximite'),
          // Pendant une recherche, l'appui est ignoré : sans cela un pilote
          // impatient empilerait les requêtes Overpass, qui limite le débit.
          onTap: poi.loading
              ? null
              : () => poi.searchAround(currentCenter(), radiusKm: radiusKm),
          child: GlassPuck(
            icon: poi.loading ? Icons.hourglass_top : Icons.local_gas_station,
            color: AppColors.orange,
            active: poi.results.isNotEmpty,
          ),
        ),
      ],
    );
  }
}
