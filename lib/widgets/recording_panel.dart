import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app/router.dart';
import '../app/theme.dart';
import '../widgets/glass_control.dart';
import '../models/ride.dart';
import '../services/ride_merge_service.dart';
import '../services/ride_repository.dart';
import '../providers/recording_provider.dart';
import '../providers/settings_provider.dart';
import '../services/ride_recorder.dart';
import '../services/ride_recording_service.dart';
import '../services/ride_sensor_bridge.dart';
import '../services/vibration_calibration.dart';

// ── Commandes d'enregistrement ───────────────────────────────
//
// Une colonne de boutons ronds au gabarit du SOS, glissée sous lui. Le
// bandeau pleine largeur qui occupait le bas de l'écran recouvrait les
// onglets de navigation ; empilé sur le côté, il ne recouvre plus rien et
// reste atteignable avec des gants dans les deux orientations.
class RecordingPanel extends StatelessWidget {
  const RecordingPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final rec = context.watch<RecordingProvider>();
    return rec.state == RecorderState.idle
        ? const _RecButton()
        : const _RecControls();
  }
}

// ── Bouton rond, même gabarit que le SOS ─────────────────────
//
// Utilisé pour Démarrer, seule commande de recording_panel.dart dont
// l'action reste un simple appui court : la bulle d'info s'y affiche sans
// conflit, contrairement à Pause/Arrêter (voir RadialRecordingControl).
class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback? onTap;

  const _RoundBtn({
    required this.icon,
    required this.color,
    required this.tooltip,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: GlassPuck(
          icon: icon,
          color: color,
          active: true,
          size: AppSizes.sosButtonSize,
          iconSize: 26,
        ),
      ),
    );
  }
}

// ── Rendu visuel d'un rond, sans geste propre ─────────────────
//
// Le geste vit au niveau du menu radial ou de _RoundBtn ; ce widget ne fait
// que dessiner le cercle, dans son état normal ou mis en avant.
class _RoundVisual extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool highlight;
  final bool scaledDown;

  const _RoundVisual({
    required this.icon,
    required this.color,
    this.highlight = false,
    this.scaledDown = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: scaledDown ? 0.85 : 1.0,
      duration: const Duration(milliseconds: 150),
      child: GlassPuck(
        icon: icon,
        color: color,
        active: highlight,
        size: AppSizes.sosButtonSize,
        iconSize: 26,
      ),
    );
  }
}

enum _RadialSegment { none, pauseResume, stop }

// ── Menu radial : pause/reprendre et arrêter ──────────────────
//
// Un appui long ouvre un grand rond avec les deux commandes ; on glisse le
// doigt sans le relever pour choisir, puis on relâche dessus. Remplace la
// pile de deux boutons ronds : la bulle d'info du bouton Arrêter ne
// s'affichait jamais, son propre appui long entrant en conflit avec celui
// que Tooltip utilise pour se révéler.
//
// Arrêter exige en plus un temps de maintien une fois le segment atteint —
// il se déclenche pendant le maintien, pas au relâcher — pour qu'un
// relâchement accidentel n'arrête jamais l'enregistrement par erreur.
// Pause/Reprendre reste instantané au relâcher.
class RadialRecordingControl extends StatefulWidget {
  final bool paused;
  final VoidCallback onTogglePause;
  final VoidCallback onStop;

  const RadialRecordingControl({
    super.key,
    required this.paused,
    required this.onTogglePause,
    required this.onStop,
  });

  @override
  State<RadialRecordingControl> createState() => _RadialRecordingControlState();
}

