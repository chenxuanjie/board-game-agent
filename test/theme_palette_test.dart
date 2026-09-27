import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:board_game_agent/core/theme/color_scheme_option.dart';
import 'package:board_game_agent/core/localization/app_copy.dart';
import 'package:board_game_agent/core/localization/app_language.dart';
import 'package:board_game_agent/features/settings/services/preferences_service.dart';
import 'package:board_game_agent/core/theme/app_palette.dart';
import 'package:board_game_agent/core/theme/app_theme.dart';
import 'package:board_game_agent/core/theme/palette_registry.dart';

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
    expect(defaultColorScheme, ColorSchemeOption.warmwoodStudy);
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
      ColorSchemeOption.warmwoodStudy,
    );
    expect(PaletteRegistry.classic.nameZh, '夜幕棋局');
    expect(PaletteRegistry.classic.nameEn, 'Midnight Table');
    expect(
      AppCopy(AppLanguage.zhHans).colorSchemeName(ColorSchemeOption.classic),
      '夜幕棋局',
    );
    expect(
      AppCopy(AppLanguage.en).colorSchemeName(ColorSchemeOption.classic),
      'Midnight Table',
    );
  });

  test(
    'missing theme defaults to warmwood without replacing saved choices',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      expect(
        await PreferencesService().loadColorScheme(),
        ColorSchemeOption.warmwoodStudy,
      );

      SharedPreferences.setMockInitialValues(<String, Object>{
        'app_language': 'zh',
      });
      expect(
        await PreferencesService().loadColorScheme(),
        ColorSchemeOption.warmwoodStudy,
      );

      SharedPreferences.setMockInitialValues(<String, Object>{
        'color_scheme': 'classic',
      });
      expect(
        await PreferencesService().loadColorScheme(),
        ColorSchemeOption.classic,
      );

      SharedPreferences.setMockInitialValues(<String, Object>{
        'color_scheme': 'sunset_coast',
      });
      expect(
        await PreferencesService().loadColorScheme(),
        ColorSchemeOption.sunsetCoast,
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
