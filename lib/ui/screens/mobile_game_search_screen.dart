import 'package:flutter/material.dart';

import '../../models/game_info.dart';
import '../../state/app_controller.dart';
import '../widgets/mobile_game_cover.dart';

class MobileGameSearchScreen extends StatefulWidget {
  const MobileGameSearchScreen({
    super.key,
    required this.controller,
    required this.onOpenGame,
    this.favoritesOnly = false,
    this.recentOnly = false,
  });

  final AppController controller;
  final ValueChanged<GameInfo> onOpenGame;
  final bool favoritesOnly;
  final bool recentOnly;

  @override
  State<MobileGameSearchScreen> createState() => _MobileGameSearchScreenState();
}

class _MobileGameSearchScreenState extends State<MobileGameSearchScreen> {
  final _queryController = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant MobileGameSearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _queryController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final copy = widget.controller.copy;
    final query = _queryController.text.trim().toLowerCase();
    final games =
        (widget.favoritesOnly
                ? widget.controller.favoriteGames
                : widget.recentOnly
                ? widget.controller.recentlyViewedGames
                : widget.controller.games)
            .where(
              (game) =>
                  query.isEmpty ||
                  <String>[
                    game.title,
                    game.subtitle,
                    ...game.aliases,
                    ...game.designers,
                    ...game.keywords,
                    game.categoryLine,
                  ].any((value) => value.toLowerCase().contains(query)),
            )
            .toList(growable: false);

    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFFBF7),
        title: Text(
          copy.localized(
            widget.favoritesOnly
                ? '我的喜欢'
                : widget.recentOnly
                ? '最近浏览'
                : '搜索游戏',
            widget.favoritesOnly
                ? 'My likes'
                : widget.recentOnly
                ? 'Recently viewed'
                : 'Search games',
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: TextField(
                key: const ValueKey('mobile-game-query'),
                controller: _queryController,
                autofocus: !widget.favoritesOnly,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: copy.localized(
                    '游戏 / 机制 / 作者',
                    'Game / mechanism / designer',
                  ),
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Color(0xFFF0E5DD)),
                  ),
                ),
              ),
            ),
            Expanded(
              child: games.isEmpty
                  ? Center(
                      child: Text(
                        copy.localized(
                          widget.favoritesOnly && query.isEmpty
                              ? '还没有喜欢的桌游'
                              : widget.recentOnly && query.isEmpty
                              ? '还没有浏览记录'
                              : '没有找到桌游',
                          widget.favoritesOnly && query.isEmpty
                              ? 'No liked games yet'
                              : widget.recentOnly && query.isEmpty
                              ? 'No recently viewed games'
                              : 'No games found',
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: games.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final game = games[index];
                        return ListTile(
                          key: ValueKey('mobile-search-game-${game.id}'),
                          onTap: () => widget.onOpenGame(game),
                          tileColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: const BorderSide(color: Color(0xFFF1E9E2)),
                          ),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(7),
                            child: SizedBox(
                              width: 42,
                              height: 54,
                              child: MobileGameCover(
                                controller: widget.controller,
                                game: game,
                              ),
                            ),
                          ),
                          title: Text(
                            game.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            game.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
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
