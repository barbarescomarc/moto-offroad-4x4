import 'package:flutter/material.dart';
import '../app/theme.dart';
import '../services/tutorial_controller.dart';
import '../services/tutorial_steps.dart';

/// Tutoriel de première ouverture : voile sombre, projecteur sur l'élément
/// réel de l'interface, carte d'explication. Transposé du tutoriel du
/// tableau de bord de streaming (projet DRONE 31) — même forme, éprouvée à
/// l'usage : carte épinglée en bas sur téléphone, à portée du pouce.
///
/// Aucun paquet de coach marks : `Stack` et `CustomPaint` suffisent.
class TutorialOverlay extends StatelessWidget {
  const TutorialOverlay({super.key, required this.controller});

  final TutorialController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (!controller.visible) return const SizedBox.shrink();

        final step = controller.current;
        final hole = _targetRect(context, step.target);

        return Positioned.fill(
          child: Stack(
            children: [
              // ── Voile + projecteur ────────────────────────────
              // Un seul geste absorbe tout le reste de l'écran : le rider
              // ne doit jamais déplacer la carte en croyant toucher un
              // bouton du tutoriel.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: CustomPaint(
                    painter: _SpotlightPainter(hole: hole),
                    size: Size.infinite,
                  ),
                ),
              ),

              // ── Carte d'explication ────────────────────────────
              _buildCard(context, step),
            ],
          ),
        );
      },
    );
  }

  // Rectangle de l'élément réel à mettre en surbrillance, dans le même
  // repère que le canevas du voile (celui de l'overlay lui-même, pas
  // l'écran global — ils ne coïncident pas forcément, par ex. si un
  // bandeau de mise à jour pousse la carte vers le bas). Nul si la cible
  // n'a pas de clé, n'est pas montée (currentContext nul — cas normal, pas
  // une exception), ou se trouve hors écran : dans tous ces cas, l'étape
  // reste lisible, simplement sans trou dans le voile.
  Rect? _targetRect(BuildContext context, GlobalKey? key) {
    if (key == null) return null;
    try {
      final targetContext = key.currentContext;
      if (targetContext == null) return null;
      final renderObject = targetContext.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.attached) return null;

      final ancestor = context.findRenderObject();
      final topLeft = renderObject.localToGlobal(Offset.zero, ancestor: ancestor);
      final rect = topLeft & renderObject.size;

      final overlaySize = ancestor is RenderBox ? ancestor.size : MediaQuery.of(context).size;
      final overlayRect = Offset.zero & overlaySize;
      if (!overlayRect.overlaps(rect)) return null;
      return rect;
    } catch (_) {
      return null;
    }
  }

  // ── Carte « ÉTAPE n / total » ──────────────────────────────
  // Épinglée en bas, à portée du pouce, avec une hauteur maximale qui
  // laisse le pied (les boutons) toujours atteignable : la leçon déjà
  // apprise sur le tableau de bord de streaming.
  Widget _buildCard(BuildContext context, TutorialStep step) {
    final isLast = controller.index == controller.total - 1;
    return Positioned(
      left: 12,
      right: 12,
      bottom: 16,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height - 32,
        ),
        child: Material(
          color: AppColors.bgPanel,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ÉTAPE ${controller.index + 1} / ${controller.total}',
                  style: const TextStyle(
                    fontFamily: 'Rajdhani',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.orange,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  step.title,
                  style: const TextStyle(
                    fontFamily: 'Rajdhani',
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  step.body,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.35,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                _buildDots(),
                const SizedBox(height: 12),
                _buildButtons(isLast),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Pastilles de progression ───────────────────────────────
  Widget _buildDots() {
    return Row(
      children: List.generate(controller.total, (i) {
        final active = i == controller.index;
        return Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Container(
            width: active ? 18 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: active ? AppColors.orange : AppColors.textMuted,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        );
      }),
    );
  }

  // ── Commandes : Passer / Précédent / Suivant ou Terminer ✓ ─
  Widget _buildButtons(bool isLast) {
    return Row(
      children: [
        TextButton(
          key: const Key('tuto-passer'),
          onPressed: controller.skip,
          child: const Text('Passer', style: TextStyle(color: AppColors.textMuted)),
        ),
        const Spacer(),
        if (controller.index > 0)
          TextButton(
            key: const Key('tuto-precedent'),
            onPressed: controller.previous,
            child: const Text('Précédent', style: TextStyle(color: AppColors.textSecondary)),
          ),
        const SizedBox(width: 8),
        ElevatedButton(
          key: const Key('tuto-suivant'),
          onPressed: controller.next,
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.orange),
          child: Text(isLast ? 'Terminer ✓' : 'Suivant'),
        ),
      ],
    );
  }
}

// Peint le voile sombre plein écran, avec un trou rectangulaire arrondi à
// l'emplacement de la cible quand il y en a une.
class _SpotlightPainter extends CustomPainter {
  const _SpotlightPainter({required this.hole});

  final Rect? hole;

  @override
  void paint(Canvas canvas, Size size) {
    final fullScreen = Offset.zero & size;
    final veilPaint = Paint()..color = Colors.black.withOpacity(0.84);

    canvas.saveLayer(fullScreen, Paint());
    canvas.drawRect(fullScreen, veilPaint);
    if (hole != null) {
      final holeRect = hole!.inflate(8);
      final holePaint = Paint()..blendMode = BlendMode.clear;
      canvas.drawRRect(
        RRect.fromRectAndRadius(holeRect, const Radius.circular(14)),
        holePaint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) =>
      oldDelegate.hole != hole;
}
