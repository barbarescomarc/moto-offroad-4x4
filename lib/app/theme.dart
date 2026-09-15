import 'package:flutter/material.dart';

// ── Charte GO FREE ──────────────────────────────────────────
// Reprise littérale de la charte du site gofree.fr, direction « Minimalism
// & Swiss » : fond quasi blanc, texte ardoise, marine en primaire, vert en
// action, bleu en lien. L'app et le site doivent se reconnaître au premier
// coup d'œil — c'est la même marque.
//
// L'orange #E8601C, couleur historique de l'app, a été retiré partout :
// le site n'en porte aucune trace (décision du 2026-09-15).
class AppColors {
  // ── Jetons sémantiques, repris tels quels du site ────────
  static const Color primary          = Color(0xFF1E3A5F); // marine
  static const Color onPrimary        = Color(0xFFFFFFFF);
  static const Color secondary        = Color(0xFF2563EB); // bleu, liens
  // Le vert d'action du site : #059669 ne donnait que 3,77:1 avec du blanc
  // dessus, sous le seuil de 4,5:1 exigé pour un bouton. Le site a pris sa
  // teinte de survol comme base (5,48:1) ; on fait pareil ici.
  static const Color accent           = Color(0xFF047857); // vert
  static const Color accentHover      = Color(0xFF065F46);
  static const Color onAccent         = Color(0xFFFFFFFF);
  static const Color background       = Color(0xFFF8FAFC);
  static const Color foreground       = Color(0xFF0F172A);
  static const Color card             = Color(0xFFFFFFFF);
  static const Color muted            = Color(0xFFF1F3F5);
  static const Color mutedForeground  = Color(0xFF475569);
  static const Color border           = Color(0xFFE4E7EB);
  static const Color destructive      = Color(0xFFDC2626);
  // Texte posé sur le marine (bandeaux, en-têtes) : le site emploie ce bleu
  // très pâle pour ses lignes secondaires sur fond marine.
  static const Color onPrimaryMuted   = Color(0xFFC7D6E6);

  // ── Statuts et nuances ──────────────────────────────────
  // Ces trois-là gardent leur nom : ils disent un état, pas une couleur.
  static const Color statusGreen  = accent;
  static const Color statusOrange = Color(0xFFB45309); // ambre, pour l'alerte
  static const Color statusRed    = destructive;
  // Le gris le plus clair encore lisible sur blanc (4,76:1) : libellés
  // d'appoint, textes désactivés.
  static const Color textMuted    = Color(0xFF64748B);

  // ── Overlay carte ───────────────────────────────────────
  // Sur la carte, la couleur porte un sens et doit tenir sur l'IGN comme sur
  // la photo aérienne — c'est ce qui commande les choix ci-dessous.
  static const Color overlayRed    = Color(0x55DC2626); // impraticable
  static const Color overlayOrange = Color(0x44B45309); // difficile
  // La trace est marine, doublée du liseré blanc de traceCasing : le marine
  // seul se perd dans les zones sombres de la photo aérienne, le liseré la
  // détache de n'importe quel fond. C'est la parade cartographique classique.
  static const Color traceColor    = primary;           // trace GPX
  static const Color traceCasing   = Color(0xCCFFFFFF); // liseré de lisibilité
  static const Color traceDone     = accent;            // portion parcourue
  static const Color navRoute      = secondary;         // ruban de guidage
  // L'anneau blanc qui détache un marqueur du fond de carte. Ce n'est pas
  // une couleur de thème : c'est du contraste cartographique, et il reste
  // blanc quelle que soit la charte.
  static const Color markerCasing  = Color(0xFFFFFFFF);
}

// ── Thème principal ─────────────────────────────────────────
class AppTheme {
  static ThemeData get light => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    fontFamily: 'Inter',
    colorScheme: const ColorScheme.light(
      primary:   AppColors.primary,
      onPrimary: AppColors.onPrimary,
      secondary: AppColors.accent,
      onSecondary: AppColors.onAccent,
      error:     AppColors.destructive,
      surface:   AppColors.card,
      onSurface: AppColors.foreground,
      outline:   AppColors.border,
    ),
    scaffoldBackgroundColor: AppColors.background,

    // AppBar — le bandeau marine du site, texte blanc dessus.
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.onPrimary,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontFamily: 'Inter',
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppColors.onPrimary,
        letterSpacing: -0.2,
      ),
    ),

    // BottomNavigationBar
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.card,
      selectedItemColor: AppColors.accent,
      unselectedItemColor: AppColors.mutedForeground,
      selectedLabelStyle: TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
      unselectedLabelStyle: TextStyle(fontSize: 10),
      type: BottomNavigationBarType.fixed,
    ),

    // Cards — blanches, bordure fine, rayon 8 comme le site.
    cardTheme: CardThemeData(
      color: AppColors.card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        side: const BorderSide(color: AppColors.border, width: 1),
      ),
    ),

    // ElevatedButton — le bouton principal du site : vert, 52 px de haut.
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.onAccent,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        ),
        textStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    // TextButton
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.secondary),
    ),

    // Divider
    dividerTheme: const DividerThemeData(
      color: AppColors.border,
      thickness: 1,
      space: 1,
    ),

    // TextTheme — échelle du site : 12 / 14 / 16 / 18 / 24 / 32, titres en
    // 700 avec le resserrement de chasse qui fait sa signature.
    textTheme: const TextTheme(
      displayLarge:   TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: AppColors.foreground, letterSpacing: -0.64, height: 1.15),
      displayMedium:  TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.foreground, letterSpacing: -0.48, height: 1.15),
      headlineLarge:  TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.foreground, letterSpacing: -0.4),
      headlineMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.foreground, letterSpacing: -0.18),
      titleLarge:     TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.foreground),
      titleMedium:    TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.foreground),
      bodyLarge:      TextStyle(fontSize: 14, color: AppColors.foreground, height: 1.6),
      bodyMedium:     TextStyle(fontSize: 12, color: AppColors.mutedForeground, height: 1.6),
      bodySmall:      TextStyle(fontSize: 11, color: AppColors.mutedForeground),
      labelLarge:     TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.accent, letterSpacing: .5),
    ),

    // InputDecoration
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.card,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        borderSide: const BorderSide(color: AppColors.secondary, width: 1.5),
      ),
      labelStyle: const TextStyle(color: AppColors.mutedForeground),
      hintStyle: const TextStyle(color: AppColors.textMuted),
    ),

    // Chip
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.muted,
      selectedColor: const Color(0xFFD1FAE5), // vert très pâle, lisible
      labelStyle: const TextStyle(fontSize: 12, color: AppColors.mutedForeground),
      side: const BorderSide(color: AppColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSizes.cardRadius)),
    ),
  );
}

// ── Constantes de mise en page ───────────────────────────────
class AppSizes {
  static const double tabBarHeight    = 72.0;
  static const double statsBarHeight  = 56.0;
  static const double appBarHeight    = 56.0;
  static const double sosButtonSize   = 52.0;  // min 48dp pour les gants
  static const double iconButtonSize  = 52.0;  // aligné sur GlassPuck.size par défaut
  static const double cardRadius      = 8.0;   // le rayon du site
  static const double mapSplitRatio   = 0.65;  // paysage : 65% carte
}
