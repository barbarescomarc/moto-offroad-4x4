// lib/widgets/maneuver_tile.dart
import 'package:flutter/material.dart';
import '../app/theme.dart';
import '../models/route_result.dart';

// Flèche de manœuvre et distance dans un même bloc, à la manière d'un GPS
// auto : l'oeil n'a qu'un seul endroit à lire pour "quoi" et "quand".
class ManeuverTile extends StatelessWidget {
  final RouteStep? step;
  final double distanceToNextStepMeters;
  final double size;

  const ManeuverTile({
    super.key,
    required this.step,
    required this.distanceToNextStepMeters,
    this.size = 64,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.orange.withValues(alpha: .15),
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.orange.withValues(alpha: .5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_iconFor(step?.maneuver), color: AppColors.orange, size: 34),
          if (step != null) ...[
            const SizedBox(height: 2),
            Text(
              _distanceLabel(distanceToNextStepMeters),
              style: const TextStyle(color: AppColors.orange, fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ],
        ],
      ),
    );
  }

  static String _distanceLabel(double meters) {
    if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(1)} km';
    return '${meters.round()} m';
  }

  IconData _iconFor(ManeuverType? m) {
    switch (m) {
      case ManeuverType.turnLeft:   return Icons.turn_left;
      case ManeuverType.turnRight:  return Icons.turn_right;
      case ManeuverType.sharpLeft:  return Icons.turn_sharp_left;
      case ManeuverType.sharpRight: return Icons.turn_sharp_right;
      case ManeuverType.uturn:      return Icons.u_turn_left;
      case ManeuverType.arrive:     return Icons.flag;
      case ManeuverType.depart:     return Icons.navigation;
      case ManeuverType.straight:
      case null:                    return Icons.straight;
    }
  }
}
