import 'package:flutter/material.dart';

import '../models/color_scheme_option.dart';

/// Semantic colors shared by every screen and every visual skin.
///
/// A page should choose a token by its visual responsibility (surface,
/// primary action, error state, and so on), never by the page it happens to
/// be rendered on. This keeps skin changes coherent across the whole app.
class AppPalette {
  const AppPalette({
    required this.scheme,
    required this.nameZh,
    required this.nameEn,
    required this.pageBackground,
    required this.surface,
    required this.surfaceContainer,
    required this.surfaceVariant,
    required this.inputSurface,
    required this.textPrimary,
    required this.textSecondary,
    required this.outline,
    required this.primary,
    required this.primaryContainer,
    required this.onPrimary,
    required this.onPrimaryContainer,
    required this.secondary,
    required this.secondaryContainer,
    required this.onSecondary,
    required this.onSecondaryContainer,
    required this.success,
    required this.onSuccess,
    required this.warning,
    required this.onWarning,
    required this.error,
    required this.onError,
    required this.focusRing,
    required this.disabledForeground,
    required this.disabledBackground,
    required this.shadow,
  });

  final ColorSchemeOption scheme;
  final String nameZh;
  final String nameEn;

  final Color pageBackground;
  final Color surface;
  final Color surfaceContainer;
  final Color surfaceVariant;
  final Color inputSurface;
  final Color textPrimary;
  final Color textSecondary;
  final Color outline;

  final Color primary;
  final Color primaryContainer;
  final Color onPrimary;
  final Color onPrimaryContainer;
  final Color secondary;
  final Color secondaryContainer;
  final Color onSecondary;
  final Color onSecondaryContainer;

  final Color success;
  final Color onSuccess;
  final Color warning;
  final Color onWarning;
  final Color error;
  final Color onError;

  final Color focusRing;
  final Color disabledForeground;
  final Color disabledBackground;
  final Color shadow;

  /// Reads the active palette from the inherited application theme.
  ///
  /// Pages should use this accessor instead of reading a controller snapshot.
  /// The theme extension is rebuilt together with [ThemeData], so existing
  /// routes also receive a palette change immediately.
  static AppPalette of(BuildContext context) {
    final AppPaletteThemeExtension? extension = Theme.of(
      context,
    ).extension<AppPaletteThemeExtension>();
    if (extension == null) {
      throw StateError('AppPaletteThemeExtension is missing from ThemeData.');
    }
    return extension.palette;
  }
}

/// ThemeData bridge for the single [AppPalette] source of truth.
///
/// This wrapper deliberately stores the palette object rather than another
/// set of colors, preventing ThemeData and AppPalette from drifting apart.
class AppPaletteThemeExtension
    extends ThemeExtension<AppPaletteThemeExtension> {
  const AppPaletteThemeExtension(this.palette);

  final AppPalette palette;

  @override
  AppPaletteThemeExtension copyWith({AppPalette? palette}) {
    return AppPaletteThemeExtension(palette ?? this.palette);
  }

  @override
  AppPaletteThemeExtension lerp(
    covariant AppPaletteThemeExtension? other,
    double t,
  ) {
    if (other == null) {
      return this;
    }
    return AppPaletteThemeExtension(t < 0.5 ? palette : other.palette);
  }
}
