import 'package:flutter/material.dart';
import '../../core/theme/app_motion.dart';
import '../../app/state/app_controller.dart';
import '../../features/games/models/game_info.dart';

class FavoriteFeedbackIcon extends StatefulWidget {
  const FavoriteFeedbackIcon({
    super.key,
    required this.selected,
    this.color,
    this.size = 20,
  });
  final bool selected;
  final Color? color;
  final double size;
  @override
  State<FavoriteFeedbackIcon> createState() => _FavoriteFeedbackIconState();
}

class _FavoriteFeedbackIconState extends State<FavoriteFeedbackIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: AppMotion.content,
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
  @override
  void didUpdateWidget(covariant FavoriteFeedbackIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
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
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(
    scale: _scale,
    child: Icon(
      widget.selected ? Icons.favorite_rounded : Icons.favorite_border_rounded,
      color: widget.color,
      size: widget.size,
    ),
  );
}

/// Uses the existing mutation queue and rollback. A pulse follows persistence,
/// while repeated presses are disabled until the current write settles.
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
  @override
  void didUpdateWidget(covariant FavoriteToggleButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_busy) _confirmed = widget.controller.isFavorite(widget.game);
  }

  Future<void> _toggle() async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final copy = widget.controller.copy;
    setState(() => _busy = true);
    var saved = false;
    try {
      saved = await widget.controller.toggleFavorite(widget.game);
    } catch (_) {
      saved = false;
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _confirmed = widget.controller.isFavorite(widget.game);
        });
      }
    }
    if (!saved && messenger?.mounted == true) {
      messenger!.showSnackBar(SnackBar(content: Text(copy.favoriteSaveFailed)));
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
      onPressed: _busy ? null : _toggle,
      icon: Stack(
        alignment: Alignment.center,
        children: [
          Opacity(
            opacity: _busy ? 0 : 1,
            child: FavoriteFeedbackIcon(
              selected: _confirmed,
              color: widget.color,
            ),
          ),
          if (_busy)
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: widget.color,
              ),
            ),
        ],
      ),
    );
  }
}
