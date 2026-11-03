import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Motion Prompt #160, adapted to a real operation and a stable hit target.
class LoadingActionButton extends StatefulWidget {
  const LoadingActionButton({
    super.key,
    required this.onPressed,
    required this.loading,
    required this.succeeded,
    required this.label,
    required this.loadingLabel,
    required this.doneLabel,
    required this.background,
    required this.foreground,
    required this.successBackground,
    required this.successForeground,
  });

  final VoidCallback? onPressed;
  final bool loading;

  /// The result of the most recent operation. Null means no success feedback.
  final bool? succeeded;
  final String label;
  final String loadingLabel;
  final String doneLabel;
  final Color background;
  final Color foreground;
  final Color successBackground;
  final Color successForeground;

  @override
  State<LoadingActionButton> createState() => _LoadingActionButtonState();
}

enum _Phase {
  idle,
  shrink,
  expandLoading,
  loading,
  success,
  expandSuccess,
  done,
  fade,
  restore,
}

class _LoadingActionButtonState extends State<LoadingActionButton>
    with TickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(vsync: this)
    ..addStatusListener(_next);
  late final AnimationController _spinner = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  Timer? _hold;
  _Phase _phase = _Phase.idle;
  bool _reduced = false;
  double _width = 160;
  double _height = 48;
  double _fromWidth = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.disableAnimationsOf(context);
    if (widget.loading && _phase == _Phase.idle) _phase = _Phase.loading;
    if (_reduced) {
      _spinner.stop();
      _motion.stop();
      if (widget.loading) {
        _phase = _Phase.loading;
      } else if (_phase != _Phase.idle) {
        _hold?.cancel();
        _phase = _Phase.done;
        _hold = Timer(const Duration(milliseconds: 1100), () {
          if (mounted && !widget.loading) {
            setState(() => _phase = _Phase.idle);
          }
        });
      }
    } else if (widget.loading && !_spinner.isAnimating) {
      _spinner.repeat();
    }
  }

  void _start(_Phase phase, Duration duration) {
    _motion.stop();
    _phase = phase;
    _motion.duration = duration;
    _motion.forward(from: 0);
  }

  void _next(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    final completedPhase = _phase;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _phase != completedPhase) return;
      setState(() {
        switch (completedPhase) {
          case _Phase.shrink:
            if (widget.loading) {
              _start(_Phase.expandLoading, const Duration(milliseconds: 350));
            }
          case _Phase.expandLoading:
            _phase = _Phase.loading;
          case _Phase.success:
            _start(_Phase.expandSuccess, const Duration(milliseconds: 350));
          case _Phase.expandSuccess:
            _phase = _Phase.done;
            _hold = Timer(const Duration(milliseconds: 1100), () {
              if (!mounted || widget.loading) return;
              setState(
                () => _start(_Phase.fade, const Duration(milliseconds: 200)),
              );
            });
          case _Phase.fade:
            _start(_Phase.restore, const Duration(milliseconds: 300));
          case _Phase.restore:
            _phase = _Phase.idle;
          case _Phase.idle:
          case _Phase.loading:
          case _Phase.done:
            break;
        }
      });
    });
  }

  double get _circle => math.min(_height, _width);
  double get _doneWidth => math.min(_width, math.max(_circle, 150));
  double get _eased => Curves.easeInOutCubic.transform(_motion.value);
  double get _currentWidth => switch (_phase) {
    _Phase.shrink => _width + (_circle - _width) * _eased,
    _Phase.expandLoading => _circle + (_width - _circle) * _eased,
    _Phase.success => _fromWidth + (_circle - _fromWidth) * _eased,
    _Phase.expandSuccess => _circle + (_doneWidth - _circle) * _eased,
    _Phase.done || _Phase.fade => _doneWidth,
    _ => _width,
  };

  @override
  void didUpdateWidget(covariant LoadingActionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.loading && widget.loading) {
      _hold?.cancel();
      if (_reduced) {
        _motion.stop();
        _phase = _Phase.loading;
      } else {
        _spinner.repeat();
        _start(_Phase.shrink, const Duration(milliseconds: 300));
      }
    } else if (oldWidget.loading && !widget.loading) {
      final currentWidth = _currentWidth;
      _spinner.stop();
      if (widget.succeeded == true) {
        if (_reduced) {
          _motion.stop();
          _phase = _Phase.done;
          _hold = Timer(const Duration(milliseconds: 1100), () {
            if (mounted && !widget.loading) {
              setState(() => _phase = _Phase.idle);
            }
          });
        } else {
          _fromWidth = currentWidth;
          _start(_Phase.success, const Duration(milliseconds: 250));
        }
      } else {
        _motion.stop();
        _phase = _Phase.idle;
      }
    }
  }

  @override
  void dispose() {
    _hold?.cancel();
    _motion.dispose();
    _spinner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.onPressed != null && !widget.loading;
    final showingSuccess =
        _phase == _Phase.success ||
        _phase == _Phase.expandSuccess ||
        _phase == _Phase.done ||
        _phase == _Phase.fade;
    final semanticLabel = widget.loading
        ? widget.loadingLabel
        : showingSuccess
        ? widget.doneLabel
        : widget.label;
    final style = Theme.of(context).textTheme.labelLarge!;
    return Semantics(
      button: true,
      enabled: active,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: active ? widget.onPressed : null,
            borderRadius: BorderRadius.circular(30),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Opacity(
                    opacity: 0,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 14,
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          for (final text in [
                            widget.label,
                            widget.loadingLabel,
                            widget.doneLabel,
                          ])
                            RichText(
                              text: TextSpan(text: text, style: style),
                              textScaler: MediaQuery.textScalerOf(context),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        _width = constraints.maxWidth;
                        // Invisible measurement uses two lines; reserve one line.
                        _height = constraints.maxHeight;
                        return AnimatedBuilder(
                          animation: Listenable.merge([_motion, _spinner]),
                          builder: (context, _) {
                            final p = _motion.value;
                            final success = switch (_phase) {
                              _Phase.success => Curves.easeOutCubic.transform(
                                (p * 1.25).clamp(0.0, 1.0),
                              ),
                              _Phase.expandSuccess ||
                              _Phase.done ||
                              _Phase.fade => 1.0,
                              _ => 0.0,
                            };
                            final alpha = _phase == _Phase.fade
                                ? 1 - p
                                : _phase == _Phase.restore
                                ? Curves.easeOutCubic.transform(p)
                                : 1.0;
                            final isLoading = widget.loading;
                            final isSuccess = success > 0;
                            final showIdle = !isLoading && !isSuccess;
                            final showFadingLabel =
                                _phase == _Phase.shrink && p < 1 / 3;
                            final showLoadingLabel =
                                _phase == _Phase.loading ||
                                _phase == _Phase.expandLoading && p > .5;
                            final showDone =
                                _phase == _Phase.done ||
                                _phase == _Phase.fade ||
                                _phase == _Phase.expandSuccess && p > .5;
                            return Center(
                              child: Opacity(
                                opacity: alpha,
                                child: Container(
                                  key: const ValueKey('loading-action-surface'),
                                  width: _currentWidth,
                                  height: _height,
                                  clipBehavior: Clip.antiAlias,
                                  decoration: BoxDecoration(
                                    color: Color.lerp(
                                      widget.background,
                                      widget.successBackground,
                                      success,
                                    ),
                                    borderRadius: BorderRadius.circular(
                                      _height / 2,
                                    ),
                                  ),
                                  child: DefaultTextStyle(
                                    style: style.copyWith(
                                      color: isSuccess
                                          ? widget.successForeground
                                          : widget.foreground,
                                    ),
                                    child: Center(
                                      child: showFadingLabel
                                          ? Opacity(
                                              opacity: (1 - p * 3).clamp(
                                                0.0,
                                                1.0,
                                              ),
                                              child: Text(
                                                widget.label,
                                                textAlign: TextAlign.center,
                                              ),
                                            )
                                          : showIdle
                                          ? Text(
                                              widget.label,
                                              textAlign: TextAlign.center,
                                            )
                                          : isSuccess
                                          ? Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                CustomPaint(
                                                  size: const Size(20, 20),
                                                  painter: _CheckPainter(
                                                    widget.successForeground,
                                                    _phase == _Phase.success
                                                        ? p
                                                        : 1,
                                                  ),
                                                ),
                                                if (showDone) ...[
                                                  const SizedBox(width: 8),
                                                  Flexible(
                                                    child: Text(
                                                      widget.doneLabel,
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            )
                                          : Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Opacity(
                                                  opacity:
                                                      _phase == _Phase.shrink
                                                      ? ((p - .83) / .17).clamp(
                                                          0.0,
                                                          1.0,
                                                        )
                                                      : 1,
                                                  child: RotationTransition(
                                                    turns: _spinner,
                                                    child: CustomPaint(
                                                      key: const ValueKey(
                                                        'loading-action-spinner',
                                                      ),
                                                      size: const Size(20, 20),
                                                      painter: _SpinnerPainter(
                                                        widget.foreground,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                if (showLoadingLabel) ...[
                                                  const SizedBox(width: 8),
                                                  Flexible(
                                                    child: Text(
                                                      widget.loadingLabel,
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SpinnerPainter extends CustomPainter {
  const _SpinnerPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(
      size.center(Offset.zero),
      8.5,
      paint..color = color.withValues(alpha: .35),
    );
    canvas.drawArc(
      (Offset.zero & size).deflate(1.5),
      0,
      math.pi * .7,
      false,
      paint..color = color,
    );
  }

  @override
  bool shouldRepaint(_SpinnerPainter oldDelegate) => color != oldDelegate.color;
}

class _CheckPainter extends CustomPainter {
  const _CheckPainter(this.color, this.progress);
  final Color color;
  final double progress;
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(3, 10)
      ..lineTo(8, 15)
      ..lineTo(17, 5);
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * progress.clamp(0, 1)),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter oldDelegate) =>
      color != oldDelegate.color || progress != oldDelegate.progress;
}
