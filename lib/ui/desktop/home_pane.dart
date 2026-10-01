// Body layout adapted directly from the read-only Desktop reference.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../features/games/models/game_info.dart';
import '../../features/games/models/game_metadata_text.dart';
import '../../features/games/models/recent_game_record.dart';
import '../../app/state/app_controller.dart';
import 'desktop_resolved_image.dart';
import 'content_primitives.dart';
import 'desktop_responsive.dart';
import 'theme.dart';
import '../shared/hover_horizontal_scrollbar.dart';
import '../shared/hover_carousel_controls.dart';

class DesktopHomePane extends StatefulWidget {
  const DesktopHomePane({
    super.key,
    required this.controller,
    required this.onNavigate,
    required this.onOpenGame,
    required this.onOpenNationalDay,
  });
  final AppController controller;
  final ValueChanged<String> onNavigate;
  final ValueChanged<GameInfo> onOpenGame;
  final VoidCallback onOpenNationalDay;

  @override
  State<DesktopHomePane> createState() => _DesktopHomePaneState();
}

class _DesktopHomePaneState extends State<DesktopHomePane> {
  Timer? _nextDayTimer;

  @override
  void initState() {
    super.initState();
    _scheduleNextDay();
  }

  void _scheduleNextDay() {
    _nextDayTimer?.cancel();
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    _nextDayTimer = Timer(tomorrow.difference(now), () {
      if (!mounted) return;
      setState(() {});
      _scheduleNextDay();
    });
  }

  @override
  void dispose() {
    _nextDayTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final metrics = DesktopMetricsScope.of(context);
      final games = widget.controller.dailyRecommendedGames
          .map((g) => DesktopContentGame(g, widget.controller))
          .toList();
      void action(String label) {
        for (final g in games) {
          if (g.title == label) {
            widget.onOpenGame(g.data);
            return;
          }
        }
        final route = {
          '开始探索': 'games',
          '游戏库': 'games',
          '规则查询': 'library',
          'AI助手': 'assistant',
        }[label];
        if (route != null) widget.onNavigate(route);
      }

      final main = Column(
        children: [
          DesktopContentStatus(controller: widget.controller),
          if (!widget.controller.hasGames)
            TextButton(
              onPressed: () => widget.onNavigate('library'),
              child: const Text('打开资料库'),
            ),
          _MainColumn(
            controller: widget.controller,
            games: games,
            onNavigate: widget.onNavigate,
            onOpenGame: widget.onOpenGame,
            onOpenNationalDay: widget.onOpenNationalDay,
            onAction: action,
          ),
        ],
      );
      final right = _RightColumn(
        controller: widget.controller,
        onNavigate: widget.onNavigate,
        onAction: action,
      );
      return LayoutBuilder(
        builder: (context, constraints) {
          final wide = DesktopResponsive.homeUsesTwoColumns(
            constraints.maxWidth,
          );
          if (!wide) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [main, const SizedBox(height: 14), right],
            );
          }
          final rightWidth = (constraints.maxWidth * 0.22)
              .clamp(metrics.px(282), metrics.px(340))
              .toDouble();
          return DesktopContentColumns(
            wide: true,
            main: main,
            right: right,
            rightWidth: rightWidth,
            gap: metrics.px(14),
          );
        },
      );
    },
  );
}

class _MainColumn extends StatelessWidget {
  final AppController controller;
  final ValueChanged<String> onAction;
  final ValueChanged<String> onNavigate;
  final ValueChanged<GameInfo> onOpenGame;
  final VoidCallback onOpenNationalDay;

  final List<DesktopContentGame> games;
  const _MainColumn({
    required this.controller,
    required this.onAction,
    required this.onNavigate,
    required this.onOpenGame,
    required this.onOpenNationalDay,
    required this.games,
  });

