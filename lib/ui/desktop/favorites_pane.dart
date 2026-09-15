import 'package:flutter/material.dart';

import '../../models/game_info.dart';
import '../../state/app_controller.dart';
import '../app_copy.dart';
import 'games_pane.dart';
import 'theme.dart';

class DesktopFavoritesPane extends StatelessWidget {
  const DesktopFavoritesPane({
    super.key,
    required this.controller,
    required this.showPreview,
    required this.onNavigate,
    required this.onOpenGame,
    required this.onToggleFavorite,
  });

  final AppController controller;
  final bool showPreview;
  final ValueChanged<String> onNavigate;
  final ValueChanged<GameInfo> onOpenGame;
  final ValueChanged<GameInfo> onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final games = controller.favoriteGames;
        if (games.isEmpty) {
          return _FavoritesEmptyState(
            copy: controller.copy,
            onOpenLibrary: () => onNavigate('games'),
          );
        }
        return DesktopGamesPane(
          controller: controller,
          sourceGames: games,
          showPreview: showPreview,
          onNavigate: onNavigate,
          onOpenGame: onOpenGame,
          onToggleFavorite: onToggleFavorite,
        );
      },
    );
  }
}

class _FavoritesEmptyState extends StatelessWidget {
  const _FavoritesEmptyState({required this.copy, required this.onOpenLibrary});

  final AppCopy copy;
  final VoidCallback onOpenLibrary;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 520,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.favorite_border_rounded,
                size: 54,
                color: DesktopColors.orange,
              ),
              const SizedBox(height: 14),
              Text(
                copy.favoritesEmptyTitle,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                copy.favoritesEmptyMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: DesktopColors.secondaryText,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                key: const ValueKey<String>('desktop-favorites-open-library'),
                onPressed: onOpenLibrary,
                icon: const Icon(Icons.casino_rounded),
                label: Text(copy.favoritesGoToLibrary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
