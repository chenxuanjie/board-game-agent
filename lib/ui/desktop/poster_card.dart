import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/desktop_library_resource.dart';
import '../../models/game_info.dart';
import '../../state/app_controller.dart';
import '../../theme/app_palette.dart';
import '../widgets/desktop_resolved_image.dart';

class DesktopLibraryPosterCard extends StatefulWidget {
  const DesktopLibraryPosterCard({
    super.key,
    required this.controller,
    required this.game,
    required this.onTap,
    this.onOpenAssistant,
  });

  final AppController controller;
  final GameInfo game;
  final VoidCallback onTap;
  final VoidCallback? onOpenAssistant;

  @override
  State<DesktopLibraryPosterCard> createState() => _DesktopPosterCardState();
}

class _DesktopPosterCardState extends State<DesktopLibraryPosterCard> {
  static const double _previewWidth = 290;
  static const double _previewGap = 14;
  static const double _previewEstimatedHeight = 318;

  final LayerLink _previewLink = LayerLink();
  OverlayEntry? _previewEntry;
  Timer? _previewHideTimer;
  bool _hovered = false;
  bool _focused = false;
  bool _previewOnLeft = false;
  bool _previewAlignBottom = false;

  bool get _highlighted => _hovered || _focused;

  @override
  void dispose() {
    _previewHideTimer?.cancel();
    _removePreview();
    super.dispose();
  }