class _RadialRecordingControlState extends State<RadialRecordingControl> {
  // Distance du centre à chaque segment ouvert.
  static const double _radius = 78;
  // Angles depuis la verticale basse, vers la droite : les deux segments
  // restent sous et à droite du bouton, jamais au-dessus (le SOS y est) ni
  // vers la gauche (bord de l'écran).
  // Décalé vers la droite : à la main gauche, le pouce qui tient le geste
  // masque ce qui est trop proche de la verticale sous le bouton.
  static const double _angleStopDeg = 40;
  static const double _anglePauseResumeDeg = 80;
  // Rayon mort autour du point de départ avant qu'un segment soit visé.
  static const double _deadZoneRadius = 28;
  static const Duration _stopDwell = Duration(milliseconds: 550);

  bool _expanded = false;
  _RadialSegment _active = _RadialSegment.none;
  double _stopProgress = 0;
  Timer? _stopTimer;

  Offset _segmentOffset(_RadialSegment segment) {
    final deg = segment == _RadialSegment.stop ? _angleStopDeg : _anglePauseResumeDeg;
    final rad = deg * math.pi / 180;
    return Offset(_radius * math.sin(rad), _radius * math.cos(rad));
  }

  @override
  void dispose() {
    _stopTimer?.cancel();
    super.dispose();
  }

  void _onLongPressStart(LongPressStartDetails d) {
    setState(() {
      _expanded = true;
      _active = _RadialSegment.none;
      _stopProgress = 0;
    });
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails d) {
    final offset = d.offsetFromOrigin;
    _RadialSegment segment;
    if (offset.distance < _deadZoneRadius) {
      segment = _RadialSegment.none;
    } else {
      final toStop  = (offset - _segmentOffset(_RadialSegment.stop)).distance;
      final toPause = (offset - _segmentOffset(_RadialSegment.pauseResume)).distance;
      segment = toStop < toPause ? _RadialSegment.stop : _RadialSegment.pauseResume;
    }

    if (segment == _active) return;

    _stopTimer?.cancel();
    setState(() {
      _active = segment;
      _stopProgress = 0;
    });

    if (segment == _RadialSegment.stop) _armStopDwell();
  }

  // Le déclenchement se fait ICI, pendant le maintien — jamais au relâcher.
  void _armStopDwell() {
    const steps = 22;
    final stepDuration = _stopDwell ~/ steps;
    var step = 0;
    _stopTimer = Timer.periodic(stepDuration, (t) {
      step++;
      if (!mounted || _active != _RadialSegment.stop) {
        t.cancel();
        return;
      }
      setState(() => _stopProgress = step / steps);
      if (step >= steps) {
        t.cancel();
        _closeMenu();
        widget.onStop();
      }
    });
  }

  void _onLongPressEnd(LongPressEndDetails d) {
    _stopTimer?.cancel();
    final active = _active;
    _closeMenu();
    // L'arrêt se déclenche déjà pendant le maintien (_armStopDwell) : ici,
    // seul Pause/Reprendre peut encore se produire.
    if (active == _RadialSegment.pauseResume) {
      widget.onTogglePause();
    }
  }

