import 'package:flutter/material.dart';
import '../shared/favorite_feedback.dart';
import '../shared/content_entrance.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/ui_tokens.dart';

import '../../app/state/app_controller.dart';
import '../../features/games/models/game_info.dart';
import '../../features/games/models/game_metadata_text.dart';
import 'game_cover.dart';
import '../shared/content_cards.dart';

class MobileLibraryContent extends StatefulWidget {
  const MobileLibraryContent({
    super.key,
    required this.controller,
    required this.onOpenGame,
    required this.onActivities,
    required this.onProfile,
  });

  final AppController controller;
  final ValueChanged<GameInfo> onOpenGame;
  final VoidCallback onActivities;
  final VoidCallback onProfile;

  @override
  State<MobileLibraryContent> createState() => _MobileLibraryContentState();
}

class _MobileLibraryContentState extends State<MobileLibraryContent> {
  final _search = TextEditingController();
  int _category = 0;

  static const _categories = [
    ('all', '全部', 'All'),
    ('strategy', '策略', 'Strategy'),
    ('family', '家庭', 'Family'),
    ('party', '聚会', 'Party'),
    ('cooperative', '合作', 'Co-op'),
    ('two_player', '双人', 'Two-player'),
  ];

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant MobileLibraryContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_refresh);
      widget.controller.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    _search.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  bool _matchesCategory(GameInfo game) {
    if (_category == 0) return true;
    if (_category == 5) return game.supportedPlayers.contains(2);
    return game.browseCategories.contains(_categories[_category].$1);
  }

  @override
  Widget build(BuildContext context) {
    final copy = widget.controller.copy;
    final query = _search.text.trim().toLowerCase();
    final games = widget.controller.games
        .where((game) {
          if (!_matchesCategory(game)) return false;
          if (query.isEmpty) return true;
          return <String>[
            game.title,
            game.subtitle,
            game.categoryLine,
            ...game.aliases,
            ...game.designers,
            ...game.keywords,
          ].any((value) => value.toLowerCase().contains(query));
        })
        .toList(growable: false);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  Image.asset(
                    'assets/desktop/home/logo.png',
                    width: 50,
                    height: 50,
                  ),
                  const SizedBox(width: 7),
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
                      ],
                    ),
                  ),
                  Stack(
                    children: [
                      IconButton(
                        tooltip: copy.localized('消息', 'Notifications'),
                        onPressed: widget.onActivities,
                        icon: Icon(
                          Icons.notifications_none_rounded,
                          color: AppPalette.of(context).textPrimary,
                        ),
                      ),
                      if (widget.controller.unreadActivityCount > 0)
                        Positioned(
                          right: 10,
                          top: 9,
                          child: CircleAvatar(
                            radius: 4,
                            backgroundColor: AppPalette.of(context).primary,
                          ),
                        ),
                    ],
                  ),
                  GestureDetector(
                    onTap: widget.onProfile,
                    child: const CircleAvatar(
                      radius: 19,
                      backgroundColor: Color(0xFFFFE6CE),
                      child: Icon(
                        Icons.person_rounded,
                        color: Color(0xFF955B3B),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: TextField(
                key: const ValueKey('mobile-library-search'),
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: copy.localized(
                    '搜索桌游 / 机制 / 作者',
                    'Search games / mechanics / designers',
                  ),
                  hintStyle: TextStyle(
                    color: AppPalette.of(context).textSecondary,
                    fontSize: 14,
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: AppPalette.of(context).textSecondary,
                  ),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: copy.localized('清除搜索', 'Clear search'),
                          onPressed: () => setState(_search.clear),
                          icon: const Icon(Icons.close_rounded),
                        ),
                  filled: true,
                  fillColor: AppPalette.of(context).inputSurface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            SizedBox(
              height: 44,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: _categories.length,
                separatorBuilder: (_, _) => const SizedBox(width: 7),
                itemBuilder: (context, index) {
                  final selected = _category == index;
                  return ChoiceChip(
                    key: ValueKey('mobile-library-category-$index'),
                    label: Text(
                      copy.localized(
                        _categories[index].$2,
                        _categories[index].$3,
                      ),
                    ),
                    selected: selected,
                    onSelected: (_) => setState(() => _category = index),
                    showCheckmark: false,
                    backgroundColor: AppPalette.of(context).surfaceContainer,
                    selectedColor: AppPalette.of(context).primary,
                    labelStyle: TextStyle(
                      color: selected
                          ? AppPalette.of(context).onPrimary
                          : AppPalette.of(context).textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: games.isEmpty
                  ? Center(
                      child: Text(copy.localized('没有找到桌游', 'No games found')),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = ((constraints.maxWidth - 20) / 172)
                            .floor()
                            .clamp(2, 4);
                        final width =
                            (constraints.maxWidth - 32 - (columns - 1) * 12) /
                            columns;
                        final coverHeight = width * 4 / 3;
                        final infoHeight = games
                            .map(
                              (game) =>
                                  _GameCard.infoHeight(context, game, width),
                            )
                            .reduce((a, b) => a > b ? a : b);
                        return GridView.builder(
                          key: const ValueKey('mobile-library-grid'),
                          padding: const EdgeInsets.fromLTRB(
                            UiTokens.pageInset,
                            0,
                            UiTokens.pageInset,
                            UiTokens.sectionGap,
                          ),
                          itemCount: games.length,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                mainAxisExtent: coverHeight + infoHeight,
                              ),
                          itemBuilder: (context, index) => ContentEntrance(
                            key: ValueKey(
                              'mobile-library-entrance-${games[index].id}',
                            ),
                            order: index,
                            animate: index < 6,
                            child: _GameCard(
                              controller: widget.controller,
                              game: games[index],
                              coverHeight: coverHeight,
                              onOpen: () => widget.onOpenGame(games[index]),
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

class _GameCard extends StatelessWidget {
  static double infoHeight(BuildContext context, GameInfo game, double width) {
    double measure(
      String text,
      TextStyle style,
      double maxWidth, {
      int? maxLines,
    }) {
      if (text.isEmpty) return 0;
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: maxLines,
      )..layout(maxWidth: maxWidth);
      final height = painter.height;
      painter.dispose();
      return height;
    }

    final body = ContentCardStyle.body(context);
    final scoreHeight = measure(
      game.score,
      ContentCardStyle.score(context),
      width - 24,
    );
    final iconHeight = MediaQuery.textScalerOf(context).scale(14) * 1.2;
    final ratingHeight = scoreHeight > iconHeight ? scoreHeight : iconHeight;
    return (52 +
            measure(
              game.title,
              ContentCardStyle.title(context),
              width - 24,
              maxLines: 2,
            ) +
            ContentAttributeTags.heightFor(context, _tags(game), width - 24) +
            ratingHeight.clamp(18.0, double.infinity) +
            measure(
              GameMetadataText.players(game.playerCount),
              body,
              width - 41,
            ) +
            measure(GameMetadataText.playTime(game.playTime), body, width - 41))
        .ceilToDouble();
  }

  const _GameCard({
    required this.controller,
    required this.game,
    required this.coverHeight,
    required this.onOpen,
  });

  final AppController controller;
  final GameInfo game;
  final double coverHeight;
  final VoidCallback onOpen;

  static List<String> _tags(GameInfo game) => game.categoryLine
      .split(RegExp(r'[/／,，·]'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .take(2)
      .toList();

  @override
  Widget build(BuildContext context) {
    final favorite = controller.isFavorite(game);
    final tags = _tags(game);
    return Material(
      color: AppPalette.of(context).surface,
      borderRadius: BorderRadius.circular(ContentCardStyle.radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('mobile-library-game-${game.id}'),
        borderRadius: BorderRadius.circular(ContentCardStyle.radius),
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: coverHeight,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    child: Center(
                      child: MobileGameCover(
                        controller: controller,
                        game: game,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 4,
                    top: 4,
                    child: FavoriteToggleButton(
                      key: ValueKey('mobile-library-favorite-${game.id}'),
                      controller: controller,
                      game: game,
                      filledTonal: true,
                      color: favorite
                          ? AppPalette.of(context).primary
                          : AppPalette.of(context).textSecondary,
                      style: IconButton.styleFrom(
                        backgroundColor: AppPalette.of(
                          context,
                        ).surface.withValues(alpha: .92),
                        foregroundColor: favorite
                            ? AppPalette.of(context).primary
                            : AppPalette.of(context).textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      game.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: ContentCardStyle.title(context),
                    ),
                    const SizedBox(height: 4),
                    if (tags.isNotEmpty) ContentAttributeTags(tags: tags),
                    const SizedBox(height: 8),
                    ContentRating(score: game.score),
                    const Spacer(),
                    _GameCardFact(
                      icon: Icons.people_alt_rounded,
                      text: GameMetadataText.players(game.playerCount),
                    ),
                    const SizedBox(height: 4),
                    _GameCardFact(
                      icon: Icons.schedule_rounded,
                      text: GameMetadataText.playTime(game.playTime),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GameCardFact extends StatelessWidget {
  const _GameCardFact({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 12, color: AppPalette.of(context).textSecondary),
      const SizedBox(width: 5),
      Expanded(
        child: Text(
          text,
          softWrap: true,
          style: ContentCardStyle.body(context),
        ),
      ),
    ],
  );
}
