// lib/widgets/guidance_banner.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app/theme.dart';
import '../providers/guidance_provider.dart';
import '../providers/settings_provider.dart';
import 'maneuver_tile.dart';

class GuidanceBanner extends StatelessWidget {
  // À false, le carré flèche+distance est affiché ailleurs à l'écran (voir
  // MapScreen, portrait normal) : l'instruction card ne garde alors que le
  // texte "Suivi de la trace" et les icônes GPS perdu/hors piste, pour ne
  // pas le dupliquer.
  final bool showManeuverTile;

  const GuidanceBanner({super.key, this.showManeuverTile = true});

  @override
  Widget build(BuildContext context) {
    final guidance = context.watch<GuidanceProvider>();
    if (!guidance.isActive) return const SizedBox.shrink();

    final controlZone = guidance.upcomingControlZoneMeters;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (controlZone != null) ...[
          _controlZoneAlert(controlZone),
          const SizedBox(height: 6),
        ],
        _instructionCard(guidance),
        const SizedBox(height: 6),
        _footer(context, guidance),
      ],
    );
  }

  // Jamais le mot « radar » ni sa position exacte : seule une zone de
  // danger est autorisée en France (décret du 3 janvier 2012).
  Widget _controlZoneAlert(double distanceMeters) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.statusOrange.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.statusOrange.withValues(alpha: .6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.warning_amber, color: AppColors.statusOrange, size: 20),
          const SizedBox(width: 8),
          Text(
            'Zone de contrôle possible à ${_distanceLabel(distanceMeters)}',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _instructionCard(GuidanceProvider guidance) {
    // En mode alerte, l'unique étape est l'arrivée : elle pilote la fin du
    // guidage, elle n'est pas une manœuvre à exécuter. Le rider suit sa trace,
    // c'est ce que le bandeau doit dire.
    final step =
        guidance.mode == GuidanceMode.gpxAlert ? null : guidance.currentStep;
    // Le texte d'instruction d'ORS embarque le nom de rue ("Tournez à gauche
    // sur D941") : pas encore souhaité à l'affichage. Tant que c'est le cas,
    // la manœuvre ne parle qu'à travers la flèche + la distance ; le texte ne
    // revient que pour "Suivi de la trace", qui ne nomme aucune rue.
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.bgPanel.withValues(alpha: .92),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A3E)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showManeuverTile)
            ManeuverTile(step: step, distanceToNextStepMeters: guidance.distanceToNextStepMeters),
          if (step == null) ...[
            if (showManeuverTile) const SizedBox(width: 12),
            const Flexible(
              child: Text(
                'Suivi de la trace',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
              ),
            ),
          ],
          if (guidance.gpsSignalLost) ...[
            const SizedBox(width: 10),
            const Icon(Icons.gps_off, color: AppColors.statusRed, size: 20),
          ] else if (guidance.isOffRoute) ...[
            const SizedBox(width: 10),
            const Icon(Icons.warning_amber, color: AppColors.statusOrange, size: 20),
          ],
        ],
      ),
    );
  }

  static String _distanceLabel(double meters) {
    if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(1)} km';
    return '${meters.round()} m';
  }

  Widget _footer(BuildContext context, GuidanceProvider guidance) {
    final remainingKm = (guidance.remainingDistanceMeters / 1000).toStringAsFixed(1);
    final eta = guidance.eta;
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
          // Pas d'estimation sur une trace GPX : elle ne porte aucune durée,
          // afficher « 0 min » induirait le rider en erreur.
          if (eta > Duration.zero) ...[
            const Text(' · ', style: TextStyle(color: Colors.white38, fontSize: 12)),
            Text(_formatEta(eta), style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
          const Spacer(),
          IconButton(
            icon: Icon(guidance.isMuted ? Icons.volume_off : Icons.volume_up, color: Colors.white70, size: 20),
            onPressed: () => _toggleMute(context, guidance),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: AppColors.statusRed, size: 20),
            onPressed: guidance.stop,
          ),
        ],
      ),
    );
  }

  // Le bouton du bandeau et l'interrupteur des Réglages commandent la même
  // chose : on bascule la voix en session ET on persiste le choix, sinon
  // l'un des deux affiche un état que l'autre a démenti.
  void _toggleMute(BuildContext context, GuidanceProvider guidance) {
    final newMuted = !guidance.isMuted;
    guidance.toggleMute();
    context.read<SettingsProvider>().setGuidanceVoiceMuted(newMuted);
  }

  static String _formatEta(Duration d) {
    if (d.inHours >= 1) {
      return '${d.inHours}h${(d.inMinutes % 60).toString().padLeft(2, '0')}';
    }
    return d.inMinutes < 1 ? '< 1 min' : '${d.inMinutes} min';
  }
}
