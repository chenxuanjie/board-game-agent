import 'package:flutter/material.dart';

import '../models/color_scheme_option.dart';
import 'app_palette.dart';

class PaletteRegistry {
  static const AppPalette classic = AppPalette(
    scheme: ColorSchemeOption.classic,
    nameZh: '默认深色',
    nameEn: 'Classic Dark',
    scaffoldBackground: Color(0xFF10192B),
    primaryGradient: <Color>[
      Color(0xFF111C31),
      Color(0xFF0D1630),
      Color(0xFF091120),
    ],
    homeSurface: Color(0xFF15203A),
    homeSearchBackground: Color(0xFF1E2A44),
    homeSearchHint: Colors.white38,
    homeTextPrimary: Colors.white,
    homeTextSecondary: Colors.white70,
    cardSurface: Color(0xFF1B2438),
    cardBorder: Color(0x14FFFFFF),
    cardShadow: Color(0x33000000),
    aiPrimary: Color(0xFF132B25),
    aiSecondary: Color(0xFF1F6C55),
    accentPrimary: Color(0xFF23D2D8),
    accentSecondary: Color(0xFFFF8E68),
    rankChip: Color(0xFFFF8E68),
    detailSurface: Color(0xFF171F32),
    detailOverlayTop: Color(0x8C000000),
    detailOverlayMid: Color(0xD1111827),
    detailOverlayBottom: Color(0xFF111827),
    buttonOutline: Color(0xFF23D2D8),
    buttonFill: Color(0xFF23D2D8),
    buttonText: Color(0xFF23D2D8),
    inputFill: Color(0xFFFBF6EE),
    messageUserBubble: Color(0xFF184C54),
    messageAssistantBubble: Color(0xFFFBF6EE),
    messageAssistantText: Color(0xFF1E241F),
    splashBackground: Color(0xFF0F172A),
  );

  static const AppPalette gradientBluePink = AppPalette(
    scheme: ColorSchemeOption.gradientBluePink,
    nameZh: '高级渐变',
    nameEn: 'Advanced Gradient',
    scaffoldBackground: Color(0xFFE5E5F3),
    primaryGradient: <Color>[
      Color(0xFFF3CCDB),
      Color(0xFFE5E5F3),
      Color(0xFFA8D1E1),
      Color(0xFF62A9C8),
      Color(0xFF147EBC),
    ],
    homeSurface: Color(0xF9FFFFFF),
    homeSearchBackground: Color(0xEFFFFFFF),
    homeSearchHint: Color(0xFF8AA8BA),
    homeTextPrimary: Color(0xFF1C587E),
    homeTextSecondary: Color(0xFF5C8EAA),
    cardSurface: Color(0xF9FFFFFF),
    cardBorder: Color(0x22FFFFFF),
    cardShadow: Color(0x2262A9C8),
    aiPrimary: Color(0xFFA8D1E1),
    aiSecondary: Color(0xFF62A9C8),
    accentPrimary: Color(0xFF147EBC),
    accentSecondary: Color(0xFFF3CCDB),
    rankChip: Color(0xFFF3CCDB),
    detailSurface: Color(0xF9FFFFFF),
    detailOverlayTop: Color(0x554A93BE),
    detailOverlayMid: Color(0xCCCEE6F0),
    detailOverlayBottom: Color(0xFFE5E5F3),
    buttonOutline: Color(0xFF147EBC),
    buttonFill: Color(0xFF147EBC),
    buttonText: Color(0xFF147EBC),
    inputFill: Color(0xFFFFFFFF),
    messageUserBubble: Color(0xFF62A9C8),
    messageAssistantBubble: Color(0xFFFFFFFF),
    messageAssistantText: Color(0xFF245677),
    splashBackground: Color(0xFFE5E5F3),
  );

  static AppPalette of(ColorSchemeOption scheme) {
    switch (scheme) {
      case ColorSchemeOption.gradientBluePink:
        return gradientBluePink;
      case ColorSchemeOption.classic:
        return classic;
    }
  }
}