  void _handlePointerEnter() {
    _previewHideTimer?.cancel();
    if (!_hovered) setState(() => _hovered = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _hovered) _showPreview();
    });
  }

  void _handlePointerExit() {
    if (_hovered) setState(() => _hovered = false);
    _schedulePreviewHide();
  }

  void _schedulePreviewHide() {
    _previewHideTimer?.cancel();
    _previewHideTimer = Timer(const Duration(milliseconds: 110), () {
      if (mounted) _removePreview();
    });
  }

  void _showPreview() {
    _previewHideTimer?.cancel();
    if (_previewEntry != null) {
      _previewEntry!.markNeedsBuild();
      return;
    }

    final RenderObject? renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;

    final Offset globalOrigin = renderObject.localToGlobal(Offset.zero);
    final Rect cardRect = globalOrigin & renderObject.size;
    final Size viewport = MediaQuery.sizeOf(context);

    _previewOnLeft =
        cardRect.right + _previewGap + _previewWidth > viewport.width - 16;
    _previewAlignBottom =
        cardRect.top + _previewEstimatedHeight > viewport.height - 20 &&
        cardRect.bottom - _previewEstimatedHeight > 20;

    final OverlayState overlay = Overlay.of(context);
    _previewEntry = OverlayEntry(
      builder: (BuildContext overlayContext) {
        final Alignment targetAnchor = _previewAlignBottom
            ? (_previewOnLeft ? Alignment.bottomLeft : Alignment.bottomRight)
            : (_previewOnLeft ? Alignment.topLeft : Alignment.topRight);
        final Alignment followerAnchor = _previewAlignBottom
            ? (_previewOnLeft ? Alignment.bottomRight : Alignment.bottomLeft)
            : (_previewOnLeft ? Alignment.topRight : Alignment.topLeft);
        final Offset offset = Offset(
          _previewOnLeft ? -_previewGap : _previewGap,
          0,
        );

        // Overlay entries are laid out by a full-screen Stack. Keep the
        // follower in the original finite preview box so its child cannot
        // expand to the viewport and override _previewWidth.
        return Positioned(
          left: 0,
          top: 0,
          width: _previewWidth,
          child: CompositedTransformFollower(
            link: _previewLink,
            showWhenUnlinked: false,
            targetAnchor: targetAnchor,
            followerAnchor: followerAnchor,
            offset: offset,
            child: Material(
              type: MaterialType.transparency,
              child: MouseRegion(
                onEnter: (_) => _previewHideTimer?.cancel(),
                onExit: (_) => _schedulePreviewHide(),
                child: _DesktopGameHoverPreview(
                  controller: widget.controller,
                  game: widget.game,
                  onOpenAssistant: widget.onOpenAssistant == null
                      ? null
                      : () {
                          _removePreview();
                          widget.onOpenAssistant!.call();
                        },
                  enterFromRight: _previewOnLeft,
                ),
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(_previewEntry!);
  }

  void _removePreview() {
    _previewHideTimer?.cancel();
    _previewHideTimer = null;
    _previewEntry?.remove();
    _previewEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final GameInfo game = widget.game;
    final Color accent = Color(game.cardAccent);
    return Semantics(
      button: true,
      label: '${game.title}，${game.playerCount}，${game.complexity}',
      child: CompositedTransformTarget(
        link: _previewLink,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => _handlePointerEnter(),
          onExit: (_) => _handlePointerExit(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                child: InkWell(
                  onTap: () {
                    _removePreview();
                    widget.onTap();
                  },
                  onFocusChange: (value) => setState(() => _focused = value),
                  child: AnimatedContainer(
                    key: ValueKey<String>('desktop-poster-${game.id}'),
                    duration: const Duration(milliseconds: 380),
                    curve: const Cubic(0.25, 1, 0.5, 1),
                    transformAlignment: Alignment.topCenter,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, -1 / 1200)
                      // Keep the hover effect inside the grid cell. Scaling a
                      // GridView child makes it overlap neighbouring children,
                      // whose later paint order can visually cover the hovered
                      // poster and create a one-frame "jump". The 3D tilt,
                      // shadow, border and sheen still provide the lift effect
                      // without changing the card's 2D footprint.
                      ..rotateX(_hovered ? math.pi / 50 : 0.0),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: <Color>[
                          accent.withValues(alpha: 0.9),
                          Color.lerp(accent, palette.pageBackground, 0.72) ??
                              palette.pageBackground,
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color: _highlighted
                            ? const Color(0x94FFFFFF)
                            : const Color(0x14FFFFFF),
                        width: 1,
                      ),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: _hovered
                              ? const Color(0xE6000000)
                              : const Color(0xA6000000),
                          blurRadius: _hovered ? 42 : 14,
                          offset: Offset(0, _hovered ? 22 : 4),
                        ),
                        BoxShadow(
                          color: _hovered
                              ? const Color(0x8C000000)
                              : Colors.transparent,
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                        BoxShadow(
                          color: _hovered
                              ? const Color(0x4066C0F4)
                              : Colors.transparent,
                          blurRadius: 20,
                        ),
                      ],
                    ),
                    child: _DesktopPosterTone(
                      active: _hovered,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: Stack(
                          fit: StackFit.expand,
                          children: <Widget>[
                            DesktopResolvedImage(
                              controller: widget.controller,
                              assetPath: game.coverAssetPath,
                              palette: palette,
                              fit: BoxFit.cover,
                              placeholderBuilder: (BuildContext context) =>
                                  DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: <Color>[
                                          accent.withValues(alpha: 0.9),
                                          Color.lerp(
                                                accent,
                                                palette.pageBackground,
                                                0.72,
                                              ) ??
                                              palette.pageBackground,
                                        ],
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                      ),
                                    ),
                                    child: Center(
                                      child: Icon(
                                        _posterIcon(game),
                                        size: 78,
                                        color: accent,
                                      ),
                                    ),
                                  ),
                            ),
                            const IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: <Color>[
                                      Color(0x14FFFFFF),
                                      Colors.transparent,
                                      Color(0x26000000),
                                      Color(0x99000000),
                                    ],
                                    stops: <double>[0, 0.4, 0.75, 1.0],
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                  ),
                                ),
                              ),
                            ),
                            Positioned.fill(
                              child: IgnorePointer(
                                child: _DesktopPosterSheen(active: _hovered),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _posterIcon(GameInfo game) {
    final String value = '${game.categoryLine} ${game.title}'.toLowerCase();
    if (value.contains('城市') || value.contains('建筑')) {
      return Icons.location_city_rounded;
    }
    if (value.contains('卡') || value.contains('牌')) {
      return Icons.style_rounded;
    }
    if (value.contains('骰')) return Icons.casino_rounded;
    return Icons.extension_rounded;
  }
}

class _DesktopGameHoverPreview extends StatelessWidget {
  const _DesktopGameHoverPreview({
    required this.controller,
    required this.game,
    required this.enterFromRight,
    this.onOpenAssistant,
  });

  final AppController controller;
  final GameInfo game;
  final VoidCallback? onOpenAssistant;
  final bool enterFromRight;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final Color accent = Color(game.cardAccent);
    final String bannerPath = game.bannerAssetPath.trim().isNotEmpty
        ? game.bannerAssetPath
        : game.coverAssetPath;
    final String title = _previewTitle(game);
    final String status = _rulebookStatus(controller, game);
    final String playTime = game.playTime.trim().isEmpty ? '—' : game.playTime;
    final String perPlayer = game.perPlayerTime.trim().isEmpty
        ? '—'
        : game.perPlayerTime;
    final String complexity = game.complexity.trim().isNotEmpty
        ? game.complexity
        : (game.learningDifficulty.trim().isNotEmpty
              ? game.learningDifficulty
              : '—');

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      builder: (BuildContext context, double value, Widget? child) {
        final double dx = (enterFromRight ? 6 : -6) * (1 - value);
        return Opacity(
          opacity: value,
          child: Transform.translate(offset: Offset(dx, 0), child: child),
        );
      },
      child: SizedBox(
        key: ValueKey<String>('desktop-game-hover-preview-${game.id}'),
        width: _DesktopPosterCardState._previewWidth,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xF517212E),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0x5966C0F4)),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0xD9000000),
                blurRadius: 50,
                offset: Offset(0, 20),
              ),
              BoxShadow(color: Color(0x2E66C0F4), blurRadius: 22),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SizedBox(
                  height: 96,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: <Color>[
                              accent.withValues(alpha: 0.82),
                              const Color(0xFF132235),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                      ),
                      DesktopResolvedImage(
                        controller: controller,
                        assetPath: bannerPath,
                        palette: palette,
                        fit: BoxFit.cover,
                        placeholderBuilder: (_) => const SizedBox.shrink(),
                      ),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: <Color>[
                              Colors.transparent,
                              Color(0xF517212E),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF66C0F4),
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1, color: Color(0x14FFFFFF)),
                      const SizedBox(height: 10),
                      const Text(
                        '游戏时间',
                        style: TextStyle(
                          color: Color(0xFF8F98A0),
                          fontSize: 10.5,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              '单局：$playTime',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFC7D5E0),
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              '人均：$perPlayer',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                color: Color(0xFFC7D5E0),
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: _DesktopGameHoverStat(
                              label: '适合人数',
                              value: game.playerCount.trim().isEmpty
                                  ? '—'
                                  : game.playerCount,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _DesktopGameHoverStat(
                              label: '策略重度',
                              value: complexity,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        height: 36,
                        child: FilledButton(
                          onPressed: onOpenAssistant,
                          style: FilledButton.styleFrom(
                            padding: EdgeInsets.zero,
                            backgroundColor: const Color(0xFF75B022),
                            foregroundColor: const Color(0xFFD8F5A2),
                            disabledBackgroundColor: const Color(0xFF3A4A2A),
                            disabledForegroundColor: const Color(0xFF8F98A0),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          child: const Text(
                            '启动 AI 规则问答',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _previewTitle(GameInfo game) {
    final String title = game.title.trim();
    final String edition = game.editionLabel?.trim() ?? '';
    if (edition.isEmpty || title.contains(edition)) return '《$title》';
    return '《$title：$edition》';
  }

  static String _rulebookStatus(AppController controller, GameInfo game) {
    final List<DesktopLibraryResource> rulebooks = controller.libraryResources
        .where(
          (DesktopLibraryResource resource) =>
              resource.gameSlug == game.slug &&
              resource.type == DesktopLibraryResourceType.rulebook,
        )
        .toList(growable: false);
    if (rulebooks.any(
      (DesktopLibraryResource resource) =>
          resource.canOpen && !resource.isRemote,
    )) {
      return '规则手册已缓存 · 离线可用';
    }
    if (rulebooks.any((DesktopLibraryResource resource) => resource.canOpen)) {
      return '规则手册已同步 · 可直接打开';
    }
    if (rulebooks.isNotEmpty) return '规则手册已登记 · 待同步';
    return '规则资料待补充';
  }
}

class _DesktopGameHoverStat extends StatelessWidget {
  const _DesktopGameHoverStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: const Color(0xB30E1621),
      borderRadius: BorderRadius.circular(3),
      border: Border.all(color: const Color(0x0DFFFFFF)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(color: Color(0xFF8F98A0), fontSize: 9.5),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _DesktopPosterTone extends StatelessWidget {
  const _DesktopPosterTone({required this.active, required this.child});
  final bool active;
  final Widget child;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween<double>(begin: 0, end: active ? 1 : 0),
    duration: const Duration(milliseconds: 280),
    curve: Curves.ease,
    child: child,
    builder: (context, value, child) {
      // CSS brightness(1.05) followed by contrast(1.02).
      final double scale = 1 + 0.071 * value;
      final double bias = -2.55 * value;
      return ColorFiltered(
        colorFilter: ColorFilter.matrix(<double>[
          scale,
          0,
          0,
          0,
          bias,
          0,
          scale,
          0,
          0,
          bias,
          0,
          0,
          scale,
          0,
          bias,
          0,
          0,
          0,
          1,
          0,
        ]),
        child: child,
      );
    },
  );
}

// Matches test-all.html: steamSheenSweep, 800ms, with an oversized screen-blended band.
class _DesktopPosterSheen extends StatefulWidget {
  const _DesktopPosterSheen({required this.active});
  final bool active;
  @override
  State<_DesktopPosterSheen> createState() => _DesktopPosterSheenState();
}

class _DesktopPosterSheenState extends State<_DesktopPosterSheen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );

  @override
  void didUpdateWidget(covariant _DesktopPosterSheen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active) {
      if (widget.active && !MediaQuery.disableAnimationsOf(context)) {
        _sweep.forward(from: 0);
      } else {
        _sweep.reset();
      }
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(painter: _DesktopPosterSheenPainter(_sweep)),
  );
}

class _DesktopPosterSheenPainter extends CustomPainter {
  _DesktopPosterSheenPainter(this.animation) : super(repaint: animation);
  final Animation<double> animation;

  @override
  void paint(Canvas canvas, Size size) {
    final double time = animation.value;
    if (time == 0) return;
    const Curve easing = Cubic(0.2, 0.8, 0.25, 1);
    final double progress = easing.transform(time);
    final double opacity = time < 0.3
        ? 0.65 * easing.transform(time / 0.3)
        : 0.65 - 0.23 * easing.transform((time - 0.3) / 0.7);
    final double translation = -0.35 + 0.51 * progress;
    final Rect band = Rect.fromCenter(
      center: Offset.zero,
      width: size.width * 2,
      height: size.height * 2,
    );
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(
      size.width * (0.5 + translation * 2),
      size.height * (0.5 + translation * 2),
    );
    canvas.rotate(math.pi / 12);
    final Paint paint = Paint()
      ..blendMode = BlendMode.screen
      ..shader = LinearGradient(
        begin: const Alignment(-0.9063, -0.4226),
        end: const Alignment(0.9063, 0.4226),
        stops: const <double>[0.38, 0.46, 0.50, 0.54, 0.62],
        colors: <Color>[
          Colors.transparent,
          Colors.white.withValues(alpha: 0.05 * opacity),
          Colors.white.withValues(alpha: 0.22 * opacity),
          const Color(0xFF66C0F4).withValues(alpha: 0.12 * opacity),
          Colors.transparent,
        ],
      ).createShader(band);
    canvas.drawRect(band, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DesktopPosterSheenPainter oldDelegate) =>
      oldDelegate.animation != animation;
}
