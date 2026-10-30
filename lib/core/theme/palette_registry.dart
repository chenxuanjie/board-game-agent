import 'package:flutter/material.dart';

import 'color_scheme_option.dart';
import 'app_palette.dart';

class PaletteRegistry {
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
      case ColorSchemeOption.spatialCinema:
        return spatialCinema;
      case ColorSchemeOption.warmwoodStudy:
        return warmwoodStudy;
    }
  }
}
