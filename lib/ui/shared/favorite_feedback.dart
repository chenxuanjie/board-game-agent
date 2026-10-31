import 'package:flutter/material.dart';
import '../../core/theme/app_motion.dart';
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
  });
  final bool selected;
  final Color? color;
  final double size;
  final IconData selectedIcon, unselectedIcon;
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
      widget.selected ? widget.selectedIcon : widget.unselectedIcon,
      color: widget.color,
      size: widget.size,
    ),
  );
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
