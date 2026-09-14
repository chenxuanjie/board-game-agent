import 'package:flutter/material.dart';

import '../models/color_scheme_option.dart';
import 'app_palette.dart';

class PaletteRegistry {
  static const AppPalette classic = AppPalette(
    scheme: ColorSchemeOption.classic,
    nameZh: '默认主题',
    nameEn: 'Default Theme',
    pageBackground: Color(0xFF0B1119),
    surface: Color(0xFF121D2A),
    surfaceContainer: Color(0xFF172535),
    surfaceVariant: Color(0xFF0E1722),
    inputSurface: Color(0xFF121D2A),
    textPrimary: Color(0xFFEDF3F8),
    textSecondary: Color(0xFF8496AA),
    outline: Color(0xFF253548),
    primary: Color(0xFF72E0D1),
    primaryContainer: Color(0xFF172535),
    onPrimary: Color(0xFF06221F),
    onPrimaryContainer: Color(0xFFEDF3F8),
    secondary: Color(0xFFFF8E68),
    secondaryContainer: Color(0xFF4A2D30),
    onSecondary: Color(0xFF2D150A),
    onSecondaryContainer: Color(0xFFFFDCCF),
    success: Color(0xFF83D9A9),
    onSuccess: Color(0xFF062419),
    warning: Color(0xFFF1C979),
    onWarning: Color(0xFF2A1600),
    error: Color(0xFFFF7E88),
    onError: Color(0xFF31060A),
    focusRing: Color(0xFF5CE9EE),
    disabledForeground: Color(0xFF758198),
    disabledBackground: Color(0xFF252D3E),
    shadow: Color(0xFF000000),
  );

  static const AppPalette sunsetCoast = AppPalette(
    scheme: ColorSchemeOption.sunsetCoast,
    nameZh: '晚霞海岸',
    nameEn: 'Sunset Coast',
    pageBackground: Color(0xFFFAF6F5),
    surface: Color(0xFFFFFDFC),
    surfaceContainer: Color(0xFFF7EDEE),
    surfaceVariant: Color(0xFFEEF4F8),
    inputSurface: Color(0xFFFFFDFC),
    textPrimary: Color(0xFF3A3035),
    textSecondary: Color(0xFF7D6E75),
    outline: Color(0xFFEBDADC),
    primary: Color(0xFF7D98BA),
    primaryContainer: Color(0xFFE0EAF3),
    onPrimary: Color(0xFF1F2633),
    onPrimaryContainer: Color(0xFF293142),
    secondary: Color(0xFFDD97A6),
    secondaryContainer: Color(0xFFEECCCA),
    onSecondary: Color(0xFF3A3035),
    onSecondaryContainer: Color(0xFF3A3035),
    success: Color(0xFF497461),
    onSuccess: Color(0xFFFFFFFF),
    warning: Color(0xFF945D31),
    onWarning: Color(0xFFFFFFFF),
    error: Color(0xFF9F4D5D),
    onError: Color(0xFFFFFFFF),
    focusRing: Color(0xFF7D98BA),
    disabledForeground: Color(0xFFAA9EA3),
    disabledBackground: Color(0xFFF0E6E7),
    shadow: Color(0xFF8D747E),
  );

  /// Warm ivory, orange and walnut tones used by the V4 desktop workspace.
  static const AppPalette warmwoodStudy = AppPalette(
    scheme: ColorSchemeOption.warmwoodStudy,
    nameZh: '暖木书房',
    nameEn: 'Warmwood Study',
    pageBackground: Color(0xFFFFFCF7),
    surface: Color(0xFFFFFEFC),
    surfaceContainer: Color(0xFFFFFAF1),
    surfaceVariant: Color(0xFFF8F3EC),
    inputSurface: Color(0xFFFFFEFC),
    textPrimary: Color(0xFF171412),
    textSecondary: Color(0xFF7D756D),
    outline: Color(0xFFE8DDD2),
    primary: Color(0xFFFF6846),
    primaryContainer: Color(0xFFFFDDD4),
    onPrimary: Color(0xFF171412),
    onPrimaryContainer: Color(0xFF572012),
    secondary: Color(0xFF9B5435),
    secondaryContainer: Color(0xFFF4E4D9),
    onSecondary: Color(0xFFFFFFFF),
    onSecondaryContainer: Color(0xFF4D2919),
    success: Color(0xFF497461),
    onSuccess: Color(0xFFFFFFFF),
    warning: Color(0xFF945D31),
    onWarning: Color(0xFFFFFFFF),
    error: Color(0xFF9F4D5D),
    onError: Color(0xFFFFFFFF),
    focusRing: Color(0xFF9B5435),
    disabledForeground: Color(0xFF9B928A),
    disabledBackground: Color(0xFFF1EBE4),
    shadow: Color(0xFF5A392A),
  );

  static AppPalette of(ColorSchemeOption scheme) {
    switch (scheme) {
      case ColorSchemeOption.classic:
        return classic;
      case ColorSchemeOption.sunsetCoast:
        return sunsetCoast;
      case ColorSchemeOption.warmwoodStudy:
        return warmwoodStudy;
    }
  }
}
