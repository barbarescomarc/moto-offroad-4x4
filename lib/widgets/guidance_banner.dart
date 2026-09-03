// lib/widgets/guidance_banner.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app/theme.dart';
import '../models/route_result.dart';
import '../providers/guidance_provider.dart';

class GuidanceBanner extends StatelessWidget {
  const GuidanceBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final guidance = context.watch<GuidanceProvider>();
    if (!guidance.isActive) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _instructionCard(guidance),
        const SizedBox(height: 6),
        _footer(guidance),
      ],
    );
  }

  Widget _instructionCard(GuidanceProvider guidance) {
    final step = guidance.currentStep;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.bgPanel.withValues(alpha: .92),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A3E)),
      ),
      child: Row(
        children: [
          Icon(_iconFor(step?.maneuver), color: AppColors.orange, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step?.instruction ?? 'Suivi de la trace',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                ),
                if (step != null)
                  Text(
                    '${guidance.distanceToNextStepMeters.round()} m',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
              ],
            ),
          ),
          if (guidance.gpsSignalLost)
            const Icon(Icons.gps_off, color: AppColors.statusRed, size: 20)
          else if (guidance.isOffRoute)
            const Icon(Icons.warning_amber, color: AppColors.statusOrange, size: 20),
        ],
      ),
    );
  }

  Widget _footer(GuidanceProvider guidance) {
    final remainingKm = (guidance.remainingDistanceMeters / 1000).toStringAsFixed(1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.bgPanel.withValues(alpha: .92),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A3E)),
      ),
      child: Row(
        children: [
          Text('$remainingKm km restants', style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const Spacer(),
          IconButton(
            icon: Icon(guidance.isMuted ? Icons.volume_off : Icons.volume_up, color: Colors.white70, size: 20),
            onPressed: guidance.toggleMute,
          ),
          IconButton(
            icon: const Icon(Icons.close, color: AppColors.statusRed, size: 20),
            onPressed: guidance.stop,
          ),
        ],
      ),
    );
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
