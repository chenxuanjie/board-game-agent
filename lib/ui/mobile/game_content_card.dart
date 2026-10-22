import 'package:flutter/material.dart';

import '../../app/state/app_controller.dart';
import '../../features/games/models/game_info.dart';
import '../shared/content_cards.dart';
import 'game_cover.dart';

class GameContentCard extends StatelessWidget {
  const GameContentCard({
    super.key,
    required this.controller,
    required this.game,
    required this.metrics,
    required this.onTap,
    this.description,
    this.attributesKey,
  });
  final AppController controller;
  final GameInfo game;
  final ContentCardMetrics metrics;
  final VoidCallback onTap;
  final String? description;
  final Key? attributesKey;

  @override
  Widget build(BuildContext context) => ContentCardSurface(
    onTap: onTap,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: metrics.coverWidth,
          child: ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: metrics.recommendation
                ? MobileGameCover(controller: controller, game: game)
                : Center(
                    child: MobileGameCover(
                      controller: controller,
                      game: game,
                      fit: BoxFit.contain,
                    ),
                  ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: metrics.recommendation ? 10 : 12,
              vertical: 10,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  game.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ContentCardStyle.title(context),
                ),
                const SizedBox(height: 4),
                Text(
                  ContentCardStyle.attributes(game.categoryLine),
                  key: attributesKey,
                  overflow: TextOverflow.clip,
                  style: metrics.recommendation
                      ? ContentCardStyle.compactBody(context)
                      : ContentCardStyle.body(context),
                ),
                const SizedBox(height: 8),
                ContentRating(score: game.score),
                if (description != null && description!.trim().isNotEmpty) ...[
                  const SizedBox(height: 22),
                  Text(
                    description!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: metrics.recommendation
                        ? ContentCardStyle.compactBody(context)
                        : ContentCardStyle.body(context),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
