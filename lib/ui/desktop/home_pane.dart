// Body layout adapted directly from the read-only Desktop reference.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../models/game_info.dart';
import '../../models/recent_game_record.dart';
import '../../state/app_controller.dart';
import '../widgets/desktop_resolved_image.dart';
import 'content_primitives.dart';
import 'desktop_responsive.dart';
import 'theme.dart';

class DesktopHomePane extends StatelessWidget {
  const DesktopHomePane({
    super.key,
    required this.controller,
    required this.onNavigate,
    required this.onOpenGame,
  });
  final AppController controller;
  final ValueChanged<String> onNavigate;
  final ValueChanged<GameInfo> onOpenGame;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final games = controller.games
          .take(5)
          .map((g) => DesktopContentGame(g, controller))
          .toList();
      void action(String label) {
        for (final g in games) {
          if (g.title == label) {
            onOpenGame(g.data);
            return;
          }
        }
        final route = {
          '开始探索': 'games',
          '游戏库': 'games',
          '规则查询': 'library',
          'AI助手': 'assistant',
        }[label];
        if (route != null) {
          onNavigate(route);
        } else {
          desktopContentPending(context, label);
        }
      }

      final main = Column(
        children: [
          DesktopContentStatus(controller: controller),
          if (!controller.hasGames)
            TextButton(
              onPressed: () => onNavigate('library'),
              child: const Text('打开资料库'),
            ),
          _MainColumn(
            controller: controller,
            games: games,
            onNavigate: onNavigate,
            onOpenGame: onOpenGame,
            onUnavailable: action,
          ),
        ],
      );
      final right = _RightColumn(
        controller: controller,
        onNavigate: onNavigate,
        onUnavailable: action,
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
          return DesktopContentColumns(
            wide: true,
            main: main,
            right: right,
            rightWidth: 282,
          );
        },
      );
    },
  );
}

class _MainColumn extends StatelessWidget {
  final AppController controller;
  final ValueChanged<String> onUnavailable;
  final ValueChanged<String> onNavigate;
  final ValueChanged<GameInfo> onOpenGame;

