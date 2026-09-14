// Body layout adapted directly from the read-only V4 reference.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../models/game_info.dart';
import '../../state/app_controller.dart';
import 'v4_content_primitives.dart';
import 'v4_theme.dart';

class V4HomePane extends StatelessWidget {
  const V4HomePane({
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
          .map((g) => V4ContentGame(g, controller))
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
          v4ContentPending(context, label);
        }
      }

      return V4ContentColumns(
        main: Column(
          children: [
            V4ContentStatus(controller: controller),
            if (!controller.hasGames)
              TextButton(
                onPressed: () => onNavigate('library'),
                child: const Text('打开资料库'),
              ),
            _MainColumn(games: games, onUnavailable: action),
          ],
        ),
        right: _RightColumn(onUnavailable: action),
        rightWidth: 282,
      );
    },
  );
}

class _MainColumn extends StatelessWidget {
  final ValueChanged<String> onUnavailable;

  final List<V4ContentGame> games;
  const _MainColumn({required this.onUnavailable, required this.games});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HeroBanner(
          onExplore: () => onUnavailable('开始探索'),
          onPending: () => onUnavailable('即将开放'),
          onOpenAssistant: () => onUnavailable('AI助手'),
        ),
        const SizedBox(height: 11),
        _SectionHeader(
          key: const ValueKey<String>('v4-home-recommendation-header'),
          leading: SvgPicture.asset(
            'assets/desktop/home/flame_icon_hd.svg',
            key: const ValueKey<String>('v4-home-library-flame'),
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
            final columns = (constraints.maxWidth / 145).floor().clamp(1, 5);
            final cardWidth =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: 13,
              children: [
                for (var i = 0; i < games.length; i++) ...[
                  SizedBox(
                    width: cardWidth,
                    child: _GameCard(
                      game: games[i],
                      onTap: () => onUnavailable(games[i].title),
                    ),
                  ),
                ],
              ],
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
                  _RecentCard(onUnavailable: onUnavailable),
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
                  child: _RecentCard(onUnavailable: onUnavailable),
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
                  color: V4Colors.secondaryText,
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
                color: hover ? V4Colors.orange : const Color(0xFF6C625A),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.chevron_right_rounded,
              size: 17,
              color: hover ? V4Colors.orange : const Color(0xFF6C625A),
            ),
          ],
        ),
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  final V4ContentGame game;
  final VoidCallback onTap;

  const _GameCard({required this.game, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return HoverSurface(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        height: 229,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: V4Colors.card,
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
                color: V4Colors.secondaryText,
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
  final ValueChanged<String> onUnavailable;
  const _RecentCard({required this.onUnavailable});
  @override
  Widget build(BuildContext context) => _Panel(
    height: 171,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
      child: Column(
        children: [
          _SectionHeader(
            icon: Icons.history_rounded,
            iconColor: V4Colors.orange,
            title: '最近浏览',
            onMore: () => onUnavailable('最近浏览'),
          ),
          const Expanded(
            child: Center(
              child: Text(
                '未开放',
                style: TextStyle(color: V4Colors.secondaryText),
              ),
            ),
          ),
        ],
      ),
    ),
  );
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
            iconColor: V4Colors.orange,
            title: '社区热门',
            onMore: () => onUnavailable('社区热门'),
          ),
          const Expanded(
            child: Center(
              child: Text(
                '未开放',
                style: TextStyle(color: V4Colors.secondaryText),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _RightColumn extends StatelessWidget {
  final ValueChanged<String> onUnavailable;

  const _RightColumn({required this.onUnavailable});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ProfilePanel(onUnavailable: onUnavailable),
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
              child: Image.asset('assets/v4/promo_art.png', fit: BoxFit.cover),
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

  const _Panel({required this.child, this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: V4Colors.card,
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
  final ValueChanged<String> onUnavailable;

  const _ProfilePanel({required this.onUnavailable});

  @override
  Widget build(BuildContext context) {
    const stats = [
      ('-', '我的收藏', Icons.menu_book_rounded, Color(0xFFB34DE9)),
      ('-', '心愿单', Icons.favorite_rounded, Color(0xFFFF5759)),
      ('-', '游戏记录', Icons.bar_chart_rounded, Color(0xFF19C889)),
      ('-', '想玩游戏', Icons.star_rounded, Color(0xFFFFA91C)),
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
              '个人中心 · 未开放',
              style: TextStyle(fontSize: 12, color: V4Colors.secondaryText),
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
                    onTap: () => onUnavailable(s.$2),
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
                                  s.$1,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 20,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  s.$2,
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    color: V4Colors.secondaryText,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(s.$3, color: s.$4, size: 25),
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
            iconColor: V4Colors.orange,
            title: '下次桌游聚会',
            onMore: () => onUnavailable('下次桌游聚会'),
          ),
          const Expanded(
            child: Center(
              child: Text(
                '未开放',
                style: TextStyle(color: V4Colors.secondaryText),
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
                                    color: V4Colors.secondaryText,
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
