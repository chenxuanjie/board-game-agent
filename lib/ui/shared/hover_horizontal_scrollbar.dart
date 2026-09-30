import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Explicit ownership keeps each horizontal strip independent of page scrolling.
class HoverHorizontalScrollbar extends StatefulWidget {
  const HoverHorizontalScrollbar({
    super.key,
    required this.builder,
    required this.keyPrefix,
    this.enabled,
  });
  final Widget Function(ScrollController) builder;
  final String keyPrefix;
  final bool? enabled;
  @override
  State<HoverHorizontalScrollbar> createState() =>
      _HoverHorizontalScrollbarState();
}

class _HoverHorizontalScrollbarState extends State<HoverHorizontalScrollbar> {
  final _controller = ScrollController();
  bool _hover = false;
  bool _focus = false;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled =
        widget.enabled ??
        (kIsWeb ||
            const {
              TargetPlatform.windows,
              TargetPlatform.macOS,
              TargetPlatform.linux,
            }.contains(defaultTargetPlatform));
    final child = widget.builder(_controller);
    if (!enabled) return child;
    return MouseRegion(
      key: ValueKey('${widget.keyPrefix}-hover'),
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Focus(
        onFocusChange: (value) => setState(() => _focus = value),
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: RawScrollbar(
            key: ValueKey('${widget.keyPrefix}-scrollbar'),
            controller: _controller,
            thumbVisibility: _hover || _focus,
            interactive: true,
            thickness: 8,
            radius: const Radius.circular(4),
            thumbColor: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: .55),
            scrollbarOrientation: ScrollbarOrientation.bottom,
            fadeDuration: const Duration(milliseconds: 160),
            timeToFade: const Duration(milliseconds: 300),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
