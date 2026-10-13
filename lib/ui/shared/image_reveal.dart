import 'package:flutter/material.dart';
import '../../core/theme/app_motion.dart';

/// Reveal only after an actual decoded frame; cached frames appear immediately.
Widget revealImageFrame(
  BuildContext context,
  Widget child,
  int? frame,
  bool synchronous,
) => _DecodedImageReveal(
  ready: frame != null,
  immediate: synchronous || AppMotion.reduced(context),
  child: child,
);

class ImageLoadingPlaceholder extends StatelessWidget {
  const ImageLoadingPlaceholder({super.key});
  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerLow);
}

class _DecodedImageReveal extends StatefulWidget {
  const _DecodedImageReveal({
    required this.child,
    required this.ready,
    required this.immediate,
  });
  final Widget child;
  final bool ready, immediate;
  @override
  State<_DecodedImageReveal> createState() => _DecodedImageRevealState();
}

class _DecodedImageRevealState extends State<_DecodedImageReveal> {
  late bool _shown = widget.ready;
  @override
  void didUpdateWidget(covariant _DecodedImageReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    // gaplessPlayback keeps the last decoded frame while a replacement loads.
    _shown = _shown || widget.ready;
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.passthrough,
    children: [
      const Positioned.fill(child: ImageLoadingPlaceholder()),
      if (widget.immediate)
        Opacity(opacity: _shown ? 1 : 0, child: widget.child)
      else
        AnimatedOpacity(
          opacity: _shown ? 1 : 0,
          duration: widget.immediate
              ? Duration.zero
              : AppMotion.duration(context),
          curve: AppMotion.curve,
          child: widget.child,
        ),
    ],
  );
}
