import 'package:flutter/material.dart';
import '../../../core/theme/app_motion.dart';

/// A keyed entrance is played once, never once per streamed text delta.
class AssistantMessageEntrance extends StatelessWidget {
  const AssistantMessageEntrance({
    super.key,
    required this.child,
    this.animate = true,
  });
  final Widget child;
  final bool animate;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: animate ? 0 : 1, end: 1),
    duration: AppMotion.duration(context),
    curve: AppMotion.curve,
    child: child,
    builder: (context, value, child) => Opacity(
      opacity: value,
      child: Transform.translate(
        offset: Offset(0, 6 * (1 - value)),
        child: child,
      ),
    ),
  );
}
