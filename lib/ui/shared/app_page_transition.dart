import 'package:flutter/material.dart';

import '../../core/theme/app_motion.dart';

/// Shows the current destination immediately, then gently fades it in.
/// Only one live page is mounted: rapid navigation cannot retain an old AI
/// pane, duplicate GlobalKeys, or attach two pages to one scroll controller.
class AppPageTransition extends StatefulWidget {
  const AppPageTransition({
    super.key,
    required this.identity,
    required this.child,
  });

  final Object identity;
  final Widget child;

  @override
  State<AppPageTransition> createState() => _AppPageTransitionState();
}

class _AppPageTransitionState extends State<AppPageTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    value: 1,
    duration: AppMotion.content,
  );
  late final Animation<double> _opacity = _entrance.drive(
    CurveTween(curve: AppMotion.curve),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context)) _entrance.value = 1;
  }

  @override
  void didUpdateWidget(covariant AppPageTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity) {
      if (AppMotion.reduced(context)) {
        _entrance.value = 1;
      } else {
        // A nonzero start keeps the destination readable and clickable even
        // on the first frame. It never waits for an outgoing page animation.
        _entrance.forward(from: .35);
      }
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _opacity, child: widget.child);
}
