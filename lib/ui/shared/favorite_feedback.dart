import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/color_scheme_option.dart';
import '../../app/state/app_controller.dart';
import '../../features/games/models/game_info.dart';
import 'app_failure_notice.dart';
import 'personal_account_access.dart';

class FavoriteFeedbackIcon extends StatefulWidget {
  const FavoriteFeedbackIcon({
    super.key,
    required this.selected,
    this.color,
    this.size = 20,
    this.selectedIcon = Icons.favorite_rounded,
    this.unselectedIcon = Icons.favorite_border_rounded,
    this.motion166 = false,
  });
  final bool selected;
  final Color? color;
  final double size;
  final IconData selectedIcon, unselectedIcon;
  final bool motion166;
  @override
  State<FavoriteFeedbackIcon> createState() => _FavoriteFeedbackIconState();
}

class _FavoriteFeedbackIconState extends State<FavoriteFeedbackIcon>
    with TickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: AppMotion.content,
    value: 1,
  );
  late final AnimationController _reference = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1320),
    value: 1,
  );
  late final Animation<double> _scale = _pulse.drive(
    TweenSequence([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1,
          end: 1.15,
        ).chain(CurveTween(curve: AppMotion.curve)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.15,
          end: 1,
        ).chain(CurveTween(curve: AppMotion.curve)),
        weight: 60,
      ),
    ]),
  );
  late final Animation<double> _warmScale = _pulse.drive(
    TweenSequence([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1,
          end: 1.1,
        ).chain(CurveTween(curve: AppMotion.curve)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.1,
          end: 1,
        ).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 60,
      ),
    ]),
  );
  @override
  void didUpdateWidget(covariant FavoriteFeedbackIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.motion166 &&
        Theme.of(
              context,
            ).extension<AppPaletteThemeExtension>()?.palette.scheme ==
            ColorSchemeOption.warmwoodStudy &&
        oldWidget.selected != widget.selected &&
        !AppMotion.reduced(context)) {
      _reference.forward(from: 0);
      return;
    }
    if (oldWidget.selected != widget.selected &&
        widget.selected &&
        !AppMotion.reduced(context)) {
      _pulse.forward(from: 0);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context)) _pulse.value = 1;
    if (AppMotion.reduced(context)) _reference.value = 1;
  }

  @override
  void dispose() {
    _pulse.dispose();
    _reference.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final warm =
        Theme.of(
          context,
        ).extension<AppPaletteThemeExtension>()?.palette.scheme ==
        ColorSchemeOption.warmwoodStudy;
    if (warm && widget.motion166) {
      final color = AppPalette.of(context).primary;
      return AnimatedBuilder(
        animation: _reference,
        builder: (context, _) {
          final t = _reference.value * 1.32;
          final double scale;
          if (widget.selected) {
            scale = t < .12
                ? .78 + .67 * Curves.easeOutCubic.transform(t / .12)
                : 1 + .45 * math.exp(-7 * (t - .12)) * math.cos(15 * (t - .12));
          } else {
            scale = t < .3
                ? 1 - .16 * math.sin(math.pi * ((t + .1) / .4).clamp(0.0, 1.0))
                : 1;
          }
          return SizedBox(
            width: widget.size,
            height: widget.size,
            child: OverflowBox(
              minWidth: 0,
              minHeight: 0,
              maxWidth: widget.size + 80,
              maxHeight: widget.size + 80,
              child: SizedBox(
                width: widget.size + 80,
                height: widget.size + 80,
                child: CustomPaint(
                  painter: _LikeBurstPainter(
                    time: t,
                    active: widget.selected && _reference.isAnimating,
                    color: color,
                  ),
                  child: Center(
                    child: Transform.scale(
                      scale: scale,
                      child: Icon(
                        widget.selected
                            ? widget.selectedIcon
                            : widget.unselectedIcon,
                        color: widget.color,
                        size: widget.size,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    }
    return ScaleTransition(
      scale:
          Theme.of(
                context,
              ).extension<AppPaletteThemeExtension>()?.palette.scheme ==
              ColorSchemeOption.warmwoodStudy
          ? _warmScale
          : _scale,
      child: Icon(
        widget.selected ? widget.selectedIcon : widget.unselectedIcon,
        color: widget.color,
        size: widget.size,
      ),
    );
  }
}

// Motion Prompt #166, MIT License (c) 2026 Shohei Ohtaki.
// https://showheyohtaki.github.io/motion-prompt/#166
class _LikeBurstPainter extends CustomPainter {
  _LikeBurstPainter({
    required this.time,
    required this.active,
    required this.color,
  });
  final double time;
  final bool active;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    if (!active || time < .08 || time >= .58) return;
    final f = ((time - .08) / .5).clamp(0.0, 1.0);
    final eased = Curves.easeOutCubic.transform(f);
    final center = size.center(Offset.zero);
    canvas.drawCircle(
      center,
      15 + 18 * eased,
      Paint()
        ..color = color.withValues(alpha: .5 * (1 - f))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    final colors = [color, const Color(0xffffb020), const Color(0xffff8a4a)];
    for (var i = 0; i < 6; i++) {
      final angle = -math.pi / 2 + i * math.pi / 3;
      final radius = 24 + 13 * eased;
      canvas.drawCircle(
        center + Offset(math.cos(angle) * radius, math.sin(angle) * radius),
        2.4 * (1 - .5 * f),
        Paint()..color = colors[i % 3].withValues(alpha: 1 - f),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LikeBurstPainter old) =>
      old.time != time || old.active != active || old.color != color;
}

/// Immediate intent feedback over the existing mutation queue and rollback.
/// Repeated presses are guarded without dimming or replacing the reaction icon.
class FavoriteToggleButton extends StatefulWidget {
  const FavoriteToggleButton({
    super.key,
    required this.controller,
    required this.game,
    this.color,
    this.style,
    this.filledTonal = false,
  });
  final AppController controller;
  final GameInfo game;
  final Color? color;
  final ButtonStyle? style;
  final bool filledTonal;
  @override
  State<FavoriteToggleButton> createState() => _FavoriteToggleButtonState();
}

class _FavoriteToggleButtonState extends State<FavoriteToggleButton> {
  bool _busy = false;
  late bool _confirmed = widget.controller.isFavorite(widget.game);
  int _generation = 0;
  @override
  void didUpdateWidget(covariant FavoriteToggleButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.game.id != widget.game.id) {
      ++_generation;
      _busy = false;
    }
    if (!_busy) _confirmed = widget.controller.isFavorite(widget.game);
  }

  Future<void> _toggle() async {
    if (!requirePersonalAccount(context)) return;
    if (_busy) return;
    final generation = ++_generation;
    final controller = widget.controller;
    final game = widget.game;
    final copy = widget.controller.copy;
    setState(() {
      _busy = true;
      _confirmed = !_confirmed;
    });
    var saved = false;
    try {
      saved = await controller.toggleFavorite(game);
    } catch (_) {
      saved = false;
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          _confirmed = widget.controller.isFavorite(widget.game);
        });
      }
    }
    if (!saved && mounted && generation == _generation) {
      showAppFailureNotice(context, copy.favoriteSaveFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final button = widget.filledTonal ? IconButton.filledTonal : IconButton.new;
    return button(
      style: widget.style,
      tooltip: _confirmed
          ? widget.controller.copy.localized('取消喜欢', 'Unlike')
          : widget.controller.copy.localized('喜欢', 'Like'),
      onPressed: _toggle,
      icon: FavoriteFeedbackIcon(selected: _confirmed, color: widget.color),
    );
  }
}
