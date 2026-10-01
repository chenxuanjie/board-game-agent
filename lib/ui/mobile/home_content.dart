import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/ui_tokens.dart';

import '../../features/assistant/models/ai_conversation.dart';
import '../../features/games/models/game_info.dart';
import '../../app/state/app_controller.dart';
import '../../core/localization/app_copy.dart';
import '../shared/content_cards.dart';
import 'game_content_card.dart';
import '../shared/hover_carousel_controls.dart';

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
    required this.onOpenNationalDay,
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
  final VoidCallback onOpenNationalDay;

  @override
  State<MobileHomeContent> createState() => _MobileHomeContentState();
}

class _MobileHomeContentState extends State<MobileHomeContent> {
  final PageController _bannerController = PageController();
  Timer? _bannerTimer;
  int _banner = 0;
  int _recommendationOffset = 0;
  bool _bannerInteracting = false;

  @override
  void initState() {
    super.initState();
    _bannerTimer = Timer.periodic(const Duration(seconds: 7), (_) {
      if (!mounted || !_bannerController.hasClients || _bannerInteracting) {
        return;
      }
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
            const SizedBox(height: UiTokens.sectionGap),
            _sectionHeader(
              icon: Icons.chat_bubble_outline_rounded,
              title: copy.localized('最近AI对话', 'Recent AI chats'),
            ),
            const SizedBox(height: 12),
            if (recentConversations.isEmpty)
              _emptyAiConversations(copy)
            else
              ContentCardStrip(
                keyPrefix: 'mobile-home-recent-ai',
                itemCount: recentConversations.length,
                itemBuilder: (context, index, metrics) =>
                    _conversationCard(recentConversations[index], copy),
              ),
            const SizedBox(height: UiTokens.sectionGap),
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
              ContentCardStrip(
                keyPrefix: 'mobile-home-recommendations',
                recommendation: true,
                itemCount: ordered.length,
                metadata: ordered.map(
                  (game) => ContentCardStyle.attributes(game.categoryLine),
                ),
                itemBuilder: (context, index, metrics) => GameContentCard(
                  key: ValueKey('mobile-recommendation-${ordered[index].id}'),
                  controller: widget.controller,
                  game: ordered[index],
                  metrics: metrics,
                  onTap: () => widget.onOpenGame(ordered[index]),
                  attributesKey: ValueKey(
                    'mobile-recommendation-attributes-${ordered[index].id}',
                  ),
                  description: ordered[index].summary.trim().isNotEmpty
                      ? ordered[index].summary
                      : ordered[index].heroTagline,
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
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppPalette.of(context).textPrimary,
              ),
            ),
            Text(
              copy.localized('好游戏 · 好伙伴 · 好时光', 'Good games · Better people'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Color(0xFFB89176)),
            ),
          ],
        ),
      ),
      IconButton(
        key: const ValueKey('mobile-home-search'),
        tooltip: copy.localized('搜索游戏', 'Search games'),
        onPressed: widget.onSearch,
        icon: Icon(
          Icons.search_rounded,
          color: AppPalette.of(context).textPrimary,
        ),
      ),
      Stack(
        children: [
          IconButton(
            key: const ValueKey('mobile-home-activities'),
            tooltip: copy.localized('消息', 'Notifications'),
            onPressed: widget.onActivities,
            icon: Icon(
              Icons.notifications_none_rounded,
              color: AppPalette.of(context).textPrimary,
            ),
          ),
          if (widget.controller.unreadActivityCount > 0)
            Positioned(
              right: 11,
              top: 8,
              child: CircleAvatar(
                radius: 4,
                backgroundColor: AppPalette.of(context).primary,
              ),
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
        '国庆聚会，\n一起玩桌游',
        '投票选出这次想玩的游戏',
      ),
      ('assets/desktop/home/banner_ai.png', '规则看不懂？\n直接问 AI', '桌游问题随时问'),
    ];
    return SizedBox(
      height:
          191 +
          (MediaQuery.textScalerOf(context).scale(24) - 24).clamp(
                0.0,
                double.infinity,
              ) *
              2.4 +
          (MediaQuery.textScalerOf(context).scale(14) - 14).clamp(
                0.0,
                double.infinity,
              ) *
              1.4,
      child: HoverCarouselControls(
        enabled: kIsWeb,
        keyPrefix: 'mobile-home-banner',
        onPrevious: () => _stepBanner(-1),
        onNext: () => _stepBanner(1),
        onInteractionChanged: (value) => _bannerInteracting = value,
        child: Stack(
          children: [
            PageView.builder(
              key: const ValueKey('mobile-home-banners'),
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
                    if (index == 1)
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          key: const ValueKey(
                            'mobile-home-national-day-banner',
                          ),
                          onTap: widget.onOpenNationalDay,
                          child: Semantics(button: true, label: '打开国庆专题'),
                        ),
                      ),
                    if (!wideWeb || index == 0)
                      IgnorePointer(
                        ignoring: index == 1,
                        child: Padding(
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
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF5D2419),
                                ),
                              ),
                              if (index == 1) ...[
                                const SizedBox(height: 6),
                                Text(
                                  copy.localized(
                                    pages[index].$3,
                                    'Discover your next favorite',
                                  ),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF945C45),
                                  ),
                                ),
                              ],
                              const Spacer(),
                              FilledButton.icon(
                                onPressed: index == 2
                                    ? widget.onOpenAi
                                    : index == 1
                                    ? widget.onOpenNationalDay
                                    : widget.onSearch,
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppPalette.of(
                                    context,
                                  ).primary,
                                  foregroundColor: AppPalette.of(
                                    context,
                                  ).onPrimary,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  minimumSize: const Size(48, 48),
                                ),
                                icon: const Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 17,
                                ),
                                iconAlignment: IconAlignment.end,
                                label: Text(
                                  copy.localized(
                                    index == 2
                                        ? '立即提问'
                                        : index == 1
                                        ? '投票想玩'
                                        : '开始探索',
                                    index == 2
                                        ? 'Ask now'
                                        : index == 1
                                        ? 'Vote to play'
                                        : 'Explore',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (wideWeb && index == 2)
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
                    InkWell(
                      key: ValueKey('mobile-home-banner-dot-$index'),
                      onTap: () => _bannerController.animateToPage(
                        index,
                        duration: const Duration(milliseconds: 420),
                        curve: Curves.easeInOut,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 4,
                        ),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          margin: const EdgeInsets.only(left: 4),
                          width: index == _banner ? 15 : 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: index == _banner
                                ? AppPalette.of(context).primary
                                : Colors.white,
                            borderRadius: BorderRadius.circular(4),
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
    );
  }

  void _stepBanner(int delta) {
    if (!_bannerController.hasClients) return;
    _bannerController.animateToPage(
      (_banner + delta + 3) % 3,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 420),
      curve: Curves.easeInOut,
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
        copy.localized('我的喜欢', 'Favorites'),
        const Color(0xFFFFE9EC),
        widget.onFavorites,
      ),
    ];
    const double itemGap = 12;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Keep the compact shortcut group in proportion to the banner on Web.
        final groupWidth = constraints.maxWidth.clamp(0.0, 520.0);
        final itemWidth =
            (groupWidth - itemGap * (entries.length - 1)) / entries.length;
        final tileSize = itemWidth.clamp(0.0, 88.0);
        final iconSize = (tileSize * 0.48).clamp(0.0, 40.0);
        final borderRadius = tileSize * 0.28;
        final labelSize = groupWidth >= 480 ? 13.0 : 12.0;

