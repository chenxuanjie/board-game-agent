import 'package:flutter/material.dart';
import '../../core/theme/app_motion.dart';

class CoverOrigin {
  CoverOrigin(this.path, this.rect, this.tag) : capturedAt = DateTime.now();
  final String path;
  final Rect rect;
  final Object tag;
  final DateTime capturedAt;
  bool matches(String path) =>
      this.path == path &&
      DateTime.now().difference(capturedAt) < const Duration(seconds: 1);
}

/// Geometry belongs to this workspace, never to a global registry.
class GameCoverMotionScope extends InheritedWidget {
  const GameCoverMotionScope({
    super.key,
    required this.onCapture,
    required super.child,
  });
  final ValueChanged<CoverOrigin> onCapture;
  static GameCoverMotionScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GameCoverMotionScope>();
  @override
  bool updateShouldNotify(GameCoverMotionScope oldWidget) => false;
}

class GameCoverSource extends StatefulWidget {
  const GameCoverSource({super.key, required this.path, required this.child});
  final String path;
  final Widget child;
  @override
  State<GameCoverSource> createState() => _GameCoverSourceState();
}

class _GameCoverSourceState extends State<GameCoverSource> {
  final Object _tag = Object();
  @override
  Widget build(BuildContext context) {
    final scope = GameCoverMotionScope.maybeOf(context);
    if (scope == null) return widget.child;
    return Listener(
      onPointerDown: (_) {
        final box = context.findRenderObject();
        if (box is RenderBox && box.hasSize && !AppMotion.reduced(context)) {
          scope.onCapture(
            CoverOrigin(
              widget.path,
              box.localToGlobal(Offset.zero) & box.size,
              _tag,
            ),
          );
        }
      },
      child: HeroMode(
        enabled: !AppMotion.reduced(context),
        child: Hero(tag: _tag, child: widget.child),
      ),
    );
  }
}

/// Desktop detail lives inside the same shell, so a small geometry overlay
/// supplies continuity without adding a second page/controller.
class GameCoverFlight extends StatelessWidget {
  const GameCoverFlight({
    super.key,
    required this.begin,
    required this.end,
    required this.child,
    required this.onEnd,
    this.viewport,
  });
  final Rect begin, end;
  final Widget child;
  final VoidCallback onEnd;
  final Size? viewport;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (viewport != null && constraints.biggest != viewport) {
        WidgetsBinding.instance.addPostFrameCallback((_) => onEnd());
        return const SizedBox.shrink();
      }
      return IgnorePointer(
        child: ExcludeSemantics(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: AppMotion.duration(context, AppMotion.cover),
            curve: AppMotion.curve,
            onEnd: onEnd,
            child: child,
            builder: (context, value, child) {
              final rect = Rect.lerp(begin, end, value)!;
              final opacity = ((1 - value) / .25).clamp(0.0, 1.0);
              return Stack(
                children: [
                  Positioned.fromRect(
                    rect: rect,
                    child: Opacity(
                      opacity: AppMotion.reduced(context) ? 0 : opacity,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10 * (1 - value)),
                        child: child,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
    },
  );
}

class GameDetailRoute<T> extends MaterialPageRoute<T> {
  GameDetailRoute({required super.builder});
  @override
  Duration get transitionDuration => AppMotion.cover;
  @override
  Duration get reverseTransitionDuration => AppMotion.panel;
}
