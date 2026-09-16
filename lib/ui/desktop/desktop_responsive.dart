import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Shared responsive decisions for the desktop V4 shell.
///
/// These values describe layout tiers, not device pixel sizes. Keeping them in
/// one place prevents each pane from making a slightly different breakpoint
/// decision when the window is resized.
abstract final class DesktopResponsive {
  static const Size desktopWindowDefaultSize = Size(1280, 800);
  static const double desktopWindowMinimumWidth = 1100;
  static const double desktopWindowMinimumHeight = 800;
  static const Size desktopWindowMinimumSize = Size(
    desktopWindowMinimumWidth,
    desktopWindowMinimumHeight,
  );
  static const double desktopWindowMinimumAspectRatio =
      desktopWindowMinimumWidth / desktopWindowMinimumHeight;

  static const narrowBreakpoint = 760.0;
  static const fullSidebarBreakpoint = 1200.0;
  static const fullSidebarWidth = 205.0;
  static const compactSidebarWidth = 76.0;

  /// The inspector needs enough room for both the poster grid and its panel.
  /// This is intentionally independent from the sidebar breakpoint.
  static const gamesInspectorBreakpoint = 1147.0;

  static const homeTwoColumnBreakpoint = 900.0;
  static const settingsTwoColumnBreakpoint = 700.0;
  static const settingsThreeColumnBreakpoint = 1100.0;

  static const homeMaxContentWidth = 1480.0;
  static const gamesMaxContentWidth = 1500.0;
  static const settingsMaxContentWidth = 1400.0;

  static const double desktopMinimumScale = 1.0;
  static const double desktopMaximumScale = 1.35;

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

  /// Wide windows can use more of the available canvas. The hero no longer
  /// has an independent cap, so it aligns with the rest of the home column.
  static double homeHeroWidthFor(double width) => width;

  static int homeRecommendationCountFor(double width) => width >= 1000 ? 6 : 5;

  static double homeRecommendationCardWidthFor(
    double width, {
    double gap = 13,
    double minimumWidth = 140,
    int count = 5,
  }) => math.max(minimumWidth, (width - gap * (count - 1)) / count);

  /// Dashboard/gallery pages should use the available desktop window width.
  ///
  /// Reading/form pages such as Settings remain centered and width-limited.
  static bool usesFluidPageWidth(String page) => switch (page) {
    'home' || 'games' || 'favorites' || 'gameDetail' => true,
    _ => false,
  };

  /// Returns the scale for the desktop design canvas.
  ///
  /// The design baseline remains unchanged below 1280x800. Those windows use
  /// the existing compact-sidebar/drawer reflow instead of shrinking text and
  /// hit targets. Larger windows scale from the same baseline and are capped
  /// to keep very wide monitors from producing oversized controls.
  static double desktopScaleFor(Size viewport) {
    if (viewport.width < desktopWindowDefaultSize.width ||
        viewport.height < desktopWindowDefaultSize.height) {
      return desktopMinimumScale;
    }
    return math
        .min(
          viewport.width / desktopWindowDefaultSize.width,
          viewport.height / desktopWindowDefaultSize.height,
        )
        .clamp(desktopMinimumScale, desktopMaximumScale)
        .toDouble();
  }

  static DesktopMetrics metricsFor(Size viewport) =>
      DesktopMetrics(viewportSize: viewport, scale: desktopScaleFor(viewport));

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

/// Metrics shared by the desktop shell and its panes.
///
/// `scale` is intentionally only applied to the wide desktop canvas. It is
/// not a widget transform: text remains accessible and hit targets keep their
/// normal Flutter semantics while the design dimensions grow together.
class DesktopMetrics {
  const DesktopMetrics({required this.viewportSize, required this.scale});

  final Size viewportSize;
  final double scale;

  double px(double value) => value * scale;

  double font(double value) => value * (1 + (scale - 1) * 0.75);

  double radius(double value) =>
      (value * scale).clamp(value, value * 1.2).toDouble();

  EdgeInsets insets(EdgeInsets value) => EdgeInsets.fromLTRB(
    px(value.left),
    px(value.top),
    px(value.right),
    px(value.bottom),
  );
}

class DesktopMetricsScope extends InheritedWidget {
  const DesktopMetricsScope({
    super.key,
    required this.metrics,
    required super.child,
  });

  final DesktopMetrics metrics;

  static DesktopMetrics? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<DesktopMetricsScope>()
      ?.metrics;

  static DesktopMetrics of(BuildContext context) =>
      maybeOf(context) ??
      DesktopResponsive.metricsFor(
        MediaQuery.maybeOf(context)?.size ??
            DesktopResponsive.desktopWindowDefaultSize,
      );

  @override
  bool updateShouldNotify(DesktopMetricsScope oldWidget) =>
      oldWidget.metrics.viewportSize != metrics.viewportSize ||
      oldWidget.metrics.scale != metrics.scale;
}

/// Centers a page at very wide sizes while preserving the existing edge
/// padding at normal and narrow sizes.
class DesktopResponsiveFrame extends StatelessWidget {
  const DesktopResponsiveFrame({
    super.key,
    required this.maxWidth,
    required this.padding,
    required this.child,
    this.fluid = false,
  });

  final double maxWidth;
  final EdgeInsets padding;
  final Widget child;
  final bool fluid;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final metrics = DesktopMetricsScope.of(context);
      final width = fluid
          ? constraints.maxWidth
          : math.min(constraints.maxWidth, metrics.px(maxWidth));
      return Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: width,
          child: Padding(padding: metrics.insets(padding), child: child),
        ),
      );
    },
  );
}
