import 'package:flutter/material.dart';

// ── Palette MOTO OFFROAD 4X4 ────────────────────────────────
class AppColors {
  // Primaires
  static const Color orange     = Color(0xFFE8601C);
  static const Color darkNavy   = Color(0xFF1A1A2E);
  static const Color green      = Color(0xFF2E7D32);
  static const Color red        = Color(0xFFC62828);
  static const Color blue       = Color(0xFF1565C0);

  // Backgrounds
  static const Color bgDark     = Color(0xFF0D1117);
  static const Color bgCard     = Color(0xFF12121F);
  static const Color bgPanel    = Color(0xFF1A1A2E);
  static const Color bgSurface  = Color(0xFF1E2433);

  // Textes
  static const Color textPrimary   = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF9E9E9E);
  static const Color textMuted     = Color(0xFF555570);

  // Statuts
  static const Color statusGreen  = Color(0xFF4CAF50);
  static const Color statusOrange = Color(0xFFF57C00);
  static const Color statusRed    = Color(0xFFEF5350);

  // Overlay carte
  static const Color overlayRed    = Color(0x55EF5350); // impraticable
  static const Color overlayOrange = Color(0x44F57C00); // difficile
  static const Color traceColor   = Color(0xFFE8601C);  // trace GPX
  static const Color traceDone    = Color(0xFF4CAF50);  // portion parcourue
}

// ── Thème principal ─────────────────────────────────────────
class AppTheme {
  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      primary:   AppColors.orange,
      secondary: AppColors.green,
      error:     AppColors.red,
      surface:   AppColors.bgCard,
      onPrimary: Colors.white,
      onSurface: AppColors.textPrimary,
    ),
    scaffoldBackgroundColor: AppColors.bgDark,

    // AppBar
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bgPanel,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontFamily: 'Rajdhani',
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: AppColors.orange,
        letterSpacing: 1.2,
      ),
    ),

    // BottomNavigationBar
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.bgPanel,
      selectedItemColor: AppColors.orange,
      unselectedItemColor: AppColors.textMuted,
      selectedLabelStyle: TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
      unselectedLabelStyle: TextStyle(fontSize: 10),
      type: BottomNavigationBarType.fixed,
    ),

    // Cards
    cardTheme: CardThemeData(
      color: AppColors.bgCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF2A2A3E), width: 1),
      ),
    ),

    // ElevatedButton
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.orange,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(
          fontFamily: 'Rajdhani',
          fontSize: 16,
          fontWeight: FontWeight.w700,
          letterSpacing: .8,
        ),
      ),
    ),

    // TextButton
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.orange),
    ),

    // Divider
    dividerTheme: const DividerThemeData(
      color: Color(0xFF2A2A3E),
      thickness: 1,
      space: 1,
    ),

    // TextTheme
    textTheme: const TextTheme(
      displayLarge: TextStyle(fontFamily: 'Rajdhani', fontSize: 32, fontWeight: FontWeight.w700, color: Colors.white),
      displayMedium: TextStyle(fontFamily: 'Rajdhani', fontSize: 26, fontWeight: FontWeight.w700, color: Colors.white),
      headlineLarge: TextStyle(fontFamily: 'Rajdhani', fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white),
      headlineMedium: TextStyle(fontFamily: 'Rajdhani', fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
      titleLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
      titleMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white),
      bodyLarge: TextStyle(fontSize: 14, color: AppColors.textPrimary),
      bodyMedium: TextStyle(fontSize: 12, color: AppColors.textSecondary),
      bodySmall: TextStyle(fontSize: 11, color: AppColors.textMuted),
      labelLarge: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.orange, letterSpacing: .5),
    ),

    // InputDecoration
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.bgSurface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF2A2A3E)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF2A2A3E)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.orange, width: 1.5),
      ),
      labelStyle: const TextStyle(color: AppColors.textSecondary),
      hintStyle: const TextStyle(color: AppColors.textMuted),
    ),

    // Chip
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.bgSurface,
      selectedColor: AppColors.orange.withOpacity(.2),
      labelStyle: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
      side: const BorderSide(color: Color(0xFF2A2A3E)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  );
}

// ── Constantes de mise en page ───────────────────────────────
class AppSizes {
  static const double tabBarHeight    = 72.0;
  static const double statsBarHeight  = 56.0;
  static const double appBarHeight    = 56.0;
  static const double sosButtonSize   = 52.0;  // min 48dp pour les gants
  static const double iconButtonSize  = 48.0;
  static const double cardRadius      = 12.0;
  static const double mapSplitRatio   = 0.65;  // paysage : 65% carte
}
