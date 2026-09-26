import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../features/games/models/game_info.dart';
import '../../app/state/app_controller.dart';
import '../../core/localization/app_copy.dart';
import 'game_cover.dart';

const _ink = Color(0xFF25242B);
const _muted = Color(0xFF85818A);
const _orange = Color(0xFFFF673F);

class MobileHomeContent extends StatefulWidget {
  const MobileHomeContent({
    super.key,
    required this.controller,
    required this.onSearch,
    required this.onOpenGame,
    required this.onOpenAi,
    required this.onFavorites,
    required this.onSettings,
    required this.onActivities,
    required this.onRules,
    required this.onRecentAll,
  });

  final AppController controller;
  final VoidCallback onSearch;
  final ValueChanged<GameInfo> onOpenGame;
  final VoidCallback onOpenAi;
  final VoidCallback onFavorites;
  final VoidCallback onSettings;
  final VoidCallback onActivities;
  final VoidCallback onRules;
  final VoidCallback onRecentAll;

  @override
  State<MobileHomeContent> createState() => _MobileHomeContentState();
}

class _MobileHomeContentState extends State<MobileHomeContent> {
  final PageController _bannerController = PageController();
  Timer? _bannerTimer;
  int _banner = 0;
  int _recommendationOffset = 0;

  @override
  void initState() {
    super.initState();
    _bannerTimer = Timer.periodic(const Duration(seconds: 7), (_) {
      if (!mounted || !_bannerController.hasClients) return;
      _bannerController.animateToPage(
        (_banner + 1) % 3,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _bannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final copy = widget.controller.copy;
    final recent = widget.controller.recentlyViewedGames.take(8).toList();
    final recommended = widget.controller.dailyRecommendedGames;
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final contentWidth =
        viewportWidth.clamp(0.0, kIsWeb ? 1200.0 : 560.0).toDouble() - 32;
    final visibleRecommendations = kIsWeb && contentWidth >= 600
        ? (contentWidth / 210).floor().clamp(3, 5)
        : 2;
    final recommendationWidth = kIsWeb && contentWidth >= 600
        ? (contentWidth - 10 * (visibleRecommendations - 1)) /
              visibleRecommendations
        : ((contentWidth - 10) / 2).clamp(154.0, 220.0).toDouble();
    final ordered = recommended.isEmpty
        ? const <GameInfo>[]
        : <GameInfo>[
            ...recommended.skip(_recommendationOffset % recommended.length),
            ...recommended.take(_recommendationOffset % recommended.length),
          ];
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: kIsWeb ? 1200 : 560),
        child: ListView(
          key: const ValueKey('mobile-home-scroll'),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
          children: [
            _header(copy),
            const SizedBox(height: 18),
            _carousel(copy),
            const SizedBox(height: 22),
            _shortcuts(copy),
            const SizedBox(height: 25),
            _sectionHeader(
              icon: Icons.history_rounded,
              title: copy.localized('继续游玩', 'Continue playing'),
              action: recent.isEmpty ? null : copy.localized('查看更多', 'See all'),
              onAction: recent.isEmpty ? null : widget.onRecentAll,
            ),
            const SizedBox(height: 12),
            if (recent.isEmpty)
              _emptyRecent(copy)
            else
              SizedBox(
                height: 157,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: recent.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 11),
                  itemBuilder: (context, index) =>
                      _recentCard(recent[index], copy),
                ),
              ),
            const SizedBox(height: 25),
            _sectionHeader(
              icon: Icons.star_rounded,
              title: copy.localized('推荐桌游', 'Recommended games'),
              action: copy.localized('换一批', 'Refresh'),
              onAction: recommended.length < 3
                  ? null
                  : () => setState(() => _recommendationOffset += 2),
            ),
            const SizedBox(height: 12),
            if (ordered.isEmpty)
              _emptyRecent(copy)
            else
              SizedBox(
                height: 160,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: ordered.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, index) =>
                      _recommendationCard(ordered[index], recommendationWidth),
                ),
              ),
            if (widget.controller.activities.isNotEmpty) ...[
              const SizedBox(height: 22),
              _activityCard(copy),
            ],
          ],
        ),
      ),
    );
  }

  Widget _header(AppCopy copy) => Row(
    children: [
      Image.asset('assets/desktop/home/logo.png', width: 52, height: 52),
      const SizedBox(width: 5),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              copy.localized('桌游伙伴', 'Board Game Buddy'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w900,
                color: _ink,
              ),
            ),
            Text(
              copy.localized('好游戏 · 好伙伴 · 好时光', 'Good games · Better people'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: Color(0xFFB89176)),
            ),
          ],
        ),
      ),
      IconButton(
        key: const ValueKey('mobile-home-search'),
        tooltip: copy.localized('搜索游戏', 'Search games'),
        onPressed: widget.onSearch,
        icon: const Icon(Icons.search_rounded, color: _ink),
      ),
      Stack(
        children: [
          IconButton(
            key: const ValueKey('mobile-home-activities'),
            tooltip: copy.localized('消息', 'Notifications'),
            onPressed: widget.onActivities,
            icon: const Icon(Icons.notifications_none_rounded, color: _ink),
          ),
          if (widget.controller.unreadActivityCount > 0)
            const Positioned(
              right: 11,
              top: 8,
              child: CircleAvatar(radius: 4, backgroundColor: _orange),
            ),
        ],
      ),
      GestureDetector(
        key: const ValueKey('mobile-home-profile'),
        onTap: widget.onSettings,
        child: const CircleAvatar(
          radius: 19,
          backgroundColor: Color(0xFFFFE6CE),
          child: Icon(Icons.person_rounded, color: Color(0xFF955B3B)),
        ),
      ),
    ],
  );

  Widget _carousel(AppCopy copy) {
    final bool wideWeb = kIsWeb && MediaQuery.sizeOf(context).width >= 600;
    const pages = [
      ('assets/mobile/home/gathering_banner.png', '让每一次\n相聚都有好游戏', '发现桌游的更多乐趣'),
      (
        'assets/desktop/home/banner_gathering.png',
        '好游戏，\n和朋友一起玩',
        '找到下一款喜欢的桌游',
      ),
      ('assets/desktop/home/banner_ai.png', '规则看不懂？\n直接问 AI', '桌游问题随时问'),
    ];
    return SizedBox(
      height: 191,
      child: Stack(
        children: [
          PageView.builder(
            controller: _bannerController,
            itemCount: pages.length,
            onPageChanged: (index) => setState(() => _banner = index),
            itemBuilder: (context, index) => ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    pages[index].$1,
                    fit: BoxFit.cover,
                    alignment: Alignment.centerRight,
                  ),
                  if (!wideWeb || index == 0)
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Color(0xF9FFF8EE),
                            Color(0xD7FFF4E6),
                            Color(0x00FFF4E6),
                          ],
                          stops: [0, .47, .82],
                        ),
                      ),
                    ),
                  if (!wideWeb || index == 0)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 16, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            copy.localized(
                              pages[index].$2,
                              index == 2
                                  ? 'Ask AI about\nthe rules'
                                  : 'Better games\ntogether',
                            ),
                            style: const TextStyle(
                              fontSize: 24,
                              height: 1.2,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF5D2419),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            copy.localized(
                              pages[index].$3,
                              'Discover your next favorite',
                            ),
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF945C45),
                            ),
                          ),
                          const Spacer(),
                          FilledButton.icon(
                            onPressed: index == 2
                                ? widget.onOpenAi
                                : widget.onSearch,
                            style: FilledButton.styleFrom(
                              backgroundColor: _orange,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              minimumSize: const Size(0, 39),
                            ),
                            icon: const Icon(
                              Icons.arrow_forward_rounded,
                              size: 17,
                            ),
                            iconAlignment: IconAlignment.end,
                            label: Text(
                              copy.localized(
                                index == 2 ? '立即提问' : '开始探索',
                                index == 2 ? 'Ask now' : 'Explore',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (wideWeb && index != 0)
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: index == 2 ? widget.onOpenAi : widget.onSearch,
                        child: Semantics(
                          label: copy.localized(
                            index == 2 ? '立即提问' : '开始探索',
                            index == 2 ? 'Ask now' : 'Explore',
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 14,
            bottom: 13,
            child: Row(
              children: [
                for (var index = 0; index < pages.length; index++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    margin: const EdgeInsets.only(left: 4),
                    width: index == _banner ? 15 : 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: index == _banner ? _orange : Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _shortcuts(AppCopy copy) {
    final entries = <(IconData, String, Color, VoidCallback)>[
      (
        Icons.search_rounded,
        copy.localized('搜索游戏', 'Search'),
        const Color(0xFFFFEDE2),
        widget.onSearch,
      ),
      (
        Icons.menu_book_rounded,
        copy.localized('规则资料', 'Rules'),
        const Color(0xFFFFF3D9),
        widget.onRules,
      ),
      (
        Icons.smart_toy_rounded,
        copy.localized('AI助手', 'AI helper'),
        const Color(0xFFFFEBE6),
        widget.onOpenAi,
      ),
      (
        Icons.favorite_rounded,
        copy.localized('我的喜欢', 'My likes'),
        const Color(0xFFFFE9EC),
        widget.onFavorites,
      ),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in entries)
          Expanded(
            child: InkWell(
              onTap: entry.$4,
              borderRadius: BorderRadius.circular(15),
              child: Column(
                children: [
                  AspectRatio(
                    aspectRatio: 1.15,
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: entry.$3,
                        borderRadius: BorderRadius.circular(17),
                      ),
                      child: Icon(entry.$1, size: 36, color: _orange),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    entry.$2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: _ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _sectionHeader({
    required IconData icon,
    required String title,
    String? action,
    VoidCallback? onAction,
  }) => Row(
    children: [
      Icon(icon, size: 22, color: _orange),
      const SizedBox(width: 7),
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w900,
            color: _ink,
          ),
        ),
      ),
      if (action != null && onAction != null)
        TextButton.icon(
          onPressed: onAction,
          label: Text(action),
          icon: const Icon(Icons.chevron_right_rounded, size: 17),
          iconAlignment: IconAlignment.end,
          style: TextButton.styleFrom(
            foregroundColor: _muted,
            padding: EdgeInsets.zero,
          ),
        ),
    ],
  );

  Widget _emptyRecent(AppCopy copy) => Container(
    height: 102,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: const Color(0xFFF4EAE1)),
    ),
    child: TextButton(
      onPressed: widget.onSearch,
      child: Text(copy.localized('去发现喜欢的桌游', 'Find a game to play')),
    ),
  );

  Widget _recentCard(GameInfo game, AppCopy copy) => SizedBox(
    width: 94,
    child: InkWell(
      key: ValueKey('mobile-recent-${game.id}'),
      onTap: () => widget.onOpenGame(game),
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              height: 110,
              width: 94,
              child: MobileGameCover(controller: widget.controller, game: game),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            game.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
          Text(
            copy.localized('继续上次', 'Continue'),
            style: const TextStyle(fontSize: 10, color: _muted),
          ),
        ],
      ),
    ),
  );

  Widget _recommendationCard(GameInfo game, double cardWidth) => SizedBox(
    width: cardWidth,
    child: InkWell(
      key: ValueKey('mobile-recommendation-${game.id}'),
      onTap: () => widget.onOpenGame(game),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFF2E6DE)),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 68,
                height: 142,
                child: MobileGameCover(
                  controller: widget.controller,
                  game: game,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    game.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: _ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    game.categoryLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 9, color: _muted),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      const Icon(
                        Icons.star_rounded,
                        size: 14,
                        color: Color(0xFFFF9F23),
                      ),
                      const SizedBox(width: 2),
                      Text(
                        game.score,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    game.playerCount,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: _muted),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    game.playTime,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: _muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _activityCard(AppCopy copy) {
    final activity = widget.controller.activities.first;
    return InkWell(
      onTap: widget.onActivities,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF2E7),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFFCE3D1)),
        ),
        child: Row(
          children: [
            const Icon(Icons.campaign_rounded, color: _orange, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    activity.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: _ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    activity.message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: _muted),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: _orange),
          ],
        ),
      ),
    );
  }
}
