import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../app/theme.dart';
import '../services/location_service.dart';

// ── Marqueur du pilote ───────────────────────────────────────
// Couche qui se redessine seule à chaque relevé GPS. C'est tout l'enjeu :
// le marqueur était auparavant peint depuis une valeur lue dans le build de
// l'écran carte, si bien qu'un nouveau relevé ne le déplaçait pas — la carte
// suivait le pilote (déplacement impératif du contrôleur) pendant que le
// point, lui, restait planté à l'endroit du dernier rafraîchissement de
// l'écran. Écouter la position ici limite aussi le redessin à ce seul
// marqueur, au lieu de reconstruire toute la carte à chaque point.
class RiderPositionLayer extends StatelessWidget {
  const RiderPositionLayer({super.key, required this.positions});

  final ValueListenable<GpsSnapshot?> positions;

  static const Key marqueurKey = Key('marqueur-rider');

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<GpsSnapshot?>(
      valueListenable: positions,
      builder: (context, snap, _) {
        if (snap == null) return const SizedBox.shrink();
        return MarkerLayer(markers: [
          Marker(
            key: marqueurKey,
            point: snap.position,
            width: 30, height: 30,
            child: _RiderMarker(heading: snap.headingDeg),
          ),
        ]);
      },
    );
  }
}

class _RiderMarker extends StatelessWidget {
  const _RiderMarker({required this.heading});

  final double heading;

  @override
  Widget build(BuildContext context) => Transform.rotate(
        angle: heading * (3.14159 / 180),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.secondary,
            border: Border.all(color: AppColors.markerCasing, width: 2.5),
            boxShadow: [
              BoxShadow(color: AppColors.secondary.withValues(alpha: .5), blurRadius: 8),
            ],
          ),
          child: const Icon(Icons.navigation, color: AppColors.onPrimary, size: 16),
        ),
      );
}
