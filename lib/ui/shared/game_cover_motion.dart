import 'package:flutter/material.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/color_scheme_option.dart';

/// Motion Prompt #161, MIT License (c) 2026 Shohei Ohtaki.
/// https://showheyohtaki.github.io/motion-prompt/#161
/// Shortened from the reference at the user's request.
const referenceViewDuration = Duration(milliseconds: 350);

class ReferenceViewCurve extends Curve {
  const ReferenceViewCurve();
  @override
  double transformInternal(double t) =>
      t < .5 ? 4 * t * t * t : 1 - (2 - 2 * t) * (2 - 2 * t) * (2 - 2 * t) / 2;
}

class _ReferenceHeroRectTween extends RectTween {
  _ReferenceHeroRectTween({required super.begin, required super.end});
  @override
  Rect? lerp(double t) {
    // Hero applies fastOutSlowIn before this tween. Undo it so the shared
    // element follows the reference's cubic ease-in-out over real time.
    // Pop flights use ReverseAnimation around Hero's flipped curve, yielding
    // the same forward progress curve for the rect tween.
    const curve = Curves.fastOutSlowIn;
    var low = 0.0, high = 1.0;
    for (var i = 0; i < 24; i++) {
      final mid = (low + high) / 2;
      if (curve.transform(mid) < t) {
        low = mid;
      } else {
        high = mid;
      }
    }
    return Rect.lerp(
      begin,
      end,
      const ReferenceViewCurve().transform((low + high) / 2),
    );
  }
}

RectTween referenceHeroRectTween(Rect? begin, Rect? end) =>
    _ReferenceHeroRectTween(begin: begin, end: end);

class CoverOrigin {
  CoverOrigin(this.path, this.rect, this.tag, {this.image})
    : capturedAt = DateTime.now();
  final String path;
  final Rect rect;
  final Object tag;
  final Widget? image;
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
    this.hiddenTag,
    required super.child,
  });
  final ValueChanged<CoverOrigin> onCapture;
  final Object? hiddenTag;
  static GameCoverMotionScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GameCoverMotionScope>();
  @override
  bool updateShouldNotify(GameCoverMotionScope oldWidget) =>
      hiddenTag != oldWidget.hiddenTag;
}

class GameCoverSource extends StatefulWidget {
  const GameCoverSource({super.key, required this.path, required this.child});
  final String path;
  final Widget child;
  @override
  State<GameCoverSource> createState() => _GameCoverSourceState();
}

/// Makes the card's cover the transition source even when its text is tapped.
class GameCoverCaptureRegion extends StatefulWidget {
  const GameCoverCaptureRegion({super.key, required this.child});
  final Widget child;

  @override
  State<GameCoverCaptureRegion> createState() => _GameCoverCaptureRegionState();
}

class _GameCoverCaptureRegionState extends State<GameCoverCaptureRegion> {
  final _capture = ValueNotifier<VoidCallback?>(null);
  @override
  void dispose() {
    _capture.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _GameCoverCaptureScope(
    capture: _capture,
    child: Listener(
      onPointerDown: (_) => _capture.value?.call(),
      child: widget.child,
    ),
  );
}

class _GameCoverCaptureScope extends InheritedWidget {
  const _GameCoverCaptureScope({required this.capture, required super.child});
  final ValueNotifier<VoidCallback?> capture;
  @override
  bool updateShouldNotify(_GameCoverCaptureScope oldWidget) =>
      capture != oldWidget.capture;
}

class _GameCoverSourceState extends State<GameCoverSource> {
  final Object _tag = Object();
  void _capture() {
    if (!mounted) return;
    final scope = GameCoverMotionScope.maybeOf(context);
    final box = context.findRenderObject();
    if (scope != null &&
        box is RenderBox &&
        box.hasSize &&
        !AppMotion.reduced(context)) {
      scope.onCapture(
        CoverOrigin(
          widget.path,
          box.localToGlobal(Offset.zero) & box.size,
          _tag,
          image: widget.child,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = GameCoverMotionScope.maybeOf(context);
    context
            .dependOnInheritedWidgetOfExactType<_GameCoverCaptureScope>()
            ?.capture
            .value =
        _capture;
    if (scope == null) return widget.child;
    return Listener(
      onPointerDown: (_) => _capture(),
      child: HeroMode(
        enabled: !AppMotion.reduced(context),
        child: Hero(
          tag: _tag,
          createRectTween:
              Theme.of(
                    context,
                  ).extension<AppPaletteThemeExtension>()?.palette.scheme ==
                  ColorSchemeOption.warmwoodStudy
              ? (begin, end) => referenceHeroRectTween(begin, end)
              : null,
          child: Opacity(
            opacity: scope.hiddenTag == _tag ? 0 : 1,
            child: widget.child,
          ),
        ),
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
    this.reference = false,
    this.reverse = false,
  });
  final Rect begin, end;
  final Widget child;
  final VoidCallback onEnd;
  final Size? viewport;
  final bool reference;
  final bool reverse;
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
            duration: AppMotion.duration(
              context,
              reference ? referenceViewDuration : AppMotion.cover,
            ),
            curve: reference ? Curves.linear : AppMotion.curve,
            onEnd: onEnd,
            child: child,
            builder: (context, value, child) {
              final movement = reference
                  ? const ReferenceViewCurve().transform(value)
                  : value;
              final rect = Rect.lerp(begin, end, movement)!;
              final opacity = reference
                  ? 1 - const Interval(.6, 1).transform(value)
                  : ((1 - value) / .25).clamp(0.0, 1.0);
              return Stack(
                children: [
                  Positioned.fromRect(
                    rect: rect,
                    child: Opacity(
                      opacity: AppMotion.reduced(context) ? 0 : opacity,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                          reference
                              ? (reverse ? 8 - 2 * movement : 6 + 2 * movement)
                              : 10 * (1 - value),
                        ),
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
  GameDetailRoute({required super.builder, this.reference = false});
  final bool reference;
  @override
  Duration get transitionDuration =>
      reference ? referenceViewDuration : AppMotion.cover;
  @override
  Duration get reverseTransitionDuration =>
      reference ? referenceViewDuration : AppMotion.panel;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (!reference) {
      return super.buildTransitions(
        context,
        animation,
        secondaryAnimation,
        child,
      );
    }
    if (AppMotion.reduced(context)) return child;
    return FadeTransition(
      opacity: animation.drive(CurveTween(curve: const Interval(.6, 1))),
      child: child,
    );
  }
}
