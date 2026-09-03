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
    this.size = 44,
    this.iconSize = 20,
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
            Colors.white.withOpacity(active ? .18 : .12),
            (active ? color : AppColors.bgPanel).withOpacity(active ? .5 : .42),
          ],
        ),
        border: Border.all(
          color: active ? color.withOpacity(.9) : Colors.white.withOpacity(.32),
          width: active ? 1.6 : 1.1,
        ),
        boxShadow: [
          BoxShadow(
            color: (active ? color : Colors.black).withOpacity(active ? .35 : .25),
            blurRadius: active ? 10 : 6,
            spreadRadius: active ? 1 : 0,
          ),
        ],
      ),
      child: Icon(icon, color: active ? color : Colors.white, size: iconSize),
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
            Colors.white.withOpacity(.06),
            AppColors.bgPanel.withOpacity(.55),
          ],
        ),
        border: Border.all(color: Colors.white.withOpacity(.14), width: 1),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(.25), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: child,
    );
  }
}
