import 'package:flutter/material.dart';
import '../../app/state/app_controller.dart';
import '../../core/theme/ui_tokens.dart';

/// One catalog lane, shared by every theme and platform. Dismissal applies only
/// to the home notice; the library always retains its failure and retry action.
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
      if (home && failure && !controller.showGameCatalogNotice) {
        return const SizedBox.shrink();
      }
      if (!failure && (controller.hasGames || !loading)) {
        return const SizedBox.shrink();
      }
      final copy = controller.copy;
      final colors = Theme.of(context).colorScheme;
      final message = loading
          ? controller.hasGames
                ? copy.localized(
                    '正在更新桌游资料，当前显示已有资料。',
                    'Updating game data; showing available games.',
                  )
                : copy.localized('正在加载桌游资料…', 'Loading game data…')
          : failure
          ? controller.hasGames
                ? copy.localized(
                    '当前显示已有资料，更新未完成。',
                    'Showing available games; update incomplete.',
                  )
                : controller.gameCatalogFailureMessage
          : copy.localized('正在加载桌游资料…', 'Loading game data…');
      final actions = Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (failure)
            TextButton.icon(
              key: const ValueKey('catalog-retry'),
              onPressed: loading ? null : controller.retryGameCatalog,
              icon: loading
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded, size: 18),
              label: Text(
                copy.localized(
                  loading ? '重试中' : '重试',
                  loading ? 'Retrying' : 'Retry',
                ),
              ),
            ),
          if (home && failure)
            IconButton(
              key: const ValueKey('catalog-dismiss'),
              tooltip: copy.localized('关闭提示', 'Dismiss notice'),
              onPressed: controller.dismissGameCatalogNotice,
              icon: const Icon(Icons.close_rounded, size: 18),
            ),
        ],
      );
      return Padding(
        key: const ValueKey('library-catalog-status'),
        padding: const EdgeInsets.only(bottom: UiTokens.itemGap),
        child: Semantics(
          liveRegion: true,
          child: Material(
            color: failure
                ? colors.error.withValues(alpha: .08)
                : colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(UiTokens.controlRadius),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: LayoutBuilder(
                builder: (context, box) {
                  final text = Row(
                    children: [
                      if (failure)
                        Icon(
                          Icons.error_outline_rounded,
                          color: colors.error,
                          size: 22,
                        )
                      else
                        const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          message,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  );
                  if (box.maxWidth < 480 ||
                      MediaQuery.textScalerOf(context).scale(14) > 20) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        text,
                        if (failure)
                          Align(
                            alignment: Alignment.centerRight,
                            child: actions,
                          ),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: text),
                      actions,
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
    },
  );
}
