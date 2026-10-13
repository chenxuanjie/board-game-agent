import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../app/state/app_controller.dart';
import '../../../core/theme/app_palette.dart';
import '../../../features/games/models/game_info.dart';
import '../../../features/games/models/game_metadata_text.dart';
import '../../desktop/desktop_resolved_image.dart';
import '../../desktop/content_primitives.dart';
import '../account_screen.dart';
import '../hover_horizontal_scrollbar.dart';
import '../hover_carousel_controls.dart';
import '../content_entrance.dart';
import 'cinema_surface.dart';

/// A real game catalogue presented with the Cinema composition on both shells.
class CinemaHomeContent extends StatefulWidget {
  const CinemaHomeContent({
    super.key,
    required this.controller,
    required this.onOpenGame,
    required this.onAskGame,
    required this.onLibrary,
    required this.onRankings,
    required this.onFavorites,
    required this.onActivities,
    this.onSearch,
    this.onTopic,
    this.scrollable = true,
  });
  final AppController controller;
  final ValueChanged<GameInfo> onOpenGame, onAskGame;
  final VoidCallback onLibrary, onRankings, onFavorites, onActivities;
  final VoidCallback? onSearch, onTopic;
  final bool scrollable;
  @override
  State<CinemaHomeContent> createState() => _CinemaHomeContentState();
}

class _CinemaHomeContentState extends State<CinemaHomeContent> {
  int _hero = 0;
  @override
  Widget build(BuildContext context) {
    final c = widget.controller, p = AppPalette.of(context);
    final compact = MediaQuery.sizeOf(context).width < 1100;
    final recommended = c.dailyRecommendedGames;
    final candidates = recommended.isEmpty ? c.games : recommended;
    final game = candidates.isEmpty
        ? null
        : candidates[_hero % candidates.length];
    final content = Column(
      key: const ValueKey('cinema-home'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (compact)
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: CinemaSurface(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Image.asset(
                      'assets/desktop/home/logo.png',
                      width: 40,
                      height: 40,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        c.copy.localized('桌游伙伴', 'Board Game Buddy'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    if (widget.onSearch != null)
                      IconButton(
                        onPressed: widget.onSearch,
                        tooltip: c.copy.localized('搜索', 'Search'),
                        icon: const Icon(Icons.search_rounded),
                      ),
                    IconButton(
                      onPressed: widget.onActivities,
                      tooltip: c.copy.localized('消息', 'Notifications'),
                      icon: const Icon(Icons.notifications_none_rounded),
                    ),
                    IconButton(
                      key: const ValueKey('cinema-account-entry'),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const AccountScreen(),
                        ),
                      ),
                      tooltip: c.copy.localized('账户', 'Account'),
                      icon: const Icon(Icons.person_outline_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (game == null)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(c.copy.localized('暂无桌游资料', 'No games available')),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final wide = !compact && width >= 760;
              final information = Padding(
                padding: EdgeInsets.all(wide ? 32 : 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      c.copy.localized('今晚玩什么', 'Choose your next game'),
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: p.textSecondary),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      game.title,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            fontSize: wide ? 40 : 30,
                            height: 1.18,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    if (game.subtitle.trim().isNotEmpty)
                      Text(
                        game.subtitle,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      children: [
                        Text(
                          '★ ${game.score}',
                          style: TextStyle(
                            color: p.warning,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(game.playerCount),
                        Text(game.playTime),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      game.heroTagline.isEmpty
                          ? game.summary
                          : game.heroTagline,
                      maxLines: wide ? 3 : 4,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 24),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton.icon(
                          key: const ValueKey('cinema-hero-details'),
                          onPressed: () => widget.onOpenGame(game),
                          icon: const Icon(Icons.info_outline_rounded),
                          label: Text(c.copy.localized('查看详情', 'View game')),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => widget.onAskGame(game),
                          icon: const Icon(Icons.auto_awesome_rounded),
                          label: Text(c.copy.localized('询问 AI', 'Ask AI')),
                        ),
                      ],
                    ),
                  ],
                ),
              );
              final image = AspectRatio(
                aspectRatio: wide ? 2.4 : 16 / 9,
                child: DesktopResolvedImage(
                  controller: c,
                  assetPath: game.bannerAssetPath.isEmpty
                      ? game.coverAssetPath
                      : game.bannerAssetPath,
                  palette: p,
                ),
              );
              Widget hero;
              if (wide) {
                hero = Stack(
                  children: [
                    Positioned.fill(child: image),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              p.pageBackground.withValues(alpha: .96),
                              p.pageBackground.withValues(alpha: .72),
                              p.pageBackground.withValues(alpha: .18),
                            ],
                            stops: const [0, .5, 1],
                          ),
                        ),
                      ),
                    ),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: math.max(320, width / 2.4),
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: math.min(640, width * .65),
                          ),
                          child: information,
                        ),
                      ),
                    ),
                  ],
                );
              } else {
                hero = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    image,
                    ColoredBox(color: p.surface, child: information),
                  ],
                );
              }
              return ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: HoverCarouselControls(
                  keyPrefix: 'cinema-hero',
                  fit: StackFit.passthrough,
                  enabled: candidates.length > 1,
                  child: hero,
                  onPrevious: () => setState(
                    () => _hero =
                        (_hero - 1 + candidates.length) % candidates.length,
                  ),
                  onNext: () =>
                      setState(() => _hero = (_hero + 1) % candidates.length),
                ),
              );
            },
          ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            TextButton.icon(
              onPressed: widget.onLibrary,
              icon: const Icon(Icons.grid_view_rounded),
              label: Text(c.copy.localized('全部桌游', 'All games')),
            ),
            TextButton.icon(
              onPressed: widget.onRankings,
              icon: const Icon(Icons.emoji_events_outlined),
              label: Text(c.copy.localized('排行榜', 'Rankings')),
            ),
            TextButton.icon(
              onPressed: widget.onFavorites,
              icon: const Icon(Icons.favorite_border_rounded),
              label: Text(c.copy.localized('我的喜欢', 'My likes')),
            ),
            if (widget.onTopic != null)
              TextButton.icon(
                onPressed: widget.onTopic,
                icon: const Icon(Icons.collections_bookmark_outlined),
                label: Text(c.copy.localized('桌游专题', 'Collections')),
              ),
          ],
        ),
        CinemaGameShelf(
          controller: c,
          title: c.copy.localized('今日推荐', 'Recommended today'),
          games: recommended,
          onOpenGame: widget.onOpenGame,
          onViewAll: widget.onLibrary,
        ),
        CinemaGameShelf(
          controller: c,
          title: c.copy.localized('最近浏览', 'Recently viewed'),
          games: c.recentlyViewedGames,
          onOpenGame: widget.onOpenGame,
        ),
        CinemaGameShelf(
          controller: c,
          title: c.copy.localized('我的喜欢', 'My likes'),
          games: c.favoriteGames,
          onOpenGame: widget.onOpenGame,
          onViewAll: widget.onFavorites,
        ),
      ],
    );
    return widget.scrollable
        ? SingleChildScrollView(
            key: const ValueKey('cinema-home-scroll'),
            padding: const EdgeInsets.all(16),
            child: content,
          )
        : content;
  }
}