  @override
  Widget build(BuildContext context) {
    final metrics = DesktopMetricsScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) => Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: DesktopResponsive.homeHeroWidthFor(constraints.maxWidth),
              child: _HeroBanner(
                onExplore: () => onAction('开始探索'),
                onOpenNationalDay: onOpenNationalDay,
                onOpenAssistant: () => onAction('AI助手'),
              ),
            ),
          ),
        ),
        SizedBox(height: metrics.px(11)),
        _SectionHeader(
          key: const ValueKey<String>('desktop-home-recommendation-header'),
          leading: SvgPicture.asset(
            'assets/desktop/home/flame_icon_hd.svg',
            key: const ValueKey<String>('desktop-home-library-flame'),
            width: metrics.px(25),
            height: metrics.px(25),
            semanticsLabel: '热门桌游',
          ),
          title: '今日推荐',
          onMore: () => onAction('游戏库'),
        ),
        SizedBox(height: metrics.px(10)),
        LayoutBuilder(
          builder: (context, constraints) {
            if (games.isEmpty) return const SizedBox.shrink();

            final gap = metrics.px(13);
            final minimumCardWidth = metrics.px(210);
            final fiveCardMinimumWidth = minimumCardWidth * 5 + gap * 4;

            if (constraints.maxWidth < fiveCardMinimumWidth) {
              final visibleGames = games.take(5).toList();
              return HoverHorizontalScrollbar(
                enabled: true,
                keyPrefix: 'desktop-home-recommendations',
                builder: (scrollController) => SingleChildScrollView(
                  controller: scrollController,
                  key: const ValueKey<String>(
                    'desktop-home-recommendation-row',
                  ),
                  scrollDirection: Axis.horizontal,
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < visibleGames.length; i++) ...[
                          if (i > 0) SizedBox(width: gap),
                          SizedBox(
                            width: minimumCardWidth,
                            child: _GameCard(
                              key: ValueKey<String>(
                                'desktop-home-recommendation-card-${visibleGames[i].data.id}',
                              ),
                              game: visibleGames[i],
                              cardWidth: minimumCardWidth,
                              onTap: () => onOpenGame(visibleGames[i].data),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            }

            final desiredCount = DesktopResponsive.homeRecommendationCountFor(
              constraints.maxWidth,
            );
            final count = desiredCount < games.length
                ? desiredCount
                : games.length;
            final fittedCount =
                count > 5 &&
                    constraints.maxWidth <
                        minimumCardWidth * count + gap * (count - 1)
                ? 5
                : count;
            final visibleGames = games.take(fittedCount).toList();
            final cardWidth = DesktopResponsive.homeRecommendationCardWidthFor(
              constraints.maxWidth,
              gap: gap,
              minimumWidth: minimumCardWidth,
              count: fittedCount,
            );
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                key: const ValueKey<String>('desktop-home-recommendation-row'),
                children: [
                  for (var i = 0; i < visibleGames.length; i++) ...[
                    if (i > 0) SizedBox(width: gap),
                    SizedBox(
                      width: cardWidth,
                      child: _GameCard(
                        key: ValueKey<String>(
                          'desktop-home-recommendation-card-${visibleGames[i].data.id}',
                        ),
                        game: visibleGames[i],
                        cardWidth: cardWidth,
                        onTap: () => onOpenGame(visibleGames[i].data),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
        SizedBox(height: metrics.px(13)),
        _RecentCard(
          controller: controller,
          onMore: () => onNavigate('games'),
          onOpenGame: onOpenGame,
        ),
      ],
    );
  }
}

class _HeroBanner extends StatefulWidget {
  final VoidCallback onExplore;
  final VoidCallback onOpenNationalDay;
  final VoidCallback onOpenAssistant;

  const _HeroBanner({
    required this.onExplore,
    required this.onOpenNationalDay,
    required this.onOpenAssistant,
  });

  @override
  State<_HeroBanner> createState() => _HeroBannerState();
}

class _HeroBannerState extends State<_HeroBanner> {
  static const _pageCount = 3;
  static const _interval = Duration(seconds: 5);
  static const _frameAspectRatio = 2169 / 725;
  // The first source has embedded side gutters; crop them into the shared frame.
  static const _firstBannerImageScale = 1.04;
  final PageController _controller = PageController();
  Timer? _timer;
  int _page = 0;
  int _targetPage = 0;
  int _transition = 0;
  bool _switching = false;
  bool _hovering = false;
  bool _keyboardFocused = false;

  bool get _showControls => _hovering || _keyboardFocused;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) {
      if (!mounted || _showControls || !_controller.hasClients) return;
      _goTo((_page + 1) % _pageCount);
    });
  }

  Future<void> _goTo(int page) async {
    if (!_controller.hasClients) return;
    _targetPage = page;
    final transition = ++_transition;
    _switching = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.jumpToPage(page);
    } else {
      await _controller.animateToPage(
        page,
        duration: const Duration(milliseconds: 480),
        curve: Curves.easeInOutCubic,
      );
    }
    if (!mounted || transition != _transition) return;
    _switching = false;
    _targetPage = _page;
  }

  void _step(int direction) =>
      unawaited(_goTo((_targetPage + direction + _pageCount) % _pageCount));

  void _setHover(bool hovering) {
    if (_hovering == hovering) return;
    setState(() => _hovering = hovering);
    if (!hovering) _startTimer();
  }

  void _setKeyboardFocus(bool focused) {
    if (_keyboardFocused == focused) return;
    setState(() => _keyboardFocused = focused);
    if (!focused) _startTimer();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _setHover(true),
      onExit: (_) => _setHover(false),
      child: Focus(
        canRequestFocus: false,
        onFocusChange: (focused) {
          if (!focused ||
              HardwareKeyboard.instance.logicalKeysPressed.isNotEmpty) {
            _setKeyboardFocus(focused);
          }
        },
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          _setKeyboardFocus(true);
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _step(-1);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            _step(1);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: ClipRRect(
          key: const ValueKey<String>('home-hero-frame'),
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: _frameAspectRatio,
            child: Stack(
              children: [
                PageView(
                  key: const ValueKey<String>('home-hero-carousel'),
                  controller: _controller,
                  onPageChanged: (page) => setState(() {
                    _page = page;
                    if (!_switching) _targetPage = page;
                  }),
                  children: [
                    _HeroImagePage(
                      key: const ValueKey<String>('home-hero-image-page-0'),
                      assetPath: 'assets/desktop/home/banner_tonight.png',
                      semanticLabel: '今晚玩什么：好游戏，好朋友，好时光',
                      onTap: widget.onExplore,
                      imageScale: _firstBannerImageScale,
                    ),
                    _HeroImagePage(
                      key: const ValueKey<String>('home-hero-page-1'),
                      assetPath: 'assets/desktop/home/banner_gathering.png',
                      semanticLabel: '国庆桌游聚会清单',
                      onTap: widget.onOpenNationalDay,
                    ),
                    _HeroImagePage(
                      key: const ValueKey<String>('home-hero-page-2'),
                      assetPath: 'assets/desktop/home/banner_ai.png',
                      semanticLabel: '桌游有 AI，拍照、提问、秒懂桌游规则',
                      onTap: widget.onOpenAssistant,
                    ),
                  ],
                ),
                _navigationButton(previous: true),
                _navigationButton(previous: false),
                Positioned(
                  right: 18,
                  bottom: 14,
                  child: Row(
                    children: List.generate(
                      _pageCount,
                      (index) => Padding(
                        padding: const EdgeInsets.only(left: 7),
                        child: Tooltip(
                          message: '第 ${index + 1} 页',
                          child: InkWell(
                            key: ValueKey<String>('home-hero-dot-$index'),
                            onTap: () => _goTo(index),
                            customBorder: const CircleBorder(),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              width: index == _page ? 18 : 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: index == _page
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.58),
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x33000000),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                            ),
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
      ),
    );
  }

  Widget _navigationButton({required bool previous}) => CarouselEdgeButton(
    visible: _showControls,
    previous: previous,
    keyPrefix: 'home-hero',
    onTap: () => _step(previous ? -1 : 1),
  );
}

class _HeroImagePage extends StatelessWidget {
  const _HeroImagePage({
    super.key,
    required this.assetPath,
    required this.semanticLabel,
    required this.onTap,
    this.imageScale = 1,
  });

  final String assetPath;
  final String semanticLabel;
  final VoidCallback onTap;
  final double imageScale;

  @override
  Widget build(BuildContext context) => HoverSurface(
    onTap: onTap,
    lift: 1,
    borderRadius: BorderRadius.zero,
    child: Transform.scale(
      scale: imageScale,
      child: Image.asset(
        assetPath,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        semanticLabel: semanticLabel,
      ),
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  final Widget? leading;
  final IconData? icon;
  final Color? iconColor;
  final String title;
  final VoidCallback onMore;
  final FontWeight titleWeight;
  final double? titleScaleCap;

  const _SectionHeader({
    super.key,
    this.leading,
    this.icon,
    this.iconColor,
    required this.title,
    required this.onMore,
    this.titleWeight = FontWeight.w800,
    this.titleScaleCap,
  }) : assert(leading != null || icon != null);

  @override
  Widget build(BuildContext context) {
    final metrics = DesktopMetricsScope.of(context);
    final titleSize = titleScaleCap == null
        ? metrics.font(19)
        : (19 * math.min(titleScaleCap!, math.max(1, metrics.scale)))
              .toDouble();
    return SizedBox(
      height: metrics.px(32),
      child: Row(
        children: [
          SizedBox(
            width: metrics.px(25),
            height: metrics.px(25),
            child:
                leading ?? Icon(icon, size: metrics.px(25), color: iconColor),
          ),
          SizedBox(width: metrics.px(8)),
          Text(
            title,
            style: TextStyle(fontSize: titleSize, fontWeight: titleWeight),
          ),
          const Spacer(),
          _TextLink(label: '查看更多', onTap: onMore),
        ],
      ),
    );
  }
}

class _TextLink extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _TextLink({required this.label, required this.onTap});

  @override
  State<_TextLink> createState() => _TextLinkState();
}

class _TextLinkState extends State<_TextLink> {
  bool hover = false;

  @override
  Widget build(BuildContext context) {
    final metrics = DesktopMetricsScope.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: InkWell(
        onTap: widget.onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.label,
              style: TextStyle(
                color: hover ? DesktopColors.orange : const Color(0xFF6C625A),
                fontSize: metrics.font(12),
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(width: metrics.px(2)),
            Icon(
              Icons.chevron_right_rounded,
              size: metrics.px(17),
              color: hover ? DesktopColors.orange : const Color(0xFF6C625A),
            ),
          ],
        ),
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  final DesktopContentGame game;
  final VoidCallback onTap;
  final double cardWidth;

  const _GameCard({
    super.key,
    required this.game,
    required this.onTap,
    required this.cardWidth,
  });

  @override
  Widget build(BuildContext context) {
    final metrics = DesktopMetricsScope.of(context);
    double cardFont(double value) =>
        value * (1 + math.min(0.08, math.max(0, metrics.scale - 1)));

    return HoverSurface(
      onTap: onTap,
      borderRadius: BorderRadius.circular(metrics.radius(9)),
      child: Container(
        padding: EdgeInsets.all(metrics.px(4)),
        decoration: BoxDecoration(
          color: DesktopColors.card,
          borderRadius: BorderRadius.circular(metrics.radius(9)),
          border: Border.all(color: const Color(0x0D8A6044)),
          boxShadow: [
            BoxShadow(
              color: Color(0x0B7E4D2B),
              blurRadius: metrics.px(8),
              offset: Offset(0, metrics.px(2)),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(metrics.radius(6)),
              child: AspectRatio(
                aspectRatio: 132 / 116,
                child: SizedBox(width: double.infinity, child: game.cover()),
              ),
            ),
            SizedBox(height: metrics.px(9)),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: metrics.px(6)),
              child: Tooltip(
                message: game.englishTitle == '-'
                    ? game.title
                    : '${game.title}\n${game.englishTitle}',
                child: Text(
                  game.title,
                  maxLines: 3,
                  style: TextStyle(
                    fontSize: cardFont(15),
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                    color: const Color(0xFF171412),
                  ),
                ),
              ),
            ),
            SizedBox(height: metrics.px(8)),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: metrics.px(6)),
              child: Row(
                children: [
                  Icon(
                    Icons.star_rounded,
                    color: const Color(0xFFFFA400),
                    size: metrics.px(16),
                  ),
                  SizedBox(width: metrics.px(4)),
                  Text(
                    game.score,
                    style: TextStyle(
                      fontSize: cardFont(16),
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                      color: const Color(0xFF171412),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: metrics.px(8)),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: metrics.px(6)),
              child: Wrap(
                spacing: metrics.px(6),
                runSpacing: metrics.px(3),
                children: [
                  _Tag(game.tagA),
                  if (game.tagB != '-') _Tag(game.tagB),
                ],
              ),
            ),
            SizedBox(height: metrics.px(14)),
            const Spacer(),
            Padding(
              padding: EdgeInsets.fromLTRB(
                metrics.px(6),
                0,
                metrics.px(6),
                metrics.px(7),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _GameCardFact(
                    icon: Icons.group_rounded,
                    text: cardWidth - metrics.px(20) >= metrics.px(230)
                        ? game.players
                        : GameMetadataText.cardPlayers(game.data.playerCount),
                    fullText: game.players,
                    fontSize: cardFont(10),
                  ),
                  SizedBox(width: metrics.px(8)),
                  _GameCardFact(
                    icon: Icons.schedule_rounded,
                    text: game.duration,
                    fullText: game.duration,
                    fontSize: cardFont(10),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GameCardFact extends StatelessWidget {
  const _GameCardFact({
    required this.icon,
    required this.text,
    required this.fullText,
    required this.fontSize,
  });

  final IconData icon;
  final String text;
  final String fullText;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final metrics = DesktopMetricsScope.of(context);
    return Tooltip(
      message: fullText,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: metrics.px(12), color: const Color(0xFF77706A)),
          SizedBox(width: metrics.px(4)),
          Text(
            text,
            key: ValueKey<String>('recommendation-fact-${icon.codePoint}'),
            softWrap: false,
            style: TextStyle(
              fontSize: fontSize,
              height: 1.15,
              color: const Color(0xFF77706A),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  const _Tag(this.text);

  @override
  Widget build(BuildContext context) {
    final metrics = DesktopMetricsScope.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: metrics.px(7),
        vertical: metrics.px(3),
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F2EE),
        borderRadius: BorderRadius.circular(metrics.radius(8)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5 * (1 + math.min(0.08, math.max(0, metrics.scale - 1))),
          fontWeight: FontWeight.w400,
          height: 1.15,
          color: const Color(0xFF77706A),
        ),
      ),
    );
  }
}

class _RecentCard extends StatelessWidget {
  final AppController controller;
  final VoidCallback onMore;
  final ValueChanged<GameInfo> onOpenGame;

  const _RecentCard({
    required this.controller,
    required this.onMore,
    required this.onOpenGame,
  });

  @override
  Widget build(BuildContext context) {
    final metrics = DesktopMetricsScope.of(context);
    final gamesBySlug = <String, GameInfo>{
      for (final game in controller.games) game.slug.trim().toLowerCase(): game,
    };
    final recentItems = controller.recentGameRecords
        .map(
          (record) =>
              (game: gamesBySlug[record.normalizedGameSlug], record: record),
        )
        .where((item) => item.game != null)
        .take(3)
        .toList();
    return _Panel(
      key: const ValueKey<String>('desktop-home-recent-panel'),
      height: 200,
      child: Padding(
        padding: metrics.insets(const EdgeInsets.fromLTRB(12, 8, 12, 8)),
        child: Column(
          children: [
            _SectionHeader(
              key: const ValueKey<String>('desktop-home-recent-header'),
              icon: Icons.history_rounded,
              iconColor: DesktopColors.orange,
              title: '最近浏览',
              onMore: onMore,
              titleWeight: FontWeight.w700,
              titleScaleCap: 1.08,
            ),
            SizedBox(height: metrics.px(10)),
            Expanded(
              child: recentItems.isEmpty
                  ? _RecentEmptyState(onTap: onMore)
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final metrics = DesktopMetricsScope.of(context);
                        final gap = metrics.px(14);
                        const slotCount = 3;
                        final naturalSlotWidth =
                            (constraints.maxWidth - gap * (slotCount - 1)) /
                            slotCount;
                        // Keep the preferred minimum when the panel has room,
                        // but never overflow a narrow panel just to satisfy it.
                        final slotWidth = naturalSlotWidth < metrics.px(118)
                            ? naturalSlotWidth
                            : math.min(metrics.px(150), naturalSlotWidth);
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var i = 0; i < recentItems.length; i++) ...[
                              if (i > 0) SizedBox(width: gap),
                              SizedBox(
                                width: slotWidth,
                                child: _RecentGameTile(
                                  key: ValueKey<String>(
                                    'desktop-recent-game-${recentItems[i].game!.id}',
                                  ),
                                  game: recentItems[i].game!,
                                  record: recentItems[i].record,
                                  controller: controller,
                                  onTap: () => onOpenGame(recentItems[i].game!),
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentEmptyState extends StatelessWidget {
  final VoidCallback onTap;

  const _RecentEmptyState({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: InkWell(
        key: const ValueKey<String>('desktop-home-recent-empty'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '还没有浏览记录',
                style: TextStyle(color: DesktopColors.secondaryText),
              ),
              SizedBox(height: 4),
              Text(
                '去游戏库看看 →',
                style: TextStyle(
                  color: DesktopColors.orange,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentGameTile extends StatelessWidget {
  final GameInfo game;
  final RecentGameRecord record;
  final AppController controller;
  final VoidCallback onTap;

  const _RecentGameTile({
    super.key,
    required this.game,
    required this.record,
    required this.controller,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final metrics = DesktopMetricsScope.of(context);
    final contentGame = DesktopContentGame(game, controller);
    final imagePath = game.bannerAssetPath.trim().isNotEmpty
        ? game.bannerAssetPath
        : game.coverAssetPath;
    return Semantics(
      button: true,
      label: '打开${contentGame.title}详情',
      child: HoverSurface(
        onTap: onTap,
        lift: 1,
        addShadow: false,
        borderRadius: BorderRadius.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(metrics.radius(6)),
              child: AspectRatio(
                key: ValueKey<String>('desktop-recent-thumbnail-${game.id}'),
                aspectRatio: 1.46,
                child: DesktopResolvedImage(
                  controller: controller,
                  assetPath: imagePath,
                  palette: controller.palette,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            SizedBox(height: metrics.px(5)),
            Text(
              contentGame.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: _recentFontSize(metrics, 13),
                fontWeight: FontWeight.w700,
                height: 1.12,
                color: const Color(0xFF1D1916),
              ),
            ),
            SizedBox(height: metrics.px(2)),
            Text(
              '上次浏览：${_formatRecentTime(record.viewedAt)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: _recentFontSize(metrics, 10.5),
                fontWeight: FontWeight.w400,
                height: 1.12,
                color: const Color(0xFF8A817A),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

double _recentFontSize(DesktopMetrics metrics, double value) =>
    value * math.min(1.08, math.max(1, metrics.scale));

String _formatRecentTime(DateTime viewedAt, {DateTime? now}) {
  final current = (now ?? DateTime.now()).toUtc();
  final elapsed = current.difference(viewedAt.toUtc());
  if (elapsed.isNegative || elapsed.inMinutes < 1) return '刚刚';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes} 分钟前';
  if (elapsed.inDays < 1) return '${elapsed.inHours} 小时前';
  if (elapsed.inDays < 30) return '${elapsed.inDays} 天前';
  final localDate = viewedAt.toLocal();
  return '${localDate.month} 月 ${localDate.day} 日';
}

class _RightColumn extends StatelessWidget {
  final AppController controller;
  final ValueChanged<String> onNavigate;
  final ValueChanged<String> onAction;

  const _RightColumn({
    required this.controller,
    required this.onNavigate,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final metrics = DesktopMetricsScope.of(context);
    return Column(
      children: [
        _ProfilePanel(controller: controller, onNavigate: onNavigate),
        SizedBox(height: metrics.px(12)),
        _QuickPanel(onAction: onAction),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  final Widget child;
  final double? height;

  const _Panel({super.key, required this.child, this.height});

  @override
  Widget build(BuildContext context) {
    final metrics = DesktopMetricsScope.of(context);
    return Container(
      height: height == null ? null : metrics.px(height!),
      decoration: BoxDecoration(
        color: DesktopColors.card,
        borderRadius: BorderRadius.circular(metrics.radius(12)),
        border: Border.all(color: const Color(0x0E8A6044)),
        boxShadow: [
          BoxShadow(
            color: Color(0x0A855A3E),
            blurRadius: metrics.px(10),
            offset: Offset(0, metrics.px(2)),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _HomePanelTypography {
  _HomePanelTypography(BuildContext context, DesktopMetrics metrics) {
    final theme = Theme.of(context).textTheme;
    heading = theme.titleMedium!.copyWith(
      fontSize: metrics.font(16),
      fontWeight: FontWeight.w600,
      height: 1.35,
      color: DesktopColors.text,
    );
    action = theme.titleSmall!.copyWith(
      fontSize: metrics.font(14),
      fontWeight: FontWeight.w500,
      height: 1.35,
      color: DesktopColors.text,
    );
    caption = theme.bodySmall!.copyWith(
      fontSize: metrics.font(12),
      fontWeight: FontWeight.w400,
      height: 1.4,
      color: DesktopColors.secondaryText,
    );
    value = theme.headlineSmall!.copyWith(
      fontSize: metrics.font(22),
      fontWeight: FontWeight.w600,
      height: 1.2,
      color: DesktopColors.text,
    );
  }

  late final TextStyle heading;
  late final TextStyle action;
  late final TextStyle caption;
  late final TextStyle value;
}

class _ProfilePanel extends StatelessWidget {
  final AppController controller;
  final ValueChanged<String> onNavigate;

  const _ProfilePanel({required this.controller, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final metrics = DesktopMetricsScope.of(context);
    final typography = _HomePanelTypography(context, metrics);
    final stats = [
      (
        value: '${controller.favoriteCount}',
        label: '我的喜欢',
        assetPath: 'assets/desktop/home/profile_favorite.png',
        onTap: () => onNavigate('favorites'),
        key: const ValueKey<String>('desktop-home-favorites-entry'),
      ),
      (
        value: '${controller.conversations.length}',
        label: 'AI对话',
        assetPath: 'assets/desktop/home/profile_ai_chat.png',
        onTap: () => onNavigate('assistant'),
        key: const ValueKey<String>('desktop-home-ai-entry'),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) => _Panel(
        key: const ValueKey<String>('desktop-home-profile-panel'),
        height: _profilePanelHeightFor(constraints.maxWidth / metrics.scale),
        child: Padding(
          padding: metrics.insets(const EdgeInsets.fromLTRB(14, 15, 14, 14)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('你好！', style: typography.heading),
              SizedBox(height: metrics.px(6)),
              Text('个人中心', style: typography.caption),
              SizedBox(height: metrics.px(13)),
              Expanded(
                child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: metrics.px(10),
                    mainAxisSpacing: metrics.px(10),
                    childAspectRatio: 1.55,
                  ),
                  itemCount: stats.length,
                  itemBuilder: (context, i) {
                    final s = stats[i];
                    return HoverSurface(
                      key: s.key,
                      onTap: s.onTap,
                      lift: 1,
                      borderRadius: BorderRadius.circular(metrics.radius(9)),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: metrics.px(10),
                          vertical: metrics.px(9),
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF9F5EF),
                          borderRadius: BorderRadius.circular(
                            metrics.radius(9),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(s.value, style: typography.value),
                                  SizedBox(height: metrics.px(3)),
                                  Text(s.label, style: typography.caption),
                                ],
                              ),
                            ),
                            Image.asset(
                              s.assetPath,
                              width: metrics.px(30),
                              height: metrics.px(30),
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickPanel extends StatelessWidget {
  final ValueChanged<String> onAction;

  const _QuickPanel({required this.onAction});

  @override
  Widget build(BuildContext context) {
    final metrics = DesktopMetricsScope.of(context);
    final typography = _HomePanelTypography(context, metrics);
    const actions = [
      ('规则查询', Icons.menu_book_rounded),
      ('AI助手', Icons.lightbulb_rounded),
    ];
    return LayoutBuilder(
      builder: (context, constraints) => _Panel(
        key: const ValueKey<String>('desktop-home-quick-panel'),
        height: _quickPanelHeightFor(constraints.maxWidth / metrics.scale),
        child: Padding(
          padding: metrics.insets(const EdgeInsets.all(10)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.bolt_rounded,
                    color: Color(0xFFFF6B42),
                    size: metrics.px(20),
                  ),
                  SizedBox(width: metrics.px(7)),
                  Text('快捷入口', style: typography.heading),
                ],
              ),
              SizedBox(height: metrics.px(9)),
              Expanded(
                child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: metrics.px(9),
                    mainAxisSpacing: metrics.px(9),
                    childAspectRatio: 2.35,
                  ),
                  itemCount: actions.length,
                  itemBuilder: (context, i) {
                    final a = actions[i];
                    return HoverSurface(
                      key: a.$1 == '规则查询'
                          ? const ValueKey<String>('home-quick-entry-rules')
                          : const ValueKey<String>('home-quick-entry-ai'),
                      onTap: () => onAction(a.$1),
                      lift: 1,
                      borderRadius: BorderRadius.circular(metrics.radius(9)),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: metrics.px(9),
                          vertical: metrics.px(6),
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF9F5EF),
                          borderRadius: BorderRadius.circular(
                            metrics.radius(9),
                          ),
                        ),
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  a.$2,
                                  color: const Color(0xFFFF5B43),
                                  size: metrics.px(20),
                                ),
                                SizedBox(width: metrics.px(6)),
                                Text(
                                  a.$1,
                                  maxLines: 1,
                                  style: typography.action,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

double _profilePanelHeightFor(double width) {
  const baseWidth = 282.0;
  const baseHeight = 172.0;
  const horizontalPadding = 28.0;
  const gridGap = 10.0;
  const cardAspectRatio = 1.55;
  final cardWidth = math.max(0, (width - horizontalPadding - gridGap) / 2);
  final gridHeight = cardWidth / cardAspectRatio;
  final baseCardWidth = (baseWidth - horizontalPadding - gridGap) / 2;
  final baseGridHeight = baseCardWidth / cardAspectRatio;
  return math.max(baseHeight, baseHeight + gridHeight - baseGridHeight);
}

double _quickPanelHeightFor(double width) {
  const baseHeight = 110.0;
  const horizontalPadding = 20.0;
  const gridGap = 9.0;
  const headingHeight = 23.0;
  const headingGap = 9.0;
  const cardAspectRatio = 2.35;
  final cardWidth = math.max(0, (width - horizontalPadding - gridGap) / 2);
  final gridHeight = cardWidth / cardAspectRatio;
  return math.max(
    baseHeight,
    horizontalPadding + headingHeight + headingGap + gridHeight,
  );
}
