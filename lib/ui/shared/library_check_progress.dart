import 'dart:async';
import 'package:flutter/material.dart';
import '../../app/state/app_controller.dart';
import 'smooth_progress.dart';

/// Keeps the list usable while its shared update check runs in the background.
class LibraryCheckProgress extends StatelessWidget {
  const LibraryCheckProgress({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final checking = controller.checkingLibraryUpdate;
      final failed =
          !checking &&
          controller.libraryAccessAllowed &&
          controller.libraryUpdateError != null;
      final copy = controller.copy;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SmoothProgress(
            visible: checking,
            height: 2,
            key: checking
                ? const ValueKey('library-check-progress-indicator')
                : null,
            label: copy.localized('正在检查桌游更新', 'Checking game updates'),
          ),
          if (failed)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      copy.localized(
                        '检查未完成，已有资料仍可浏览',
                        'Check incomplete. Saved games are still available.',
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('library-check-progress-retry'),
                    onPressed: () =>
                        unawaited(controller.checkForLibraryUpdatesQuick()),
                    child: Text(copy.localized('重试', 'Retry')),
                  ),
                ],
              ),
            ),
        ],
      );
    },
  );
}
