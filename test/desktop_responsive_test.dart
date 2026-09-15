import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';

import 'package:board_game_agent/ui/desktop/desktop_responsive.dart';

void main() {
  test('desktop layout tiers stay stable at their boundaries', () {
    expect(DesktopResponsive.desktopWindowDefaultSize, const Size(1280, 800));
    expect(DesktopResponsive.desktopWindowMinimumSize, const Size(1100, 800));
    expect(
      DesktopResponsive.desktopWindowMinimumAspectRatio,
      closeTo(1.375, 0.001),
    );

    expect(DesktopResponsive.libraryPosterWidthFor(799), 176);
    expect(DesktopResponsive.libraryPosterWidthFor(800), 184);
    expect(DesktopResponsive.libraryPosterWidthFor(1199), 184);
    expect(DesktopResponsive.libraryPosterWidthFor(1200), 192);

    expect(DesktopResponsive.settingsColumnsFor(699), 1);
    expect(DesktopResponsive.settingsColumnsFor(700), 2);
    expect(DesktopResponsive.settingsColumnsFor(1099), 2);
    expect(DesktopResponsive.settingsColumnsFor(1100), 3);

    expect(DesktopResponsive.shouldShowGamesInspector(1146), isFalse);
    expect(DesktopResponsive.shouldShowGamesInspector(1147), isTrue);

    expect(DesktopResponsive.detailHeroHeightFor(759), 320);
    expect(DesktopResponsive.detailHeroHeightFor(760), 380);
    expect(DesktopResponsive.detailHeroHeightFor(1099), 380);
    expect(DesktopResponsive.detailHeroHeightFor(1100), 450);
  });

  test('desktop page widths remain capped on super-wide windows', () {
    expect(
      DesktopResponsive.maxContentWidthFor('home'),
      DesktopResponsive.homeMaxContentWidth,
    );
    expect(
      DesktopResponsive.maxContentWidthFor('games'),
      DesktopResponsive.gamesMaxContentWidth,
    );
    expect(
      DesktopResponsive.maxContentWidthFor('settings'),
      DesktopResponsive.settingsMaxContentWidth,
    );
    expect(DesktopResponsive.homeHeroWidthFor(1200), 900);
  });
}
