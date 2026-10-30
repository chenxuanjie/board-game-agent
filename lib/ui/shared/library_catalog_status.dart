import 'package:flutter/material.dart';
import '../../app/state/app_controller.dart';
import 'inline_status_notice.dart';

/// Home and content pages share one dismissible, deduplicated catalog lane.
/// Content pages without a catalog use their blocking empty state instead.
class LibraryCatalogStatus extends StatelessWidget {
  const LibraryCatalogStatus({
    super.key,
    required this.controller,
    this.home = false,
  });
  final AppController controller;
  final bool home;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final loading =
          controller.gameCatalogLoadState == LibraryLoadState.loading;
      final failure = controller.gameCatalogFailed;
      if ((!home && !controller.hasGames) ||
          (failure && !controller.showGameCatalogNotice) ||
          (!failure && !loading)) {
        return const SizedBox.shrink();
      }
      final copy = controller.copy;
      final message = loading
          ? controller.hasGames
                ? copy.localized(
                    '正在更新桌游资料，当前显示已有资料。',
                    'Updating game data; showing available games.',
                  )
                : copy.localized('正在加载桌游资料…', 'Loading game data…')
          : controller.hasGames
          ? copy.localized(
              '当前显示已有资料，更新未完成。',
              'Showing available games; update incomplete.',
            )
          : controller.gameCatalogFailureMessage;
      return InlineStatusNotice(
        key: const ValueKey('library-catalog-status'),
        keyPrefix: 'catalog',
        message: message,
        revision: controller.gameCatalogRequestRevision,
        loading: loading,
        onRetry: failure ? controller.retryGameCatalog : null,
        retryLabel: copy.localized(
          loading ? '重试中' : '重试',
          loading ? 'Retrying' : 'Retry',
        ),
        dismissLabel: copy.localized('关闭提示', 'Dismiss notice'),
        onDismiss: controller.dismissGameCatalogNotice,
      );
    },
  );
}
