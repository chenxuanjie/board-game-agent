import 'package:flutter/material.dart';
import '../../core/theme/app_motion.dart';

/// Reveal only after an actual decoded frame; cached frames appear immediately.
Widget revealImageFrame(
  BuildContext context,
  Widget child,
  int? frame,
  bool synchronous,
) => synchronous || AppMotion.reduced(context)
    ? child
    : AnimatedOpacity(
        opacity: frame == null ? 0 : 1,
        duration: AppMotion.duration(context),
        curve: AppMotion.curve,
        child: child,
      );
