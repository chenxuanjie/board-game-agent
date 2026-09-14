import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:board_game_agent/models/color_scheme_option.dart';
import 'package:board_game_agent/services/preferences_service.dart';
import 'package:board_game_agent/theme/app_palette.dart';
import 'package:board_game_agent/theme/app_theme.dart';
import 'package:board_game_agent/theme/palette_registry.dart';

void main() {
  test('all skins expose the same semantic palette contract', () {
    for (final ColorSchemeOption option in ColorSchemeOption.values) {
      final AppPalette palette = PaletteRegistry.of(option);
      expect(palette.scheme, option);
      expect(palette.pageBackground.a, greaterThan(0));
      expect(palette.surface.a, greaterThan(0));
      expect(palette.surfaceContainer.a, greaterThan(0));
      expect(palette.surfaceVariant.a, greaterThan(0));
      expect(palette.inputSurface.a, greaterThan(0));
      expect(palette.textPrimary.a, greaterThan(0));
      expect(palette.textSecondary.a, greaterThan(0));
      expect(palette.outline.a, greaterThan(0));
      expect(palette.primary.a, greaterThan(0));
      expect(palette.primaryContainer.a, greaterThan(0));
      expect(palette.secondary.a, greaterThan(0));
      expect(palette.secondaryContainer.a, greaterThan(0));
      expect(palette.success.a, greaterThan(0));
      expect(palette.warning.a, greaterThan(0));
      expect(palette.error.a, greaterThan(0));
      expect(
        _contrast(palette.primary, palette.onPrimary),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(palette.primaryContainer, palette.onPrimaryContainer),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(palette.secondary, palette.onSecondary),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(palette.secondaryContainer, palette.onSecondaryContainer),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(palette.surface, palette.textPrimary),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(palette.surfaceContainer, palette.textPrimary),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(palette.success, palette.onSuccess),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(palette.warning, palette.onWarning),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(palette.error, palette.onError),
        greaterThanOrEqualTo(4.5),
      );
    }
  });

  test('color scheme codes expose the supported themes', () {
    expect(ColorSchemeOption.classic.code, 'classic');
    expect(ColorSchemeOption.sunsetCoast.code, 'sunset_coast');
    expect(ColorSchemeOption.warmwoodStudy.code, 'warmwood_study');
    expect(
      ColorSchemeOptionX.fromCode('sunset_coast'),
      ColorSchemeOption.sunsetCoast,
    );
    expect(
      ColorSchemeOptionX.fromCode('warmwood_study'),
      ColorSchemeOption.warmwoodStudy,
    );
    expect(
      ColorSchemeOptionX.fromCode('removed_theme'),
      ColorSchemeOption.classic,
    );
  });

  test(
    'fresh installs default to sunset coast while legacy stores stay classic',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      expect(
        await PreferencesService().loadColorScheme(),
        ColorSchemeOption.sunsetCoast,
      );

      SharedPreferences.setMockInitialValues(<String, Object>{
        'app_language': 'zh',
      });
      expect(
        await PreferencesService().loadColorScheme(),
        ColorSchemeOption.classic,
      );
    },
  );

  testWidgets('existing routes receive the active palette through ThemeData', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<AppPalette> activePalette = ValueNotifier(
      PaletteRegistry.classic,
    );

    await tester.pumpWidget(
      ValueListenableBuilder<AppPalette>(
        valueListenable: activePalette,
        builder: (context, palette, _) {
          return MaterialApp(
            theme: AppTheme.buildTheme(palette),
            home: Builder(
              builder: (context) {
                final AppPalette inherited = AppPalette.of(context);
                return Scaffold(
                  body: ColoredBox(
                    key: const ValueKey<String>('theme-background'),
                    color: inherited.pageBackground,
                  ),
                );
              },
            ),
          );
        },
      ),
    );

    expect(
      tester
          .widget<ColoredBox>(
            find.byKey(const ValueKey<String>('theme-background')),
          )
          .color,
      PaletteRegistry.classic.pageBackground,
    );
    expect(
      AppTheme.buildTheme(
        PaletteRegistry.classic,
      ).bottomSheetTheme.backgroundColor,
      PaletteRegistry.classic.surface,
    );

    activePalette.value = PaletteRegistry.sunsetCoast;
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<ColoredBox>(
            find.byKey(const ValueKey<String>('theme-background')),
          )
          .color,
      PaletteRegistry.sunsetCoast.pageBackground,
    );
    expect(
      AppTheme.buildTheme(
        PaletteRegistry.sunsetCoast,
      ).bottomSheetTheme.backgroundColor,
      PaletteRegistry.sunsetCoast.surface,
    );

    activePalette.value = PaletteRegistry.warmwoodStudy;
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<ColoredBox>(
            find.byKey(const ValueKey<String>('theme-background')),
          )
          .color,
      PaletteRegistry.warmwoodStudy.pageBackground,
    );

    activePalette.dispose();
  });
}

double _contrast(Color first, Color second) {
  final double a = first.computeLuminance();
  final double b = second.computeLuminance();
  return (a > b ? a + 0.05 : b + 0.05) / (a > b ? b + 0.05 : a + 0.05);
}
