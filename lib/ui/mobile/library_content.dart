import 'package:flutter/material.dart';

import '../../app/state/app_controller.dart';
import '../../features/games/models/game_info.dart';
import '../../features/games/models/game_metadata_text.dart';
import 'game_cover.dart';

const _orange = Color(0xFFFF673F);
const _ink = Color(0xFF202635);
const _muted = Color(0xFF758197);

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
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: _ink,
                          ),
                        ),
                        Text(
                          copy.localized(
                            '好游戏 · 好伙伴 · 好时光',
                            'Good games · Better people',
                          ),
                          maxLines: 1,
                          style: const TextStyle(fontSize: 10, color: _orange),
                        ),
                      ],
                    ),
                  ),
                  Stack(
                    children: [
                      IconButton(
                        tooltip: copy.localized('消息', 'Notifications'),
                        onPressed: widget.onActivities,
                        icon: const Icon(
                          Icons.notifications_none_rounded,
                          color: _ink,
                        ),
                      ),
                      if (widget.controller.unreadActivityCount > 0)
                        const Positioned(
                          right: 10,
                          top: 9,
                          child: CircleAvatar(
                            radius: 4,
                            backgroundColor: _orange,
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
                  hintStyle: const TextStyle(color: _muted, fontSize: 14),
                  prefixIcon: const Icon(Icons.search_rounded, color: _muted),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: copy.localized('清除搜索', 'Clear search'),
                          onPressed: () => setState(_search.clear),
                          icon: const Icon(Icons.close_rounded),
                        ),
                  filled: true,
                  fillColor: const Color(0xFFF4F4F6),
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
                    backgroundColor: const Color(0xFFFFF1E9),
                    selectedColor: _orange,
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : _muted,
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
                        final columns = constraints.maxWidth < 360
                            ? 2
                            : constraints.maxWidth < 540
                            ? 3
                            : 4;
                        final width =
                            (constraints.maxWidth - 32 - (columns - 1) * 9) /
                            columns;
                        final coverHeight = width * 1.28;
                        return GridView.builder(
                          key: const ValueKey('mobile-library-grid'),
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          itemCount: games.length,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                crossAxisSpacing: 9,
                                mainAxisSpacing: 12,
                                mainAxisExtent: coverHeight + 134,
                              ),
                          itemBuilder: (context, index) => _GameCard(
                            controller: widget.controller,
                            game: games[index],
                            coverHeight: coverHeight,
                            onOpen: () => widget.onOpenGame(games[index]),
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

  @override
  Widget build(BuildContext context) {
    final copy = controller.copy;
    final favorite = controller.isFavorite(game);
    final tags = game.categoryLine
        .split(RegExp(r'[/／,，·]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .take(2)
        .toList();
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: ValueKey('mobile-library-game-${game.id}'),
        borderRadius: BorderRadius.circular(12),
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: coverHeight,
              width: double.infinity,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MobileGameCover(controller: controller, game: game),
                    Positioned(
                      right: 3,
                      top: 3,
                      child: IconButton(
                        key: ValueKey('mobile-library-favorite-${game.id}'),
                        tooltip: favorite
                            ? copy.localized('取消喜欢', 'Unlike')
                            : copy.localized('喜欢', 'Like'),
                        onPressed: () async {
                          final saved = await controller.toggleFavorite(game);
                          if (!saved && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  copy.localized(
                                    '收藏保存失败',
                                    'Could not save favorite',
                                  ),
                                ),
                              ),
                            );
                          }
                        },
                        icon: Icon(
                          favorite
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: Colors.white,
                          shadows: const [
                            Shadow(color: Colors.black54, blurRadius: 5),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(
                  Icons.star_rounded,
                  size: 18,
                  color: Color(0xFFFF9825),
                ),
                Text(
                  game.score.trim().isEmpty ? '-' : game.score,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
              ],
            ),
            Text(
              game.title,
              maxLines: 2,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: _ink,
              ),
            ),
            const SizedBox(height: 2),
            if (tags.isNotEmpty)
              Wrap(
                spacing: 3,
                runSpacing: 3,
                children: [
                  for (final tag in tags)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF1E9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        tag,
                        style: const TextStyle(
                          fontSize: 9,
                          color: Color(0xFFD85E2E),
                        ),
                      ),
                    ),
                ],
              ),
            const Spacer(),
            _GameCardFact(
              icon: Icons.people_alt_outlined,
              text: GameMetadataText.players(game.playerCount),
            ),
            const SizedBox(height: 4),
            _GameCardFact(
              icon: Icons.schedule_outlined,
              text: GameMetadataText.playTime(game.playTime),
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
      Icon(icon, size: 12, color: _muted),
      const SizedBox(width: 5),
      Expanded(
        child: Text(
          text,
          softWrap: true,
          style: const TextStyle(fontSize: 10, color: _muted, height: 1.15),
        ),
      ),
    ],
  );
}
