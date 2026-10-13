import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'desktop_responsive.dart';
import 'window_controls.dart';
import 'theme.dart';

/// Page routes control the chrome background; popup routes keep their backdrop.
class DesktopWindowChromeObserver extends NavigatorObserver {
  DesktopWindowChromeObserver({required this.workspaceRouteNames});
  final Set<String> workspaceRouteNames;
  final sidebarVisible = ValueNotifier<bool>(true);
  final List<Route<dynamic>> _routes = [];
  void reset() {
    _routes.clear();
    sidebarVisible.value = true;
  }

  void _update() {
    final page = _routes.whereType<PageRoute<dynamic>>().lastOrNull;
    sidebarVisible.value =
        page == null ||
        page.isFirst ||
        workspaceRouteNames.contains(page.settings.name);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
    _update();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _update();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _update();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index >= 0) {
      if (newRoute == null) {
        _routes.removeAt(index);
      } else {
        _routes[index] = newRoute;
      }
    }
    _update();
  }
}

/// Window chrome lives above the Navigator, including its dialogs and routes.
class DesktopWindowFrame extends StatelessWidget {
  const DesktopWindowFrame({
    super.key,
    required this.child,
    this.sidebarVisible = false,
  });

  final Widget child;
  final bool sidebarVisible;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return child;
    return Overlay.wrap(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final metrics = DesktopResponsive.metricsFor(constraints.biggest);
          final height = metrics.px(32);
          // Workspace metrics use the content viewport below the title bar.
          final contentMetrics = DesktopResponsive.metricsFor(
            Size(constraints.maxWidth, constraints.maxHeight - height),
          );
          final sidebarWidth =
              !sidebarVisible ||
                  DesktopResponsive.isNarrow(constraints.maxWidth)
              ? 0.0
              : contentMetrics.px(
                  DesktopResponsive.usesFullSidebar(constraints.maxWidth)
                      ? DesktopResponsive.fullSidebarWidth
                      : DesktopResponsive.compactSidebarWidth,
                );
          return DragToResizeArea(
            resizeEdgeSize: 6,
            child: Column(
              children: [
                DesktopMetricsScope(
                  metrics: metrics,
                  child: Material(
                    color: sidebarVisible
                        ? desktopColors(context).background
                        : Theme.of(context).scaffoldBackgroundColor,
                    child: SizedBox(
                      key: ValueKey('desktop-window-titlebar'),
                      height: height,
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              key: ValueKey('desktop-window-drag-area'),
                              behavior: HitTestBehavior.opaque,
                              onPanStart: (_) => windowManager.startDragging(),
                              onDoubleTap: () async {
                                if (await windowManager.isMaximized()) {
                                  await windowManager.unmaximize();
                                } else {
                                  await windowManager.maximize();
                                }
                              },
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  if (sidebarWidth > 0)
                                    Positioned(
                                      left: 0,
                                      top: 0,
                                      bottom: 0,
                                      width: sidebarWidth,
                                      child: DecoratedBox(
                                        key: ValueKey(
                                          'desktop-window-sidebar-background',
                                        ),
                                        decoration: BoxDecoration(
                                          color: desktopColors(context).sidebar,
                                          border: Border(
                                            right: BorderSide(
                                              color: desktopColors(
                                                context,
                                              ).line,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          WindowControls(),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      size: Size(
                        constraints.maxWidth,
                        constraints.maxHeight - height,
                      ),
                    ),
                    child: child,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
