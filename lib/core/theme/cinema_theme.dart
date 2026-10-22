import 'package:flutter/material.dart';
import 'app_palette.dart';
import 'color_scheme_option.dart';

bool isCinema(BuildContext context) =>
    Theme.of(context).extension<AppPaletteThemeExtension>()?.palette.scheme ==
    ColorSchemeOption.cinema;

class CinemaMaterialTheme extends ThemeExtension<CinemaMaterialTheme> {
  const CinemaMaterialTheme({this.glassEnabled = true});
  final bool glassEnabled;
  @override
  CinemaMaterialTheme copyWith({bool? glassEnabled}) =>
      CinemaMaterialTheme(glassEnabled: glassEnabled ?? this.glassEnabled);
  @override
  CinemaMaterialTheme lerp(covariant CinemaMaterialTheme? other, double t) =>
      t < .5 ? this : other ?? this;
}

ThemeData cinemaTheme(ThemeData base, {required bool glassEnabled}) {
  final palette = base.extension<AppPaletteThemeExtension>()!.palette;
  return base.copyWith(
    extensions: [
      ...base.extensions.values,
      CinemaMaterialTheme(glassEnabled: glassEnabled),
    ],
    textTheme: base.textTheme.copyWith(
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontSize: 28,
        height: 1.25,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontSize: 20,
        height: 1.3,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.3,
      ),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 16, height: 1.55),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(
        fontSize: 14,
        height: 1.45,
      ),
      bodySmall: base.textTheme.bodySmall?.copyWith(fontSize: 12, height: 1.4),
    ),
    popupMenuTheme: base.popupMenuTheme.copyWith(
      color: palette.surfaceContainer.withValues(alpha: glassEnabled ? .94 : 1),
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dialogTheme: base.dialogTheme.copyWith(
      backgroundColor: palette.surfaceContainer,
    ),
    bottomSheetTheme: base.bottomSheetTheme.copyWith(
      backgroundColor: palette.surface,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: palette.primary,
        foregroundColor: palette.onPrimary,
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.textPrimary,
        side: BorderSide(color: palette.outline),
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    focusColor: palette.focusRing.withValues(alpha: .12),
  );
}
