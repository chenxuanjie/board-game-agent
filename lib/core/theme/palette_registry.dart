import 'package:flutter/material.dart';

import 'color_scheme_option.dart';
import 'app_palette.dart';

class PaletteRegistry {
  static const AppPalette classic = AppPalette(
    scheme: ColorSchemeOption.classic,
    nameZh: '夜幕棋局',
    nameEn: 'Midnight Table',
    pageBackground: Color(0xFF0B1119),
    surface: Color(0xFF121D2A),
    surfaceContainer: Color(0xFF172535),
    surfaceVariant: Color(0xFF0E1722),
    inputSurface: Color(0xFF121D2A),
    textPrimary: Color(0xFFEDF3F8),
    textSecondary: Color(0xFF8496AA),
    outline: Color(0xFF3B5068),
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

  /// V5 Cinema foundation. Materials and composition use the separate design spec.
  static const AppPalette cinema = AppPalette(
    scheme: ColorSchemeOption.cinema,
    nameZh: '影院',
    nameEn: 'Cinema',
    pageBackground: Color(0xFF0E1015),
    surface: Color(0xFF171A21),
    surfaceContainer: Color(0xFF20242D),
    surfaceVariant: Color(0xFF262B35),
    inputSurface: Color(0xFF1B2029),
    textPrimary: Color(0xFFF6F2EC),
    textSecondary: Color(0xFFB7B8C2),
    outline: Color(0xFF737B8A),
    primary: Color(0xFFFF6B5D),
    primaryContainer: Color(0xFF422725),
    onPrimary: Color(0xFF191111),
    onPrimaryContainer: Color(0xFFFFE4DF),
    secondary: Color(0xFFB7B8C2),
    secondaryContainer: Color(0xFF262B35),
    onSecondary: Color(0xFF171A21),
    onSecondaryContainer: Color(0xFFF6F2EC),
    success: Color(0xFF73D5A3),
    onSuccess: Color(0xFF092219),
    warning: Color(0xFFF2C46D),
    onWarning: Color(0xFF2B1E09),
    error: Color(0xFFFF8B9A),
    onError: Color(0xFF310F18),
    focusRing: Color(0xFFFFF1CA),
    disabledForeground: Color(0xFF717786),
    disabledBackground: Color(0xFF252932),
    shadow: Color(0xFF000000),
  );

  /// The prototype's warm grey/green surfaces; its layout is a separate shell.
  static const AppPalette spatialCinema = AppPalette(
    scheme: ColorSchemeOption.spatialCinema,
    nameZh: '空间影院',
    nameEn: 'Spatial Cinema',
    pageBackground: Color(0xFF080907),
    surface: Color(0xFF161813),
    surfaceContainer: Color(0xFF2C2A22),
    surfaceVariant: Color(0xFF24261D),
    inputSurface: Color(0xFF232720),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFB8BEAE),
    outline: Color(0xFF788D6A),
    primary: Color(0xFFE50914),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFF481015),
    onPrimaryContainer: Color(0xFFFFE6E6),
    secondary: Color(0xFFC9D7B5),
    onSecondary: Color(0xFF13180F),
    secondaryContainer: Color(0xFF333C29),
    onSecondaryContainer: Color(0xFFF4FFE8),
    success: Color(0xFF91C185),
    onSuccess: Color(0xFF12200C),
    warning: Color(0xFFEFC487),
    onWarning: Color(0xFF281B09),
    error: Color(0xFFFFA3A8),
    onError: Color(0xFF300D10),
    focusRing: Color(0xFFD9E9C1),
    disabledForeground: Color(0xFF7C8274),
    disabledBackground: Color(0xFF303329),
    shadow: Color(0xFF000000),
  );

  /// Warm ivory, orange and walnut tones used by the desktop workspace.
  static const AppPalette warmwoodStudy = AppPalette(
    scheme: ColorSchemeOption.warmwoodStudy,
    nameZh: '暖木书房',
    nameEn: 'Warmwood Study',
    pageBackground: Color(0xFFFFFCF7),
    surface: Color(0xFFFFFEFC),
    surfaceContainer: Color(0xFFF5EBDD),
    surfaceVariant: Color(0xFFF1E6D9),
    inputSurface: Color(0xFFFFFEFC),
    textPrimary: Color(0xFF171412),
    textSecondary: Color(0xFF6E655D),
    outline: Color(0xFFDBC5AF),
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
      case ColorSchemeOption.cinema:
        return cinema;
      case ColorSchemeOption.spatialCinema:
        return spatialCinema;
      case ColorSchemeOption.warmwoodStudy:
        return warmwoodStudy;
    }
  }
}