  void _closeMenu() {
    if (!mounted) return;
    setState(() {
      _expanded = false;
      _active = _RadialSegment.none;
      _stopProgress = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final centerIcon  = widget.paused ? Icons.play_arrow : Icons.pause;
    final centerColor = widget.paused ? const Color(0xFFF9A825) : const Color(0xFFEF5350);

    return GestureDetector(
      onLongPressStart: _onLongPressStart,
      onLongPressMoveUpdate: _onLongPressMoveUpdate,
      onLongPressEnd: _onLongPressEnd,
      child: SizedBox(
        width: AppSizes.sosButtonSize,
        height: AppSizes.sosButtonSize,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (_expanded) ...[
              // Anneau indiquant la zone de glissement, centré sur le bouton.
              Positioned(
                top: AppSizes.sosButtonSize / 2 - _radius,
                left: AppSizes.sosButtonSize / 2 - _radius,
                child: Container(
                  width: _radius * 2,
                  height: _radius * 2,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(.15), width: 1.5),
                  ),
                ),
              ),
              _segment(
                offset: _segmentOffset(_RadialSegment.pauseResume),
                icon: widget.paused ? Icons.play_arrow : Icons.pause,
                color: const Color(0xFFF9A825),
                active: _active == _RadialSegment.pauseResume,
              ),
              _segment(
                offset: _segmentOffset(_RadialSegment.stop),
                icon: Icons.stop,
                color: const Color(0xFFEF5350),
                active: _active == _RadialSegment.stop,
                progress: _active == _RadialSegment.stop ? _stopProgress : null,
              ),
            ],
            _RoundVisual(icon: centerIcon, color: centerColor, highlight: true, scaledDown: _expanded),
          ],
        ),
      ),
    );
  }

  // Place un segment centré sur `offset`, relatif au centre du bouton — la
  // même formule que celle utilisée pour la détection du glissement, afin
  // que ce qui est affiché corresponde exactement à ce qui est détecté.
  Widget _segment({
    required Offset offset,
    required IconData icon,
    required Color color,
    required bool active,
    double? progress,
  }) {
    // Segment et bouton central font la même taille : positionner le coin
    // haut-gauche à `offset` aligne exactement leurs centres.
    return Positioned(
      top:  offset.dy,
      left: offset.dx,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          if (progress != null)
            SizedBox(
              width: AppSizes.sosButtonSize + 10,
              height: AppSizes.sosButtonSize + 10,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 3,
                backgroundColor: Colors.white.withOpacity(.15),
                color: Colors.white,
              ),
            ),
          _RoundVisual(icon: icon, color: color, highlight: active),
        ],
      ),
    );
  }
}

// ── Pastille de statistiques pendant l'enregistrement ────────
class _StatsPill extends StatelessWidget {
  final String texte;
  final Color bordure;
  const _StatsPill({required this.texte, required this.bordure});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 132),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.bgPanel.withOpacity(.9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: bordure, width: 1.5),
      ),
      child: Text(
        texte,
        style: const TextStyle(color: Colors.white, fontSize: 12),
        overflow: TextOverflow.ellipsis,
      ),
    );
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
    return _RoundBtn(
      icon: Icons.fiber_manual_record,
      color: const Color(0xFFEF5350),
      tooltip: 'Démarrer l\'enregistrement',
      onTap: () => _start(context),
    );
  }
}

// ── Commandes pendant l'enregistrement ───────────────────────
class _RecControls extends StatelessWidget {
  const _RecControls();

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
    final accent = paused ? const Color(0xFFF9A825) : const Color(0xFFEF5350);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Appui long, puis glisser sans relever le doigt vers Pause/Reprendre
        // ou Arrêter. Un arrêt accidentel après trois heures de sortie n'est
        // pas rattrapable : Arrêter exige un temps de maintien supplémentaire
        // une fois le segment atteint, Pause/Reprendre reste instantané.
        RadialRecordingControl(
          paused: paused,
          onTogglePause: () => context.read<RecordingProvider>().togglePause(),
          onStop: () => _stop(context),
        ),
        const SizedBox(height: 8),
        _StatsPill(
          bordure: accent,
          texte: '${stats.distanceKm.toStringAsFixed(1).replaceAll('.', ',')} km'
              ' · ${d.inHours.toString().padLeft(2, '0')}'
              ':${(d.inMinutes % 60).toString().padLeft(2, '0')}',
        ),
      ],
    );
  }
}

// ── Rappel « Toujours en balade ? » ──────────────────────────
//
// Séparé des commandes : c'est un message occasionnel, il a besoin de la
// largeur de l'écran, alors que les boutons tiennent dans une colonne.
class RecordingReminder extends StatelessWidget {
  const RecordingReminder({super.key});

  @override
  Widget build(BuildContext context) {
    final rec = context.watch<RecordingProvider>();
    if (!rec.shouldRemindPause) return const SizedBox.shrink();
    return MaterialBanner(
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
    );
  }
}
