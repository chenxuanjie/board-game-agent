import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Shared responsive decisions for the desktop V4 shell.
///
/// These values describe layout tiers, not device pixel sizes. Keeping them in
/// one place prevents each pane from making a slightly different breakpoint
/// decision when the window is resized.
abstract final class DesktopResponsive {
  static const narrowBreakpoint = 760.0;
  static const fullSidebarBreakpoint = 1200.0;

  /// The inspector needs enough room for both the poster grid and its panel.
  /// This is intentionally independent from the sidebar breakpoint.
  static const gamesInspectorBreakpoint = 1147.0;

  static const homeTwoColumnBreakpoint = 900.0;
  static const settingsTwoColumnBreakpoint = 700.0;
  static const settingsThreeColumnBreakpoint = 1100.0;

  static const homeMaxContentWidth = 1480.0;
  static const gamesMaxContentWidth = 1500.0;
  static const settingsMaxContentWidth = 1400.0;

  static const homeHeroMaxWidth = 900.0;

  static bool isNarrow(double width) => width < narrowBreakpoint;

  static bool usesFullSidebar(double width) => width >= fullSidebarBreakpoint;

  static bool usesCompactSidebar(double width) =>
      width >= narrowBreakpoint && width < fullSidebarBreakpoint;

  static bool shouldShowGamesInspector(double width) =>
      width >= gamesInspectorBreakpoint;

  /// The poster width changes in deliberate steps so resizing does not make
  /// every card continuously stretch and shrink.
  static double libraryPosterWidthFor(double width) {
    if (width < 800) return 176;
    if (width < 1200) return 184;
    return 192;
  }

  static int settingsColumnsFor(double width) {
    if (width < settingsTwoColumnBreakpoint) return 1;
    if (width < settingsThreeColumnBreakpoint) return 2;
    return 3;
  }

  static bool homeUsesTwoColumns(double width) =>
      width >= homeTwoColumnBreakpoint;

  static double homeHeroWidthFor(double width) =>
      math.min(width, homeHeroMaxWidth);

  static double homeRecommendationCardWidthFor(double width) =>
      math.min(width, 140);

  static double detailHeroHeightFor(double width) {
    if (width < narrowBreakpoint) return 320;
    if (width < 1100) return 380;
    return 450;
  }

  static double maxContentWidthFor(String page) => switch (page) {
    'home' => homeMaxContentWidth,
    'games' || 'favorites' => gamesMaxContentWidth,
    'settings' => settingsMaxContentWidth,
    'gameDetail' => gamesMaxContentWidth,
    _ => gamesMaxContentWidth,
  };
}

/// Centers a page at very wide sizes while preserving the existing edge
/// padding at normal and narrow sizes.
class DesktopResponsiveFrame extends StatelessWidget {
  const DesktopResponsiveFrame({
    super.key,
    required this.maxWidth,
    required this.padding,
    required this.child,
  });

  final double maxWidth;
  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = math.min(constraints.maxWidth, maxWidth);
      return Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: width,
          child: Padding(padding: padding, child: child),
        ),
      );
    },
  );
}
