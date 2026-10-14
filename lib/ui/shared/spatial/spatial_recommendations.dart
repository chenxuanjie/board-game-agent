import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../app/state/app_controller.dart';
import '../../../features/games/models/game_info.dart';
import '../../desktop/desktop_resolved_image.dart';
import 'spatial_primitives.dart';

/// Same poster on the home preview and the complete ten-game slate.
class SpatialGamePoster extends StatelessWidget {
  const SpatialGamePoster({
    super.key,
    required this.controller,
    required this.game,
    required this.onOpen,
  });
  final AppController controller;
  final GameInfo game;
  final VoidCallback onOpen;
  static const aspectRatio = 141 / 216;
  @override
  Widget build(BuildContext context) => SpatialPoster(
    key: ValueKey('spatial-game-${game.id}'),
    title: game.title,
    match: '★ ${game.score}',
    genres: game.categoryLine,
    badge: '桌游',
    imageUrl: '',
    isCompact: true,
    image: DesktopResolvedImage(
      controller: controller,
      assetPath: game.coverAssetPath,
      palette: controller.palette,
      fit: BoxFit.cover,
    ),
    fallbackGradient: const [
      Color(0xFF192523),
      Color(0xFF6E7A72),
      Color(0xFF0C0E0F),
    ],
    onSelect: onOpen,
  );
}

class SpatialRecommendationsPage extends StatelessWidget {
  const SpatialRecommendationsPage({
    super.key,
    required this.controller,
    required this.onBack,
    required this.onOpenGame,
  });
  final AppController controller;
  final VoidCallback onBack;
  final ValueChanged<GameInfo> onOpenGame;
  @override
  Widget build(BuildContext context) {
    final games = controller.personalizedRecommendedGames;
    return Material(
      key: const ValueKey('spatial-recommendations-page'),
      type: MaterialType.transparency,
      child: LayoutBuilder(
        builder: (context, box) {
          final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
          final available = math.max(1.0, box.maxWidth - 44);
          final columns =
              ((available + 14) / (150 * textScale.clamp(1, 2) + 14))
                  .floor()
                  .clamp(1, 6);
          return CustomScrollView(
            key: const PageStorageKey('spatial-recommendations-scroll'),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 18, 22, 14),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: onBack,
                        tooltip: '返回',
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      const SizedBox(width: 4),
                      const Expanded(
                        child: Text(
                          '推荐桌游',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (games.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: Text('暂无可推荐的桌游')),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(22, 6, 22, 28),
                  sliver: SliverGrid.builder(
                    itemCount: games.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 18,
                      childAspectRatio: SpatialGamePoster.aspectRatio,
                    ),
                    itemBuilder: (context, index) => SpatialGamePoster(
                      controller: controller,
                      game: games[index],
                      onOpen: () => onOpenGame(games[index]),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
