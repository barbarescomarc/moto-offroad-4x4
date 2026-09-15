import 'package:flutter/material.dart';
import '../app/theme.dart';

// ── Bouton rond « verre dépoli » ──────────────────────────────
//
// Style visuel partagé par tous les contrôles flottants au-dessus de la
// carte (enregistrement, recentrer, radar, plein écran, recherche) —
// inspiré du Liquid Glass d'Apple : dégradé translucide, bordure fine et
// lumineuse, teinte d'accent à l'état actif plutôt qu'un remplissage plat.
//
// Un vrai flou du fond (BackdropFilter) donnerait un rendu plus proche du
// matériau original, mais appliqué à 6-8 petits boutons flottants
// au-dessus d'une carte qui se redessine sans cesse, ça pèserait sur un
// appareil d'entrée de gamme. Le dégradé seul donne l'essentiel du rendu
// pour une fraction du coût.
//
// Le verre est clair depuis la reprise de la charte du site (2026-09-15) :
// surface blanche, bordure fine, icône ardoise. Un verre sombre à icône
// blanche se lisait bien sur la photo aérienne mais jurait avec le reste de
// l'app, et se perdait sur l'IGN, qui est un fond clair.
//
// Le bouton SOS n'utilise pas ce style : rouge plein, sans transparence,
// c'est voulu — une alerte d'urgence doit rester la plus visible possible,
// jamais atténuée par un effet de matière.
class GlassPuck extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool active;
  final double size;
  final double iconSize;

  const GlassPuck({
    super.key,
    required this.icon,
    required this.color,
    this.active = false,
    this.size = 52,
    this.iconSize = 24,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.card.withValues(alpha: .96),
            // Actif : la teinte d'accent, posée sur le blanc plutôt que
            // laissée translucide — sinon la carte transparaît au travers
            // et la pastille perd son état.
            active
                ? Color.alphaBlend(color.withValues(alpha: .18), AppColors.card)
                : AppColors.card.withValues(alpha: .88),
          ],
        ),
        border: Border.all(
          color: active ? color : AppColors.border,
          width: active ? 1.6 : 1.1,
        ),
        boxShadow: [
          BoxShadow(
            color: (active ? color : AppColors.foreground)
                .withValues(alpha: active ? .28 : .12),
            blurRadius: active ? 14 : 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(icon, color: active ? color : AppColors.foreground, size: iconSize),
    );
  }
}

// ── Panneau rectangulaire « verre dépoli » ────────────────────
//
// Même matériau que GlassPuck, pour les surfaces qui regroupent du
// contenu (sections de réglages, barre de navigation) plutôt qu'un simple
// bouton rond. Le verre habille la surface ; le texte et les contrôles
// posés dessus restent nets, comme le veut le principe Apple : jamais de
// transparence sur le contenu lui-même.
class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(8),
    this.borderRadius = 16,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.card.withValues(alpha: .94),
            AppColors.card.withValues(alpha: .86),
          ],
        ),
        border: Border.all(color: AppColors.border, width: 1),
        boxShadow: [
          BoxShadow(
            color: AppColors.foreground.withValues(alpha: .12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}
