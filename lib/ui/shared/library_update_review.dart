import 'dart:async';
import 'package:flutter/material.dart';
import '../../app/state/app_controller.dart';
import '../../core/theme/app_motion.dart';
import '../../features/library/models/remote_library_update.dart';

Future<void> showLibraryUpdateReview(
  BuildContext context,
  AppController controller,
) async {
  if (controller.appUpdateInProgress) return;
  controller.dismissPendingLibraryUpdatePrompt();
  final narrow = MediaQuery.sizeOf(context).width < 700;
  if (narrow) {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            LibraryUpdateReview(controller: controller, fullPage: true),
      ),
    );
  } else {
    await showDialog<void>(
      context: context,
      animationStyle: AppMotion.menuStyle(context),
      builder: (_) => LibraryUpdateReview(controller: controller),
    );
  }
}

class LibraryUpdateReview extends StatefulWidget {
  const LibraryUpdateReview({
    super.key,
    required this.controller,
    this.fullPage = false,
  });
  final AppController controller;
  final bool fullPage;
  @override
  State<LibraryUpdateReview> createState() => _LibraryUpdateReviewState();
}

class _LibraryUpdateReviewState extends State<LibraryUpdateReview> {
  RemoteLibraryUpdate? _applied;
  @override
  void initState() {
    super.initState();
    if (widget.controller.pendingLibraryUpdate == null) {
      unawaited(widget.controller.checkForLibraryUpdates());
    }
  }

  Future<void> _apply() async {
    final controller = widget.controller;
    final update = controller.pendingLibraryUpdate;
    final revision = controller.libraryContentRevision;
    await controller.applyPendingLibraryUpdate();
    if (mounted && controller.libraryContentRevision > revision) {
      setState(() => _applied = update);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final copy = c.copy;
      final busy = c.applyingLibraryUpdate || c.checkingLibraryUpdate;
      final update = c.pendingLibraryUpdate ?? _applied;
      final error = c.libraryUpdateError;
      final entries = update?.changes.isNotEmpty == true
          ? update!.changes
          : [
              for (final path in update?.changedPaths ?? <String>[])
                RemoteLibraryChange(path: path, title: path.split('/').last),
            ];
      final content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (busy) ...[
            LinearProgressIndicator(
              value: c.applyingLibraryUpdate && update != null
                  ? c.libraryUpdateCompleted / update.changedCount
                  : null,
            ),
            const SizedBox(height: 12),
            Text(
              c.applyingLibraryUpdate
                  ? '${copy.updatingNow} ${c.libraryUpdateCompleted}/${update?.changedCount ?? 0}'
                  : copy.localized('正在检查资料更新…', 'Checking for updates…'),
            ),
          ] else if (_applied != null) ...[
            Text(
              copy.localized('资料已更新', 'Library updated'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(copy.libraryUpdateChangeSummary(_applied!.changedCount)),
          ] else if (update != null) ...[
            Text(
              copy.libraryUpdateChangeSummary(update.changedCount),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                for (final entry in update.changedResourceCounts.entries)
                  Text(
                    '${copy.libraryUpdateResourceLabel(entry.key)} ${entry.value}',
                  ),
              ],
            ),
          ] else if (error == null)
            Text(copy.localized('资料已是最新。', 'Your library is up to date.')),
          if (error != null) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
          if (entries.isNotEmpty) ...[
            const SizedBox(height: 16),
            for (final entry in entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${copy.libraryUpdateKindLabel(entry.kind)} · ${entry.title == 'catalog' ? copy.libraryUpdateResourceLabel(RemoteLibraryResourceType.catalog) : entry.title}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entry.fields.isNotEmpty
                          ? entry.fields
                                .map(
                                  (field) =>
                                      entry.valueChanges.containsKey(field)
                                      ? '${copy.libraryUpdateFieldLabel(field)}：${entry.valueChanges[field]}'
                                      : copy.libraryUpdateFieldLabel(field),
                                )
                                .toSet()
                                .join(' · ')
                          : copy.libraryUpdateResourceLabel(
                              RemoteLibraryUpdate.resourceTypeForPath(
                                entry.path,
                              ),
                            ),
                    ),
                    if (entry.path != 'assets/catalog.json' &&
                        !entry.path.endsWith('/game.json') &&
                        !entry.path.endsWith('/manifest.json'))
                      Text(
                        entry.path.split('/').last,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
          ],
        ],
      );
      final actions = [
        TextButton(
          key: const ValueKey('library-update-later'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            copy.localized(
              c.applyingLibraryUpdate
                  ? '后台继续'
                  : _applied != null
                  ? '关闭'
                  : '暂不更新',
              c.applyingLibraryUpdate
                  ? 'Continue in background'
                  : _applied != null
                  ? 'Close'
                  : 'Later',
            ),
          ),
        ),
        if (_applied == null && update != null)
          FilledButton(
            key: const ValueKey('library-update-apply'),
            onPressed: busy ? null : _apply,
            child: Text(
              copy.localized(
                error == null ? '更新资料' : '重试更新',
                error == null ? 'Update library' : 'Retry update',
              ),
            ),
          ),
        if (_applied == null && update == null)
          FilledButton(
            key: const ValueKey('library-update-check'),
            onPressed: busy ? null : () => c.checkForLibraryUpdates(),
            child: Text(copy.localized('重新检查', 'Check again')),
          ),
      ];
      if (widget.fullPage) {
        return Scaffold(
          key: const ValueKey('library-update-review'),
          appBar: AppBar(title: Text(copy.localized('资料更新', 'Library update'))),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [content],
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 12,
                children: actions,
              ),
            ),
          ),
        );
      }
      return AlertDialog(
        key: const ValueKey('library-update-review'),
        title: Text(copy.localized('资料更新', 'Library update')),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(child: content),
        ),
        actions: actions,
      );
    },
  );
}
