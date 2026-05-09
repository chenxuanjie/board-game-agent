import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_palette.dart';

class AppTheme {
  static const Color parchment = Color(0xFFF5E7D3);
  static const Color sand = Color(0xFFE7D5BC);
  static const Color ink = Color(0xFF1E241F);
  static const Color cedar = Color(0xFF7E4A2F);
  static const Color teal = Color(0xFF184C54);
  static const Color moss = Color(0xFF5E6D4E);
  static const Color cream = Color(0xFFFBF6EE);

  static ThemeData buildTheme(AppPalette palette) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: palette.accentPrimary,
        brightness: Brightness.light,
        primary: palette.accentPrimary,
        secondary: palette.accentSecondary,
        surface: palette.cardSurface,
      ),
    );

    final bodyTextTheme = GoogleFonts.manropeTextTheme(base.textTheme);

    return base.copyWith(
      scaffoldBackgroundColor: palette.scaffoldBackground,
      textTheme: bodyTextTheme.copyWith(
        displayLarge: GoogleFonts.cormorantGaramond(
          fontSize: 44,
          fontWeight: FontWeight.w700,
          color: palette.homeTextPrimary,
        ),
        displayMedium: GoogleFonts.cormorantGaramond(
          fontSize: 34,
          fontWeight: FontWeight.w700,
          color: palette.homeTextPrimary,
        ),
        headlineMedium: GoogleFonts.cormorantGaramond(
          fontSize: 30,
          fontWeight: FontWeight.w700,
          color: palette.homeTextPrimary,
        ),
        titleLarge: GoogleFonts.manrope(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: palette.homeTextPrimary,
        ),
        titleMedium: GoogleFonts.manrope(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: palette.homeTextPrimary,
        ),
        bodyLarge: GoogleFonts.manrope(
          fontSize: 16,
          height: 1.45,
          color: palette.homeTextPrimary,
        ),
        bodyMedium: GoogleFonts.manrope(
          fontSize: 14,
          height: 1.45,
          color: palette.homeTextPrimary.withValues(alpha: 0.86),
        ),
        labelLarge: GoogleFonts.manrope(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: palette.homeTextPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.manrope(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: palette.homeTextPrimary,
        ),
      ),
      cardTheme: CardThemeData(
        color: palette.cardSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(
            color: palette.cardBorder,
          ),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        backgroundColor: palette.accentSecondary.withValues(alpha: 0.22),
        selectedColor: palette.accentPrimary.withValues(alpha: 0.12),
        side: BorderSide.none,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.inputFill,
        hintStyle: GoogleFonts.manrope(
          color: palette.homeTextPrimary.withValues(alpha: 0.45),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide(
            color: palette.cardBorder,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide(
            color: palette.accentPrimary,
            width: 1.4,
          ),
        ),
      ),
    );
  }
}
