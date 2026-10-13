import 'package:flutter/material.dart';
import '../../core/theme/app_motion.dart';

/// Interpolation never advances beyond actual progress and never delays work.
class SmoothProgress extends StatelessWidget {
  const SmoothProgress({
    super.key,
    this.value,
    this.visible = true,
    this.height = 4,
    this.label,
  });
  final double? value;
  final bool visible;
  final double height;
  final String? label;
  @override
  Widget build(BuildContext context) {
    if (AppMotion.reduced(context)) {
      return SizedBox(
        height: height,
        child: visible
            ? LinearProgressIndicator(
                value: value?.clamp(0, 1),
                minHeight: height,
                semanticsLabel: label,
                semanticsValue: value == null
                    ? null
                    : '${(value!.clamp(0, 1) * 100).round()}',
              )
            : null,
      );
    }
    return SizedBox(
      height: height,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: AppMotion.duration(context),
        curve: AppMotion.curve,
        child: TickerMode(
          enabled: visible,
          child: value == null
              ? LinearProgressIndicator(
                  minHeight: height,
                  semanticsLabel: label,
                )
              : TweenAnimationBuilder<double>(
                  tween: Tween(
                    begin: value!.clamp(0, 1),
                    end: value!.clamp(0, 1),
                  ),
                  duration: AppMotion.duration(context, AppMotion.content),
                  curve: AppMotion.curve,
                  builder: (_, display, _) => LinearProgressIndicator(
                    value: display.clamp(0.0, value!.clamp(0.0, 1.0)),
                    minHeight: height,
                    semanticsLabel: label,
                    semanticsValue: '${(value!.clamp(0, 1) * 100).round()}',
                  ),
                ),
        ),
      ),
    );
  }
}
