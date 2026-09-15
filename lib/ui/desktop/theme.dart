import 'package:flutter/material.dart';

import '../../theme/app_palette.dart';
import '../../theme/palette_registry.dart';

/// Design tokens for the Warmwood Study desktop theme.
abstract final class DesktopColors {
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

/// Desktop presentation for the persisted Warmwood Study theme.
ThemeData buildDesktopTheme() {
  final base = ThemeData.light(useMaterial3: true);
  final colorScheme = ColorScheme.fromSeed(
    seedColor: DesktopColors.orange,
    brightness: Brightness.light,
  );
  const palette = PaletteRegistry.warmwoodStudy;
  return base.copyWith(
    scaffoldBackgroundColor: DesktopColors.background,
    colorScheme: colorScheme,
    textTheme: base.textTheme.apply(
      fontFamily: 'Microsoft YaHei',
      fontFamilyFallback: const [
        'Microsoft YaHei UI',
        'Noto Sans CJK SC',
        'Segoe UI',
        'sans-serif',
      ],
      bodyColor: DesktopColors.text,
      displayColor: DesktopColors.text,
    ),
    extensions: <ThemeExtension<dynamic>>[AppPaletteThemeExtension(palette)],
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: Colors.transparent,
    dividerColor: DesktopColors.line,
  );
}
