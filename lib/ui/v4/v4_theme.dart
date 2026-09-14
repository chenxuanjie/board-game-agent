import 'package:flutter/material.dart';

import '../../models/color_scheme_option.dart';
import '../../theme/app_palette.dart';

/// Tokens mirrored from the V4 reference's AppColors.
abstract final class V4Colors {
  static const background = Color(0xFFFFFCF7);
  static const sidebar = Color(0xFFFFFAF1);
  static const card = Color(0xFFFFFEFC);
  static const text = Color(0xFF171412);
  static const secondaryText = Color(0xFF7D756D);
  static const brown = Color(0xFF9B5435);
  static const orange = Color(0xFFFF6846);
  static const orange2 = Color(0xFFFF9A58);
  static const line = Color(0x12A76D48);
  static const soft = Color(0xFFF8F3EC);
}

/// Opt-in V4 skin. Does not change the registry or saved theme preferences.
ThemeData buildV4Theme() {
  final base = ThemeData.light(useMaterial3: true);
  final colorScheme = ColorScheme.fromSeed(
    seedColor: V4Colors.orange,
    brightness: Brightness.light,
  );
  final palette = AppPalette(
    // Compatibility metadata only: V4 is not a persisted ColorSchemeOption.
    scheme: ColorSchemeOption.sunsetCoast,
    nameZh: 'V4 暖白',
    nameEn: 'V4 Warm Light',
    pageBackground: V4Colors.background,
    surface: V4Colors.card,
    surfaceContainer: V4Colors.sidebar,
    surfaceVariant: V4Colors.soft,
    inputSurface: V4Colors.card,
    textPrimary: V4Colors.text,
    textSecondary: V4Colors.secondaryText,
    outline: V4Colors.line,
    primary: V4Colors.orange,
    primaryContainer: colorScheme.primaryContainer,
    onPrimary: V4Colors.text,
    onPrimaryContainer: colorScheme.onPrimaryContainer,
    secondary: V4Colors.brown,
    secondaryContainer: V4Colors.soft,
    onSecondary: V4Colors.card,
    onSecondaryContainer: V4Colors.text,
    // The reference has no status tokens; use readable light-surface colors.
    success: const Color(0xFF497461),
    onSuccess: Colors.white,
    warning: const Color(0xFF945D31),
    onWarning: Colors.white,
    error: colorScheme.error,
    onError: colorScheme.onError,
    focusRing: V4Colors.brown,
    disabledForeground: V4Colors.secondaryText,
    disabledBackground: V4Colors.soft,
    shadow: colorScheme.shadow,
  );
  return base.copyWith(
    scaffoldBackgroundColor: V4Colors.background,
    colorScheme: colorScheme,
    textTheme: base.textTheme.apply(
      fontFamily: 'Microsoft YaHei',
      fontFamilyFallback: const [
        'Microsoft YaHei UI',
        'Noto Sans CJK SC',
        'Segoe UI',
        'sans-serif',
      ],
      bodyColor: V4Colors.text,
      displayColor: V4Colors.text,
    ),
    extensions: <ThemeExtension<dynamic>>[AppPaletteThemeExtension(palette)],
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: Colors.transparent,
    dividerColor: V4Colors.line,
  );
}
