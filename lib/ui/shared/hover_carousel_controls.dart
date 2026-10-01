import 'package:flutter/material.dart';
import '../../core/theme/app_motion.dart';
import 'package:flutter/services.dart';

/// Classic edge controls, visible on pointer hover or keyboard focus.
class HoverCarouselControls extends StatefulWidget {
  const HoverCarouselControls({
    super.key,
    required this.child,
    required this.onPrevious,
    required this.onNext,
    required this.keyPrefix,
    this.enabled = true,
    this.onInteractionChanged,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
  });
  final Widget child;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final String keyPrefix;
  final bool enabled;
  final ValueChanged<bool>? onInteractionChanged;
  final BorderRadius borderRadius;
  @override
  State<HoverCarouselControls> createState() => _HoverCarouselControlsState();
}

class _HoverCarouselControlsState extends State<HoverCarouselControls> {
  bool _hover = false;
  bool _focus = false;
  bool get _visible => _hover || _focus;
  void _update({bool? hover, bool? focus}) {
    setState(() {
      _hover = hover ?? _hover;
      _focus = focus ?? _focus;
    });
    widget.onInteractionChanged?.call(_visible);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return MouseRegion(
      key: ValueKey('${widget.keyPrefix}-hover'),
      onEnter: (_) => _update(hover: true),
      onExit: (_) => _update(hover: false),
      child: Focus(
        onFocusChange: (value) => _update(focus: value),
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            widget.onPrevious();
            return KeyEventResult.handled;
          }
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.arrowRight) {
            widget.onNext();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: ClipRRect(
          borderRadius: widget.borderRadius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              widget.child,
              _button(context, previous: true),
              _button(context, previous: false),
            ],
          ),
        ),
      ),
    );
  }

  Widget _button(BuildContext context, {required bool previous}) =>
      CarouselEdgeButton(
        visible: _visible,
        previous: previous,
        keyPrefix: widget.keyPrefix,
        onTap: previous ? widget.onPrevious : widget.onNext,
      );
}

class CarouselEdgeButton extends StatelessWidget {
  const CarouselEdgeButton({
    super.key,
    required this.visible,
    required this.previous,
    required this.keyPrefix,
    required this.onTap,
  });
  final bool visible;
  final bool previous;
  final String keyPrefix;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final direction = previous ? 'previous' : 'next';
    final label = previous
        ? MaterialLocalizations.of(context).previousPageTooltip
        : MaterialLocalizations.of(context).nextPageTooltip;
    final duration = AppMotion.duration(
      context,
      visible ? AppMotion.menu : AppMotion.exit,
    );
    return Positioned(
      left: previous ? 0 : null,
      right: previous ? null : 0,
      top: 0,
      bottom: 0,
      child: Center(
        child: IgnorePointer(
          ignoring: !visible,
          child: AnimatedOpacity(
            key: ValueKey('$keyPrefix-$direction-visibility'),
            opacity: visible ? 1 : 0,
            duration: duration,
            curve: AppMotion.curve,
            child: AnimatedSlide(
              offset: visible ? Offset.zero : Offset(previous ? -.2 : .2, 0),
              duration: duration,
              curve: AppMotion.curve,
              child: Tooltip(
                message: label,
                child: SizedBox(
                  width: 38,
                  height: 72,
                  child: TextButton(
                    key: ValueKey('$keyPrefix-$direction'),
                    onPressed: onTap,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      backgroundColor: const Color(0x66000000),
                      foregroundColor: Colors.white,
                      overlayColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: previous
                            ? const BorderRadius.horizontal(
                                right: Radius.circular(10),
                              )
                            : const BorderRadius.horizontal(
                                left: Radius.circular(10),
                              ),
                      ),
                    ),
                    child: Icon(
                      previous
                          ? Icons.chevron_left_rounded
                          : Icons.chevron_right_rounded,
                      size: 30,
                      semanticLabel: label,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
