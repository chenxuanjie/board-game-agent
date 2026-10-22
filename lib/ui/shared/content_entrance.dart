import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/theme/app_motion.dart';

/// Stable children stay mounted. Only new or changed items receive a transition.
class ContentEntrance extends StatefulWidget {
  const ContentEntrance({
    super.key,
    required this.child,
    this.order = 0,
    this.animate = true,
    this.changeIdentity,
  });
  final Widget child;
  final int order;
  final bool animate;
  final Object? changeIdentity;
  @override
  State<ContentEntrance> createState() => _ContentEntranceState();
}

class _ContentEntranceState extends State<ContentEntrance>
    with SingleTickerProviderStateMixin {
  late final _animation = AnimationController(
    vsync: this,
    duration: AppMotion.content,
    value: widget.animate ? 0 : 1,
  );
  bool _started = false;
  bool _changed = false;
  void _start({bool changed = false}) {
    if (AppMotion.reduced(context)) {
      _animation.value = 1;
      return;
    }
    _changed = changed;
    final delay = changed ? 0 : 30 * math.min(3, math.max(0, widget.order));
    _animation.duration = Duration(
      milliseconds: (AppMotion.content.inMilliseconds + delay).toInt(),
    );
    _animation.forward(from: 0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context)) {
      _animation.value = 1;
    } else if (!_started && widget.animate) {
      _start();
    }
    _started = true;
  }

  @override
  void didUpdateWidget(covariant ContentEntrance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.changeIdentity != null &&
        widget.changeIdentity != oldWidget.changeIdentity) {
      _start(changed: true);
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _animation,
    child: widget.child,
    builder: (context, child) {
      final delay = _changed ? 0 : 30 * math.min(3, math.max(0, widget.order));
      final duration = AppMotion.content.inMilliseconds + delay;
      final value = Interval(
        delay / duration,
        1,
        curve: AppMotion.curve,
      ).transform(_animation.value);
      return Opacity(
        opacity: .6 + .4 * value,
        child: Transform.translate(
          offset: Offset(0, AppMotion.reduced(context) ? 0 : 4 * (1 - value)),
          child: child,
        ),
      );
    },
  );
}
