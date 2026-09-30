import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../features/assistant/models/ai_conversation.dart';
import '../../features/games/models/game_info.dart';
import '../../app/state/app_controller.dart';
import '../../core/localization/app_copy.dart';
import 'game_cover.dart';

const _ink = Color(0xFF25242B);
const _muted = Color(0xFF85818A);
const _orange = Color(0xFFFF673F);
const _recommendationCardHeight = 154.0;

class MobileHomeContent extends StatefulWidget {
  const MobileHomeContent({
    super.key,
    required this.controller,
    required this.onSearch,
    required this.onOpenGame,
    required this.onOpenConversation,
    required this.onOpenAi,
    required this.onFavorites,
    required this.onSettings,
    required this.onActivities,
    required this.onRules,
  });

  final AppController controller;
  final VoidCallback onSearch;
  final ValueChanged<GameInfo> onOpenGame;
  final ValueChanged<AiConversation> onOpenConversation;
  final VoidCallback onOpenAi;
  final VoidCallback onFavorites;
  final VoidCallback onSettings;
  final VoidCallback onActivities;
  final VoidCallback onRules;

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
    final recentConversations =
        widget.controller.conversations
            .where((conversation) => conversation.hasUserMessages)
            .toList()
          ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
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
        : ((contentWidth - 10) / 2).clamp(240.0, 280.0).toDouble();
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
              icon: Icons.chat_bubble_outline_rounded,
              title: copy.localized('最近AI对话', 'Recent AI chats'),
            ),
            const SizedBox(height: 12),
            if (recentConversations.isEmpty)
              _emptyAiConversations(copy)
            else
              SizedBox(
                height: 132,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: recentConversations.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 11),
                  itemBuilder: (context, index) =>
                      _conversationCard(recentConversations[index], copy),
                ),
              ),
            const SizedBox(height: 25),
            _sectionHeader(
              icon: Icons.star_rounded,
              iconSize: 30,
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
                height: _recommendationCardHeight,
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
        copy.localized('规则资料库', 'Rules'),
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
        copy.localized('我的收藏', 'Favorites'),
        const Color(0xFFFFE9EC),
        widget.onFavorites,
      ),
    ];
    const double itemGap = 12;

    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth =
            (constraints.maxWidth - itemGap * (entries.length - 1)) /
            entries.length;
        final iconSize = itemWidth * 0.48;
        final borderRadius = itemWidth * 0.28;

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final entry in entries)
              SizedBox(
                width: itemWidth,
                child: InkWell(
                  onTap: entry.$4,
                  borderRadius: BorderRadius.circular(borderRadius),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: itemWidth,
                        height: itemWidth,
                        decoration: BoxDecoration(
                          color: entry.$3,
                          borderRadius: BorderRadius.circular(borderRadius),
                        ),
                        alignment: Alignment.center,
                        child: Icon(entry.$1, size: iconSize, color: _orange),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        entry.$2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
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
      },
    );
  }

  Widget _sectionHeader({
    required IconData icon,
    required String title,
    double iconSize = 22,
    String? action,
    VoidCallback? onAction,
  }) => Row(
    children: [
      Icon(icon, size: iconSize, color: _orange),
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

  Widget _emptyAiConversations(AppCopy copy) => Container(
    height: 102,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: const Color(0xFFF4EAE1)),
    ),
    child: TextButton(
      onPressed: widget.onOpenAi,
      child: Text(copy.localized('向 AI 提一个问题', 'Ask AI a question')),
    ),
  );

  Widget _conversationCard(
    AiConversation conversation,
    AppCopy copy,
  ) => SizedBox(
    width: 176,
    child: InkWell(
      key: ValueKey('mobile-recent-ai-${conversation.id}'),
      onTap: () => widget.onOpenConversation(conversation),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFF2E6DE)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.smart_toy_rounded, size: 18, color: _orange),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    conversation.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: _ink,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              conversation.messages.reversed
                  .map((message) => message.text.trim())
                  .firstWhere(
                    (text) => text.isNotEmpty,
                    orElse: () => copy.localized('继续对话', 'Continue chatting'),
                  ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: _muted, height: 1.3),
            ),
            const Spacer(),
            Text(
              copy.localized(
                '${conversation.updatedAt.month}月${conversation.updatedAt.day}日',
                '${conversation.updatedAt.month}/${conversation.updatedAt.day}',
              ),
              style: const TextStyle(fontSize: 10, color: _muted),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _recommendationCard(GameInfo game, double baseWidth) {
    final attributes = game.categoryLine
        .split(RegExp(r'\s*[/／·,，]\s*'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .take(2)
        .join(' / ');
    final painter = TextPainter(
      text: TextSpan(text: attributes, style: const TextStyle(fontSize: 10)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final cardWidth = (painter.width + 112).clamp(baseWidth, 280.0);
    painter.dispose();
    return SizedBox(
      width: cardWidth,
      height: _recommendationCardHeight,
      child: InkWell(
        key: ValueKey('mobile-recommendation-${game.id}'),
        onTap: () => widget.onOpenGame(game),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFF2E6DE)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: (cardWidth * 0.4).clamp(96.0, 112.0),
                child: MobileGameCover(
                  controller: widget.controller,
                  game: game,
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        game.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: _ink,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        attributes,
                        key: ValueKey(
                          'mobile-recommendation-attributes-${game.id}',
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.clip,
                        style: const TextStyle(fontSize: 10, color: _muted),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            size: 17,
                            color: Color(0xFFFF9F23),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            game.score,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w900,
                              color: _ink,
                              height: 1.1,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      Text(
                        game.summary.trim().isNotEmpty
                            ? game.summary
                            : game.heroTagline,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: Color(0xFF85818A),
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
