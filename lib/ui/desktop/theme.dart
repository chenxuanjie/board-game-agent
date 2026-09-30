import 'package:flutter/material.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/palette_registry.dart';

/// Design tokens for the Warmwood Study desktop theme.
abstract final class DesktopColors {
  static const background = Color(0xFFFFFCF7);
  // Continue the castle artwork's warm paper color through the entire sidebar.
  static const sidebar = Color(0xFFFCF3E2);
  static const card = Color(0xFFFFFEFC);
  static const text = Color(0xFF171412);
  static const secondaryText = Color(0xFF7D756D);
  static const brown = Color(0xFF9B5435);
  static const orange = Color(0xFFFF6846);
  static const orange2 = Color(0xFFFF9A58);
  static const line = Color(0x12A76D48);
  static const soft = Color(0xFFF8F3EC);
}

/// Desktop presentation for the persisted Warmwood Study theme.
ThemeData buildDesktopTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: DesktopColors.orange,
    brightness: Brightness.light,
  );
  const palette = PaletteRegistry.warmwoodStudy;
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    fontFamily: 'Noto Sans SC',
    fontFamilyFallback: const ['Segoe UI Emoji'],
  );
  OutlineInputBorder inputBorder(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: width),
      );
  return base.copyWith(
    scaffoldBackgroundColor: DesktopColors.background,
    colorScheme: colorScheme,
    textTheme: base.textTheme.apply(
      fontFamily: 'Noto Sans SC',
      fontFamilyFallback: const ['Segoe UI Emoji'],
      bodyColor: DesktopColors.text,
      displayColor: DesktopColors.text,
    ),
    primaryTextTheme: base.primaryTextTheme.apply(
      fontFamily: 'Noto Sans SC',
      fontFamilyFallback: const ['Segoe UI Emoji'],
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: DesktopColors.soft,
      hintStyle: base.textTheme.bodyMedium?.copyWith(
        color: DesktopColors.secondaryText,
      ),
      labelStyle: base.textTheme.bodyMedium?.copyWith(
        color: DesktopColors.secondaryText,
      ),
      prefixIconColor: DesktopColors.secondaryText,
      suffixIconColor: DesktopColors.secondaryText,
      border: inputBorder(DesktopColors.line),
      enabledBorder: inputBorder(DesktopColors.line),
      disabledBorder: inputBorder(DesktopColors.line),
      focusedBorder: inputBorder(DesktopColors.orange, 1.2),
      errorBorder: inputBorder(colorScheme.error),
      focusedErrorBorder: inputBorder(colorScheme.error, 1.2),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: DesktopColors.card,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(DesktopColors.card),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: const Color(0xFF3F3934),
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: base.textTheme.bodySmall?.copyWith(color: Colors.white),
      waitDuration: const Duration(milliseconds: 350),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      contentTextStyle: base.textTheme.bodyMedium?.copyWith(
        color: Colors.white,
      ),
    ),
    extensions: <ThemeExtension<dynamic>>[AppPaletteThemeExtension(palette)],
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: Colors.transparent,
    dividerColor: DesktopColors.line,
  );
}
