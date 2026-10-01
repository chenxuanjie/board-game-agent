import 'package:flutter/material.dart';

import 'app_palette.dart';
import 'ui_tokens.dart';

class AppTheme {
  static ThemeData buildTheme(AppPalette palette) {
    final Brightness brightness = ThemeData.estimateBrightnessForColor(
      palette.pageBackground,
    );
    final ColorScheme colorScheme = ColorScheme(
      brightness: brightness,
      primary: palette.primary,
      onPrimary: palette.onPrimary,
      primaryContainer: palette.primaryContainer,
      onPrimaryContainer: palette.onPrimaryContainer,
      secondary: palette.secondary,
      onSecondary: palette.onSecondary,
      secondaryContainer: palette.secondaryContainer,
      onSecondaryContainer: palette.onSecondaryContainer,
      tertiary: palette.secondary,
      onTertiary: palette.onSecondary,
      tertiaryContainer: palette.secondaryContainer,
      onTertiaryContainer: palette.onSecondaryContainer,
      error: palette.error,
      onError: palette.onError,
      errorContainer: palette.error.withValues(alpha: 0.16),
      onErrorContainer: palette.error,
      surface: palette.surface,
      onSurface: palette.textPrimary,
      surfaceDim: palette.pageBackground,
      surfaceBright: palette.surface,
      surfaceContainerLowest: palette.pageBackground,
      surfaceContainerLow: palette.surface,
      surfaceContainer: palette.surfaceContainer,
      surfaceContainerHigh: palette.surfaceVariant,
      surfaceContainerHighest: palette.surfaceVariant,
      onSurfaceVariant: palette.textSecondary,
      outline: palette.outline,
      outlineVariant: palette.outline.withValues(alpha: 0.62),
      shadow: palette.shadow,
      scrim: palette.shadow.withValues(alpha: 0.56),
      inverseSurface: palette.textPrimary,
      onInverseSurface: palette.pageBackground,
      inversePrimary: palette.primaryContainer,
      surfaceTint: palette.primary,
    );

    final ThemeData base = ThemeData(
      useMaterial3: true,
      fontFamily: 'Noto Sans SC',
      fontFamilyFallback: const ['Segoe UI Emoji'],
      brightness: brightness,
      colorScheme: colorScheme,
      extensions: <ThemeExtension<dynamic>>[AppPaletteThemeExtension(palette)],
      scaffoldBackgroundColor: palette.pageBackground,
      canvasColor: palette.pageBackground,
      cardColor: palette.surface,
      dividerColor: palette.outline.withValues(alpha: 0.7),
      splashColor: palette.primary.withValues(alpha: 0.12),
      highlightColor: palette.primary.withValues(alpha: 0.08),
    );
    final TextTheme bodyTextTheme = base.textTheme;

    return base.copyWith(
      textTheme: bodyTextTheme.copyWith(
        displayLarge: TextStyle(
          fontFamily: 'Noto Sans SC',
          fontSize: 44,
          fontWeight: FontWeight.w700,
          color: palette.textPrimary,
        ),
        displayMedium: TextStyle(
          fontFamily: 'Noto Sans SC',
          fontSize: 34,
          fontWeight: FontWeight.w700,
          color: palette.textPrimary,
        ),
        headlineMedium: TextStyle(
          fontFamily: 'Noto Sans SC',
          fontSize: 30,
          fontWeight: FontWeight.w700,
          color: palette.textPrimary,
        ),
        titleLarge: TextStyle(
          fontFamily: 'Noto Sans SC',
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: palette.textPrimary,
        ),
        titleMedium: TextStyle(
          fontFamily: 'Noto Sans SC',
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: palette.textPrimary,
        ),
        bodyLarge: TextStyle(
          fontFamily: 'Noto Sans SC',
          fontSize: 16,
          height: 1.45,
          color: palette.textPrimary,
        ),
        bodyMedium: TextStyle(
          fontFamily: 'Noto Sans SC',
          fontSize: 14,
          height: 1.45,
          color: palette.textSecondary,
        ),
        bodySmall: TextStyle(
          fontFamily: 'Noto Sans SC',
          fontSize: 12,
          height: 1.4,
          color: palette.textSecondary,
        ),
        labelLarge: TextStyle(
          fontFamily: 'Noto Sans SC',
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
          color: palette.textPrimary,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: palette.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Noto Sans SC',
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: palette.textPrimary,
        ),
      ),
      cardTheme: CardThemeData(
        color: palette.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(UiTokens.cardRadius),
          side: BorderSide(color: palette.outline),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          side: BorderSide(color: palette.outline),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        labelStyle: TextStyle(
          fontFamily: 'Noto Sans SC',
          color: palette.onSecondaryContainer,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: palette.secondaryContainer,
        selectedColor: palette.primaryContainer,
        side: BorderSide.none,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.inputSurface,
        hintStyle: TextStyle(
          fontFamily: 'Noto Sans SC',
          color: palette.textSecondary,
        ),
        labelStyle: TextStyle(
          fontFamily: 'Noto Sans SC',
          color: palette.textSecondary,
        ),
        prefixIconColor: palette.textSecondary,
        suffixIconColor: palette.textSecondary,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(UiTokens.controlRadius),
          borderSide: BorderSide(color: palette.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(UiTokens.controlRadius),
          borderSide: BorderSide(color: palette.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(UiTokens.controlRadius),
          borderSide: BorderSide(color: palette.focusRing, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(UiTokens.controlRadius),
          borderSide: BorderSide(color: palette.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(UiTokens.controlRadius),
          borderSide: BorderSide(color: palette.error, width: 1.6),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll<Color>(palette.surface),
          surfaceTintColor: const WidgetStatePropertyAll<Color>(
            Colors.transparent,
          ),
          side: WidgetStatePropertyAll<BorderSide>(
            BorderSide(color: palette.outline),
          ),
        ),
        textStyle: TextStyle(
          fontFamily: 'Noto Sans SC',
          color: palette.textPrimary,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(UiTokens.groupRadius),
          side: BorderSide(color: palette.outline),
        ),
        titleTextStyle: TextStyle(
          fontFamily: 'Noto Sans SC',
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: palette.textPrimary,
        ),
        contentTextStyle: TextStyle(
          fontFamily: 'Noto Sans SC',
          fontSize: 15,
          height: 1.5,
          color: palette.textPrimary,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: palette.surfaceContainer,
        contentTextStyle: TextStyle(
          fontFamily: 'Noto Sans SC',
          color: palette.textPrimary,
          fontWeight: FontWeight.w700,
        ),
        actionTextColor: palette.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: palette.primary,
          textStyle: TextStyle(
            fontFamily: 'Noto Sans SC',
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.primary,
          minimumSize: const Size(48, 48),
          side: BorderSide(color: palette.primary),
          textStyle: TextStyle(
            fontFamily: 'Noto Sans SC',
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(UiTokens.controlRadius),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.primary,
          foregroundColor: palette.onPrimary,
          minimumSize: const Size(48, 48),
          textStyle: TextStyle(
            fontFamily: 'Noto Sans SC',
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(UiTokens.controlRadius),
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color?>(
          (states) => states.contains(WidgetState.selected)
              ? palette.onPrimary
              : palette.disabledForeground,
        ),
        trackColor: WidgetStateProperty.resolveWith<Color?>(
          (states) => states.contains(WidgetState.selected)
              ? palette.primary
              : palette.disabledBackground,
        ),
        trackOutlineColor: WidgetStatePropertyAll<Color>(palette.outline),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: palette.primary,
        circularTrackColor: palette.primary.withValues(alpha: 0.18),
        linearTrackColor: palette.primary.withValues(alpha: 0.18),
      ),
      iconTheme: IconThemeData(color: palette.textPrimary),
    );
  }
}
