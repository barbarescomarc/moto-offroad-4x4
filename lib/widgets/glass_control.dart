import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import '../app/theme.dart';

// ── Bouton rond « verre dépoli » ──────────────────────────────
//
// Style visuel partagé par tous les contrôles flottants au-dessus de la
// carte (enregistrement, recentrer, radar, plein écran, recherche) —
// inspiré du Liquid Glass d'Apple : dégradé translucide, bordure fine et
// lumineuse, teinte d'accent à l'état actif plutôt qu'un remplissage plat.
//
// Un vrai flou du fond (BackdropFilter) coûte cher : appliqué en permanence
// à sept boutons flottant au-dessus d'une carte qui se redessine sans cesse,
// il pèserait sur un appareil d'entrée de gamme. Les pastilles permanentes
// s'en passent donc, et leur dégradé en donne l'essentiel.
//
// Les segments d'un menu déplié, eux, le méritent (`verre: true`) : ils
// n'existent que le temps d'un appui, pendant lequel la carte ne bouge pas,
// et c'est précisément ce que la doctrine d'Apple appelle la couche de
// navigation — un matériau qui flotte au-dessus du contenu et échantillonne
// ce qu'il recouvre. Le flou se paie donc une demi-seconde, pas en continu.
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

  /// Le vrai matériau : le fond est flouté et teinté sous la pastille, au
  /// lieu d'être simplement recouvert. Réservé aux contrôles éphémères.
  final bool verre;

  const GlassPuck({
    super.key,
    required this.icon,
    required this.color,
    this.active = false,
    this.size = 52,
    this.iconSize = 24,
    this.verre = false,
  });

  @override
  Widget build(BuildContext context) {
    // Contraste élevé demandé : le matériau s'efface au profit d'une surface
    // pleine. Un verre translucide est le premier à devenir illisible.
    if (verre && !MediaQuery.of(context).highContrast) return _verreDepoli();
    return _pastillePleine();
  }

  /// Le matériau : on floute ce qu'il y a dessous, on le teinte à peine, et
  /// on borde d'un liseré clair — l'arête qui accroche la lumière.
  Widget _verreDepoli() => ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.card.withValues(alpha: active ? .66 : .52),
                  color.withValues(alpha: active ? .34 : .16),
                ],
              ),
              border: Border.all(
                color: active
                    ? color.withValues(alpha: .85)
                    : AppColors.card.withValues(alpha: .75),
                width: active ? 1.8 : 1.2,
              ),
            ),
            child: Icon(icon,
                color: active ? color : AppColors.foreground, size: iconSize),
          ),
        ),
      );

  Widget _pastillePleine() {
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
