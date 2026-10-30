import 'package:flutter/material.dart';

import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_palette.dart';

/// Shared by narrow and wide conversations; never moves the message layout.
class AssistantScrollToBottomButton extends StatelessWidget {
  const AssistantScrollToBottomButton({
    super.key,
    required this.visible,
    required this.tooltip,
    required this.onPressed,
  });

  final bool visible;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final duration = AppMotion.duration(context);
    return ExcludeFocus(
      excluding: !visible,
      child: ExcludeSemantics(
        excluding: !visible,
        child: IgnorePointer(
          ignoring: !visible,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: duration,
            curve: AppMotion.curve,
            child: AnimatedScale(
              scale: visible || AppMotion.reduced(context) ? 1 : .92,
              duration: duration,
              curve: AppMotion.curve,
              child: IconButton.filledTonal(
                key: const ValueKey('assistant-scroll-to-bottom'),
                tooltip: tooltip,
                onPressed: onPressed,
                icon: const Icon(Icons.arrow_downward_rounded, size: 22),
                style: IconButton.styleFrom(
                  minimumSize: const Size.square(48),
                  maximumSize: const Size.square(48),
                  padding: const EdgeInsets.all(12),
                  shape: const CircleBorder(),
                  backgroundColor: palette.surfaceContainer,
                  foregroundColor: palette.textPrimary,
                  side: BorderSide(
                    color: palette.outline.withValues(alpha: .6),
                  ),
                  shadowColor: palette.shadow.withValues(alpha: .16),
                  elevation: 2,
                  hoverColor: palette.primary.withValues(alpha: .08),
                  focusColor: palette.focusRing.withValues(alpha: .14),
                  highlightColor: palette.primary.withValues(alpha: .14),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
