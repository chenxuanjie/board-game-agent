import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/theme/app_motion.dart';

/// One short entrance per mounted content block, never per controller update.
class ContentEntrance extends StatelessWidget {
  const ContentEntrance({
    super.key,
    required this.child,
    this.order = 0,
    this.animate = true,
  });
  final Widget child;
  final int order;
  final bool animate;
  @override
  Widget build(BuildContext context) {
    if (!animate || AppMotion.reduced(context)) return child;
    final delay = (30 * math.min(3, math.max(0, order))).toInt();
    final duration = Duration(
      milliseconds: AppMotion.content.inMilliseconds + delay,
    );
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppMotion.duration(context, duration),
      curve: Interval(
        delay / duration.inMilliseconds,
        1,
        curve: AppMotion.curve,
      ),
      child: child,
      builder: (context, value, child) => Opacity(
        opacity: .6 + .4 * value,
        child: Transform.translate(
          offset: Offset(0, AppMotion.reduced(context) ? 0 : 4 * (1 - value)),
          child: child,
        ),
      ),
    );
  }
}
