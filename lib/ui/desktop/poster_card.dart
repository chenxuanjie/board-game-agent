import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/theme/app_motion.dart';

import '../../features/games/models/game_info.dart';
import '../../features/games/models/game_metadata_text.dart';
import '../../app/state/app_controller.dart';
import '../../core/theme/app_palette.dart';
import 'desktop_resolved_image.dart';

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
      label:
          '${game.title}，${GameMetadataText.players(game.playerCount)}，${game.complexity}',
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
                    duration: AppMotion.duration(context),
                    curve: AppMotion.curve,
                    transformAlignment: Alignment.topCenter,
                    transform: Matrix4.translationValues(
                      0,
                      _hovered && !AppMotion.reduced(context) ? -2 : 0,
                      0,
                    ),
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
                            ? palette.primary
                            : const Color(0x14FFFFFF),
                        width: 1,
                      ),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: _hovered
                              ? const Color(0x28000000)
                              : const Color(0x1C000000),
                          blurRadius: _hovered ? 14 : 8,
                          offset: Offset(0, _hovered ? 5 : 3),
                        ),
                      ],
                    ),
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
                                    Color(0x0FFFFFFF),
                                    Colors.transparent,
                                    Color(0x10000000),
                                  ],
                                  stops: <double>[0, 0.72, 1.0],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ),
                              ),
                            ),
                          ),
                        ],
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
    final String playTime = GameMetadataText.playTime(game.playTime);
    final String complexity = game.complexity.trim().isNotEmpty
        ? game.complexity
        : (game.learningDifficulty.trim().isNotEmpty
              ? game.learningDifficulty
              : '—');

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: AppMotion.duration(context, AppMotion.menu),
      curve: AppMotion.curve,
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
            borderRadius: BorderRadius.circular(12),
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
            borderRadius: BorderRadius.circular(12),
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
                      const SizedBox(height: 12),
                      const Divider(height: 1, color: Color(0x14FFFFFF)),
                      const SizedBox(height: 10),
                      const Text(
                        '游玩时长',
                        style: TextStyle(
                          color: Color(0xFF8F98A0),
                          fontSize: 10.5,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        playTime,
                        style: const TextStyle(
                          color: Color(0xFFC7D5E0),
                          fontSize: 11.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: _DesktopGameHoverStat(
                              label: '适合人数',
                              value: GameMetadataText.players(game.playerCount),
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
                              borderRadius: BorderRadius.circular(8),
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
      borderRadius: BorderRadius.circular(8),
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
