import 'package:flutter/material.dart';

import '../../app/state/app_controller.dart';

/// An empty result must not be mistaken for a successfully loaded catalogue.
class CatalogEmptyState extends StatelessWidget {
  const CatalogEmptyState({
    super.key,
    required this.controller,
    required this.emptyMessage,
    this.onClear,
    this.clearLabel,
    this.onBrowse,
    this.failureMessage,
  });

  final AppController controller;
  final String emptyMessage;
  final VoidCallback? onClear;
  final String? clearLabel;
  final VoidCallback? onBrowse;
  final String? failureMessage;

  @override
  Widget build(BuildContext context) {
    final copy = controller.copy;
    final noCatalog = !controller.hasGames;
    final loading =
        noCatalog &&
        controller.gameCatalogLoadState == LibraryLoadState.loading;
    final failure = noCatalog && controller.gameCatalogFailed;
    final idle =
        noCatalog &&
        controller.gameCatalogLoadState == LibraryLoadState.idle &&
        !failure;
    final message = loading
        ? copy.localized('正在加载桌游资料…', 'Loading game data…')
        : failure
        ? failureMessage ??
              copy.localized('暂时无法加载桌游资料', 'Game data is unavailable')
        : idle
        ? copy.localized('尚未加载桌游资料', 'Game data has not been loaded')
        : emptyMessage;
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading) ...[
              const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(height: 12),
            ],
            Text(message, textAlign: TextAlign.center),
            if (failure || idle)
              TextButton.icon(
                key: const ValueKey('catalog-empty-retry'),
                onPressed: controller.retryGameCatalog,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(
                  copy.localized(
                    failure ? '重试' : '加载',
                    failure ? 'Retry' : 'Load',
                  ),
                ),
              )
            else if (!loading && onClear != null)
              TextButton(
                onPressed: onClear,
                child: Text(
                  clearLabel ?? copy.localized('清除搜索', 'Clear search'),
                ),
              )
            else if (!loading && onBrowse != null)
              TextButton(
                onPressed: onBrowse,
                child: Text(copy.localized('搜索桌游', 'Search games')),
              ),
          ],
        ),
      ),
    );
  }
}
