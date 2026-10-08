import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'desktop_responsive.dart';
import 'window_controls.dart';

/// Window chrome lives above the Navigator, including its dialogs and routes.
class DesktopWindowFrame extends StatelessWidget {
  const DesktopWindowFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return child;
    return Overlay.wrap(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final metrics = DesktopResponsive.metricsFor(constraints.biggest);
          final height = metrics.px(32);
          return DragToResizeArea(
            resizeEdgeSize: 6,
            child: Column(
              children: [
                DesktopMetricsScope(
                  metrics: metrics,
                  child: Material(
                    color: Theme.of(context).colorScheme.surface,
                    child: SizedBox(
                      key: const ValueKey('desktop-window-titlebar'),
                      height: height,
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              key: const ValueKey('desktop-window-drag-area'),
                              behavior: HitTestBehavior.opaque,
                              onPanStart: (_) => windowManager.startDragging(),
                              onDoubleTap: () async {
                                if (await windowManager.isMaximized()) {
                                  await windowManager.unmaximize();
                                } else {
                                  await windowManager.maximize();
                                }
                              },
                              child: const SizedBox.expand(),
                            ),
                          ),
                          const WindowControls(),
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