        return Center(
          child: SizedBox(
            width: groupWidth,
            child: Row(
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
                            width: tileSize,
                            height: tileSize,
                            decoration: BoxDecoration(
                              color:
                                  Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? AppPalette.of(context).surfaceContainer
                                  : entry.$3,
                              borderRadius: BorderRadius.circular(borderRadius),
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              entry.$1,
                              size: iconSize,
                              color: AppPalette.of(context).primary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            entry.$2,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: labelSize,
                              fontWeight: FontWeight.w700,
                              color: AppPalette.of(context).textPrimary,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
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
      Icon(icon, size: iconSize, color: AppPalette.of(context).primary),
      const SizedBox(width: 7),
      Expanded(child: Text(title, style: ContentCardStyle.section(context))),
      if (action != null && onAction != null)
        TextButton.icon(
          onPressed: onAction,
          label: Text(action),
          icon: const Icon(Icons.chevron_right_rounded, size: 17),
          iconAlignment: IconAlignment.end,
          style: TextButton.styleFrom(
            foregroundColor: AppPalette.of(context).textSecondary,
            padding: EdgeInsets.zero,
          ),
        ),
    ],
  );

  Widget _emptyRecent(AppCopy copy) => Container(
    height: 102,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: AppPalette.of(context).surface,
      borderRadius: BorderRadius.circular(UiTokens.cardRadius),
      border: Border.all(color: AppPalette.of(context).outline),
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
      color: AppPalette.of(context).surface,
      borderRadius: BorderRadius.circular(UiTokens.cardRadius),
      border: Border.all(color: AppPalette.of(context).outline),
    ),
    child: TextButton(
      onPressed: widget.onOpenAi,
      child: Text(copy.localized('向 AI 提一个问题', 'Ask AI a question')),
    ),
  );

  Widget _conversationCard(AiConversation conversation, AppCopy copy) =>
      ContentCardSurface(
        key: ValueKey('mobile-recent-ai-${conversation.id}'),
        onTap: () => widget.onOpenConversation(conversation),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.smart_toy_rounded,
                    size: 22,
                    color: AppPalette.of(context).primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      conversation.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ContentCardStyle.title(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                conversation.messages.reversed
                    .map((message) => message.text.trim())
                    .firstWhere(
                      (text) => text.isNotEmpty,
                      orElse: () => copy.localized('继续对话', 'Continue chatting'),
                    ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: ContentCardStyle.body(context),
              ),
              const Spacer(),
              Text(
                ContentCardStyle.relativeDate(
                  conversation.updatedAt,
                  copy.localized('zh', 'en') == 'zh',
                ),
                style: ContentCardStyle.body(context),
              ),
            ],
          ),
        ),
      );

  Widget _activityCard(AppCopy copy) {
    final activity = widget.controller.activities.first;
    return InkWell(
      onTap: widget.onActivities,
      borderRadius: BorderRadius.circular(UiTokens.groupRadius),
      child: Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          color: AppPalette.of(context).surfaceContainer,
          borderRadius: BorderRadius.circular(UiTokens.groupRadius),
          border: Border.all(color: AppPalette.of(context).outline),
        ),
        child: Row(
          children: [
            Icon(
              Icons.campaign_rounded,
              color: AppPalette.of(context).primary,
              size: 28,
            ),
            const SizedBox(width: UiTokens.itemGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    activity.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppPalette.of(context).textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    activity.message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppPalette.of(context).textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: AppPalette.of(context).primary,
            ),
          ],
        ),
      ),
    );
  }
}