class CinemaGameShelf extends StatelessWidget {
  const CinemaGameShelf({
    super.key,
    required this.controller,
    required this.title,
    required this.games,
    required this.onOpenGame,
    this.onViewAll,
  });
  final AppController controller;
  final String title;
  final List<GameInfo> games;
  final ValueChanged<GameInfo> onOpenGame;
  final VoidCallback? onViewAll;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
            if (onViewAll != null)
              TextButton(
                onPressed: onViewAll,
                child: Text(controller.copy.localized('查看全部', 'View all')),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (games.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              controller.copy.localized('暂无内容', 'Nothing here yet'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth < 600 ? 152.0 : 192.0;
              final scaler = MediaQuery.textScalerOf(context);
              return HoverHorizontalScrollbar(
                keyPrefix: 'cinema-shelf-$title',
                builder: (scroll) => SizedBox(
                  height:
                      width * 4 / 3 +
                      scaler.scale(16) * 2.6 +
                      scaler.scale(14) * 1.55 +
                      36,
                  child: ListView.separated(
                    controller: scroll,
                    scrollDirection: Axis.horizontal,
                    itemCount: games.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 16),
                    itemBuilder: (context, index) => ContentEntrance(
                      key: ValueKey('cinema-shelf-$title-${games[index].id}'),
                      animate: index < 6,
                      order: index,
                      child: SizedBox(
                        width: width,
                        child: CinemaPoster(
                          controller: controller,
                          game: games[index],
                          onOpen: () => onOpenGame(games[index]),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    ),
  );
}

class CinemaPoster extends StatelessWidget {
  const CinemaPoster({
    super.key,
    required this.controller,
    required this.game,
    required this.onOpen,
    this.details = false,
  });
  final AppController controller;
  final GameInfo game;
  final VoidCallback onOpen;
  final bool details;
  @override
  Widget build(BuildContext context) => HoverSurface(
    onTap: onOpen,
    borderRadius: BorderRadius.circular(16),
    child: Material(
      color: AppPalette.of(context).surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: ValueKey('cinema-game-${game.id}'),
        borderRadius: BorderRadius.circular(16),
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              child: AspectRatio(
                aspectRatio: 3 / 4,
                child: DesktopResolvedImage(
                  controller: controller,
                  assetPath: game.coverAssetPath,
                  palette: AppPalette.of(context),
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Text(
                game.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Text(
                '★ ${game.score}',
                style: TextStyle(color: AppPalette.of(context).warning),
              ),
            ),
            if (details)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Text(
                  '${GameMetadataText.players(game.playerCount)} · ${GameMetadataText.playTime(game.playTime)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