  final List<DesktopContentGame> games;
  const _MainColumn({
    required this.controller,
    required this.onUnavailable,
    required this.onNavigate,
    required this.onOpenGame,
    required this.games,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) => Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: DesktopResponsive.homeHeroWidthFor(constraints.maxWidth),
              child: _HeroBanner(
                onExplore: () => onUnavailable('开始探索'),
                onPending: () => onUnavailable('即将开放'),
                onOpenAssistant: () => onUnavailable('AI助手'),
              ),
            ),
          ),
        ),
        const SizedBox(height: 11),
        _SectionHeader(
          key: const ValueKey<String>('desktop-home-recommendation-header'),
          leading: SvgPicture.asset(
            'assets/desktop/home/flame_icon_hd.svg',
            key: const ValueKey<String>('desktop-home-library-flame'),
            width: 25,
            height: 25,
            semanticsLabel: '热门桌游',
          ),
          title: '今日推荐',
          subtitle: '已收录的桌游',
          onMore: () => onUnavailable('游戏库'),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = 13.0;
            final cardWidth = DesktopResponsive.homeRecommendationCardWidthFor(
              constraints.maxWidth,
            );
            return SingleChildScrollView(
              key: const ValueKey<String>('desktop-home-recommendation-row'),
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < games.length; i++) ...[
                    if (i > 0) const SizedBox(width: gap),
                    SizedBox(
                      width: cardWidth,
                      child: _GameCard(
                        key: ValueKey<String>(
                          'desktop-home-recommendation-card-${games[i].data.id}',
                        ),
                        game: games[i],
                        onTap: () => onUnavailable(games[i].title),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 13),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 600) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _RecentCard(
                    controller: controller,
                    onMore: () => onNavigate('games'),
                    onOpenGame: onOpenGame,
                  ),
                  const SizedBox(height: 12),
                  _CommunityCard(onUnavailable: onUnavailable),
                ],
              );
            }
            final leftWidth = constraints.maxWidth * 0.52;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: leftWidth,
                  child: _RecentCard(
                    controller: controller,
                    onMore: () => onNavigate('games'),
                    onOpenGame: onOpenGame,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: _CommunityCard(onUnavailable: onUnavailable)),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _HeroBanner extends StatefulWidget {
  final VoidCallback onExplore;
  final VoidCallback onPending;
  final VoidCallback onOpenAssistant;

  const _HeroBanner({
    required this.onExplore,
    required this.onPending,
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
  bool _hovering = false;

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
      if (!mounted || _hovering || !_controller.hasClients) return;
      _goTo((_page + 1) % _pageCount);
    });
  }

  void _goTo(int page) {
    _controller.animateToPage(
      page,
      duration: const Duration(milliseconds: 480),
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _hovering = true,
      onExit: (_) => _hovering = false,
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
                onPageChanged: (page) => setState(() => _page = page),
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
                    onTap: widget.onPending,
                  ),
                  _HeroImagePage(
                    key: const ValueKey<String>('home-hero-page-2'),
                    assetPath: 'assets/desktop/home/banner_ai.png',
                    semanticLabel: '桌游有 AI，拍照、提问、秒懂桌游规则',
                    onTap: widget.onOpenAssistant,
                  ),
                ],
              ),
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
    );
  }
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
  final String? subtitle;
  final VoidCallback onMore;

  const _SectionHeader({
    super.key,
    this.leading,
    this.icon,
    this.iconColor,
    required this.title,
    this.subtitle,
    required this.onMore,
  }) : assert(leading != null || icon != null);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: Row(
        children: [
          SizedBox(
            width: 25,
            height: 25,
            child: leading ?? Icon(icon, size: 25, color: iconColor),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
          if (subtitle != null) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                subtitle!,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: DesktopColors.secondaryText,
                ),
              ),
            ),
          ] else
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
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.chevron_right_rounded,
              size: 17,
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

  const _GameCard({super.key, required this.game, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return HoverSurface(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        height: 229,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: DesktopColors.card,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: const Color(0x0D8A6044)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0B7E4D2B),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: double.infinity,
                height: 116,
                child: game.cover(),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              game.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
            Text(
              game.englishTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 8.6,
                color: DesktopColors.secondaryText,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 3),
            Row(
              children: [
                const Icon(
                  Icons.star_rounded,
                  color: Color(0xFFFFA400),
                  size: 15,
                ),
                Text(
                  game.score,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Row(
              children: [
                _Tag(game.tagA),
                const SizedBox(width: 6),
                _Tag(game.tagB),
              ],
            ),
            const Spacer(),
            Row(
              children: [
                const Icon(
                  Icons.group_rounded,
                  size: 11,
                  color: Color(0xFF77706A),
                ),
                const SizedBox(width: 2),
                Text(
                  game.players,
                  style: const TextStyle(
                    fontSize: 9.5,
                    color: Color(0xFF77706A),
                  ),
                ),
                const Spacer(),
                const Icon(
                  Icons.schedule_rounded,
                  size: 11,
                  color: Color(0xFF77706A),
                ),
                const SizedBox(width: 2),
                Flexible(
                  child: Text(
                    game.duration,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 9.2,
                      color: Color(0xFF77706A),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  const _Tag(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F2EE),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 9.5, color: Color(0xFF77706A)),
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
      height: 171,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
        child: Column(
          children: [
            _SectionHeader(
              key: const ValueKey<String>('desktop-home-recent-header'),
              icon: Icons.history_rounded,
              iconColor: DesktopColors.orange,
              title: '最近浏览',
              onMore: onMore,
            ),
            const SizedBox(height: 7),
            Expanded(
              child: recentItems.isEmpty
                  ? _RecentEmptyState(onTap: onMore)
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        const gap = 8.0;
                        final slotWidth = ((constraints.maxWidth - gap * 2) / 3)
                            .clamp(88.0, 126.0);
                        return Align(
                          alignment: Alignment.topLeft,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (var i = 0; i < recentItems.length; i++) ...[
                                if (i > 0) const SizedBox(width: gap),
                                SizedBox(
                                  width: slotWidth,
                                  child: _RecentGameTile(
                                    key: ValueKey<String>(
                                      'desktop-recent-game-${recentItems[i].game!.id}',
                                    ),
                                    game: recentItems[i].game!,
                                    record: recentItems[i].record,
                                    controller: controller,
                                    onTap: () =>
                                        onOpenGame(recentItems[i].game!),
                                  ),
                                ),
                              ],
                            ],
                          ),
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
    final contentGame = DesktopContentGame(game, controller);
    final imagePath = game.bannerAssetPath.trim().isNotEmpty
        ? game.bannerAssetPath
        : game.coverAssetPath;
    return Semantics(
      button: true,
      label: '打开${contentGame.title}详情',
      child: HoverSurface(
        onTap: onTap,
        lift: 2,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFCF8),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0x0F8A5A3C)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: AspectRatio(
                  key: ValueKey<String>('desktop-recent-thumbnail-${game.id}'),
                  aspectRatio: 16 / 9,
                  child: DesktopResolvedImage(
                    controller: controller,
                    assetPath: imagePath,
                    palette: controller.palette,
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                contentGame.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '上次浏览：${_formatRecentTime(record.viewedAt)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 8.5,
                  height: 1.15,
                  color: DesktopColors.secondaryText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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

class _CommunityCard extends StatelessWidget {
  final ValueChanged<String> onUnavailable;
  const _CommunityCard({required this.onUnavailable});
  @override
  Widget build(BuildContext context) => _Panel(
    height: 171,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
      child: Column(
        children: [
          _SectionHeader(
            icon: Icons.chat_bubble_rounded,
            iconColor: DesktopColors.orange,
            title: '社区热门',
            onMore: () => onUnavailable('社区热门'),
          ),
          const Expanded(
            child: Center(
              child: Text(
                '未开放',
                style: TextStyle(color: DesktopColors.secondaryText),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _RightColumn extends StatelessWidget {
  final AppController controller;
  final ValueChanged<String> onNavigate;
  final ValueChanged<String> onUnavailable;

  const _RightColumn({
    required this.controller,
    required this.onNavigate,
    required this.onUnavailable,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ProfilePanel(
          controller: controller,
          onNavigate: onNavigate,
          onUnavailable: onUnavailable,
        ),
        const SizedBox(height: 12),
        _MeetingPanel(onUnavailable: onUnavailable),
        const SizedBox(height: 12),
        _QuickPanel(onUnavailable: onUnavailable),
        const SizedBox(height: 12),
        HoverSurface(
          onTap: () => onUnavailable('桌游寄语'),
          lift: 1,
          borderRadius: BorderRadius.circular(12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 104,
              width: double.infinity,
              child: Image.asset(
                'assets/desktop/warmwood/promo_art.png',
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
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
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: DesktopColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x0E8A6044)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A855A3E),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _ProfilePanel extends StatelessWidget {
  final AppController controller;
  final ValueChanged<String> onNavigate;
  final ValueChanged<String> onUnavailable;

  const _ProfilePanel({
    required this.controller,
    required this.onNavigate,
    required this.onUnavailable,
  });

  @override
  Widget build(BuildContext context) {
    final stats = [
      (
        value: '${controller.favoriteCount}',
        label: '我的喜欢',
        assetPath: 'assets/desktop/home/profile_favorite.png',
        onTap: () => onNavigate('favorites'),
        key: const ValueKey<String>('desktop-home-favorites-entry'),
      ),
      (
        // The wishlist data layer is not available yet, so show its real
        // empty count instead of a placeholder value.
        value: '0',
        label: '想玩游戏',
        assetPath: 'assets/desktop/home/profile_wishlist.png',
        onTap: () => onUnavailable('想玩游戏'),
        key: null,
      ),
      (
        value: '${controller.conversations.length}',
        label: 'AI对话',
        assetPath: 'assets/desktop/home/profile_ai_chat.png',
        onTap: () => onNavigate('assistant'),
        key: const ValueKey<String>('desktop-home-ai-entry'),
      ),
      (
        // Activity records have no persisted data in the current product scope.
        value: '0',
        label: '我的活动',
        assetPath: 'assets/desktop/home/profile_vote.png',
        onTap: () => onUnavailable('我的活动'),
        key: null,
      ),
    ];
    return _Panel(
      height: 255,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 15, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '你好！',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text(
              '个人中心',
              style: TextStyle(
                fontSize: 12,
                color: DesktopColors.secondaryText,
              ),
            ),
            const SizedBox(height: 13),
            Expanded(
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 1.55,
                ),
                itemCount: stats.length,
                itemBuilder: (context, i) {
                  final s = stats[i];
                  return HoverSurface(
                    key: s.key,
                    onTap: s.onTap,
                    lift: 1,
                    borderRadius: BorderRadius.circular(9),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9F5EF),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.value,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 20,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  s.label,
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    color: DesktopColors.secondaryText,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Image.asset(
                            s.assetPath,
                            width: 52,
                            height: 52,
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
    );
  }
}

class _MeetingPanel extends StatelessWidget {
  final ValueChanged<String> onUnavailable;
  const _MeetingPanel({required this.onUnavailable});
  @override
  Widget build(BuildContext context) => _Panel(
    height: 157,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
      child: Column(
        children: [
          _SectionHeader(
            icon: Icons.calendar_month_rounded,
            iconColor: DesktopColors.orange,
            title: '下次桌游聚会',
            onMore: () => onUnavailable('下次桌游聚会'),
          ),
          const Expanded(
            child: Center(
              child: Text(
                '未开放',
                style: TextStyle(color: DesktopColors.secondaryText),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _QuickPanel extends StatelessWidget {
  final ValueChanged<String> onUnavailable;

  const _QuickPanel({required this.onUnavailable});

  @override
  Widget build(BuildContext context) {
    const actions = [
      ('随机推荐', '未开放', Icons.casino_rounded),
      ('找同城玩家', '未开放', Icons.group_rounded),
      ('规则查询', '快速查规则', Icons.menu_book_rounded),
      ('AI助手', '桌游问题随时问', Icons.lightbulb_rounded),
    ];
    return _Panel(
      height: 169,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.bolt_rounded, color: Color(0xFFFF6B42), size: 23),
                SizedBox(width: 7),
                Text(
                  '快捷入口',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Expanded(
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 9,
                  mainAxisSpacing: 9,
                  childAspectRatio: 2.35,
                ),
                itemCount: actions.length,
                itemBuilder: (context, i) {
                  final a = actions[i];
                  return HoverSurface(
                    key: a.$1 == '规则查询'
                        ? const ValueKey<String>('home-quick-entry-rules')
                        : null,
                    onTap: () => onUnavailable(a.$1),
                    lift: 1,
                    borderRadius: BorderRadius.circular(9),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9F5EF),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Row(
                        children: [
                          Icon(a.$3, color: const Color(0xFFFF5B43), size: 24),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  a.$1,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  a.$2,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: DesktopColors.secondaryText,
                                    fontSize: 9.5,
                                  ),
                                ),
                              ],
                            ),
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
    );
  }
}
