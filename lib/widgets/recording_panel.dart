import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app/router.dart';
import '../models/ride.dart';
import '../services/ride_merge_service.dart';
import '../services/ride_repository.dart';
import '../providers/recording_provider.dart';
import '../providers/settings_provider.dart';
import '../services/ride_recorder.dart';
import '../services/ride_recording_service.dart';
import '../services/ride_sensor_bridge.dart';
import '../services/vibration_calibration.dart';

// ── Bouton REC et bandeau de statistiques ────────────────────
class RecordingPanel extends StatelessWidget {
  const RecordingPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final rec = context.watch<RecordingProvider>();
    return rec.state == RecorderState.idle
        ? const _RecButton()
        : const _RecordingBar();
  }
}

// ── Bouton de démarrage ──────────────────────────────────────
class _RecButton extends StatelessWidget {
  const _RecButton();

  Future<void> _start(BuildContext context) async {
    final settings = context.read<SettingsProvider>();
    final rec = context.read<RecordingProvider>();
    final messenger = ScaffoldMessenger.of(context);

    // Sans la permission de notification, Android n'affiche pas le service
    // d'avant-plan et tue l'application dès l'écran éteint : l'enregistrement
    // s'arrêterait au milieu de la balade sans prévenir.
    if (!await RideRecordingService().requestPermissions()) {
      messenger.showSnackBar(const SnackBar(
        content: Text(
          'Sans autorisation de notification, l enregistrement s arrêtera '
          'quand l écran s éteindra.',
        ),
      ));
    }

    final calibration = await VibrationCalibration.load();

    final now = DateTime.now();
    await rec.startRide(
      name: 'Sortie du ${now.day}/${now.month}/${now.year}',
      config: RecorderConfig(
        pauseSpeedKmh:      settings.pauseSpeedKmh.toDouble(),
        vibrationThreshold: calibration.threshold,
        autoPauseEnabled:   settings.autoPauseEnabled,
        signalGapDelay:     Duration(seconds: settings.signalGapSeconds),
      ),
    );
    RideSensorBridge().attach(rec);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: SizedBox(
        height: 56,
        child: ElevatedButton.icon(
          onPressed: () => _start(context),
          icon: const Icon(Icons.fiber_manual_record, size: 26),
          label: const Text('ENREGISTRER',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFEF5350),
            foregroundColor: Colors.white,
          ),
        ),
      ),
    );
  }
}

// ── Bandeau pendant l'enregistrement ─────────────────────────
class _RecordingBar extends StatelessWidget {
  const _RecordingBar();

  Future<void> _stop(BuildContext context) async {
    final rec = context.read<RecordingProvider>();
    final settings = context.read<SettingsProvider>();
    final repo = context.read<RideRepository>();
    RideSensorBridge().detach();

    final gaps = rec.signalGapSegments;
    var ride = await rec.stopRide();

    if (ride != null && settings.askNameOnStop && context.mounted) {
      final nom = await _demanderNom(context, ride.name);
      if (nom != null && nom.trim().isNotEmpty) {
        ride = ride.copyWith(name: nom.trim());
        await repo.updateRide(ride);
      }
    }

    if (ride != null && gaps.isNotEmpty && context.mounted) {
      ride = await _proposerFusion(context, ride, repo, gaps);
    }

    if (ride != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sortie enregistrée : ${ride.name}')),
      );

      // Invite à calibrer après la première sortie
      final prefs = await SharedPreferences.getInstance();
      final dejaPropose = prefs.getBool('calibration_prompt_shown') ?? false;
      final cal = await VibrationCalibration.load();
      if (!dejaPropose && !cal.isCalibrated && context.mounted) {
        await prefs.setBool('calibration_prompt_shown', true);
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Calibrer les vibrations ?'),
            content: const Text(
                'La pause automatique sera bien plus fiable si l\'application '
                'connaît les vibrations de votre moto. Cela prend '
                '20 secondes.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Plus tard'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Calibrer'),
              ),
            ],
          ),
        );
        if (go == true && context.mounted) context.push(AppRoutes.calibration);
      }
    }
  }

  Future<String?> _demanderNom(BuildContext context, String actuel) {
    final champ = TextEditingController(text: actuel);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nom de la sortie'),
        content: TextField(
          controller: champ,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Nom de la sortie'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Garder'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, champ.text),
            child: const Text('Valider'),
          ),
        ],
      ),
    );
  }

  // Une perte de signal a coupé la trace en plusieurs morceaux. On ne fusionne
  // jamais d'office : le pilote sait s'il a roulé en ligne droite dans le
  // tunnel ou s'il a fait un détour que la ligne droite trahirait.
  Future<Ride> _proposerFusion(BuildContext context, Ride ride,
      RideRepository repo, Set<int> gaps) async {
    final morceaux = gaps.length + 1;
    final fusionner = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Traces séparées'),
        content: Text(
            'Le signal GPS a été perdu pendant la sortie : elle contient '
            '$morceaux traces séparées.\n\nLes fusionner en une seule ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Garder séparées'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Fusionner'),
          ),
        ],
      ),
    );
    if (fusionner != true || !context.mounted) return ride;

    final intermediaires = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Points intermédiaires'),
        content: const Text(
            'Ajouter des points le long de la portion sans signal ?\n\n'
            'Sans eux, les deux traces sont simplement reliées par un trait.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Simple trait'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
    if (!context.mounted) return ride;

    return RideMergeService.mergeGaps(
      ride:        ride,
      repo:        repo,
      gapSegments: gaps,
      interpolate: intermediaires == true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final rec = context.watch<RecordingProvider>();
    final stats = rec.liveStats;
    final paused = rec.isPaused;
    final d = stats.totalTime;
    final shouldRemind = rec.shouldRemindPause;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Rappel « Toujours en balade ? » après 15 min sans mouvement
        if (shouldRemind)
          MaterialBanner(
            content: const Text('Toujours en balade ?'),
            leading: const Icon(Icons.info_outline),
            actions: [
              TextButton(
                onPressed: () => rec.togglePause(),
                child: const Text('Mettre en pause'),
              ),
              TextButton(
                onPressed: () => rec.acknowledgeReminder(),
                child: const Text('Continuer'),
              ),
            ],
          ),
        // Panneau d'enregistrement principal
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: paused ? const Color(0xFF5C4B1F) : const Color(0xFF7A1F1F),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: paused ? const Color(0xFFF9A825) : const Color(0xFFEF5350),
              width: 2,
            ),
          ),
          child: Row(
            children: [
              Icon(paused ? Icons.pause_circle : Icons.fiber_manual_record,
                  color: Colors.white, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      paused ? 'EN PAUSE' : 'ENREGISTREMENT',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2),
                    ),
                    Text(
                      '${stats.distanceKm.toStringAsFixed(1).replaceAll('.', ',')} km'
                      ' · ${d.inHours.toString().padLeft(2, '0')}'
                      ':${(d.inMinutes % 60).toString().padLeft(2, '0')}'
                      ' · ${stats.avgSpeedKmh.toStringAsFixed(0)} km/h',
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: paused ? 'Reprendre' : 'Mettre en pause',
                icon: Icon(paused ? Icons.play_arrow : Icons.pause,
                    color: Colors.white, size: 28),
                onPressed: () => context.read<RecordingProvider>().togglePause(),
              ),
              // Appui long : un arrêt accidentel après trois heures de sortie
              // n'est pas rattrapable.
              GestureDetector(
                onLongPress: () => _stop(context),
                child: Tooltip(
                  message: 'Appui long pour arrêter',
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    child: const Icon(Icons.stop, color: Colors.white, size: 28),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
