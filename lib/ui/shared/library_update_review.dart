import 'app_modals.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../app/state/app_controller.dart';
import '../../core/theme/app_motion.dart';
import 'smooth_progress.dart';

Future<void> showLibraryUpdateReview(
  BuildContext context,
  AppController controller,
) async {
  if (controller.appUpdateInProgress) return;
  if (MediaQuery.sizeOf(context).width < 700) {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            LibraryUpdateReview(controller: controller, fullPage: true),
      ),
    );
  } else {
    await showAppDialog<void>(
      context: context,
      animationStyle: AppMotion.menuStyle(context),
      builder: (_) => LibraryUpdateReview(controller: controller),
    );
  }
}

/// Publication metadata is committed atomically; documents remain on demand.
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
  bool _starting = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _starting = false);
      unawaited(widget.controller.checkForLibraryUpdates());
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final c = widget.controller, copy = c.copy;
      final busy = _starting || c.checkingLibraryUpdate;
      final update = c.lastLibraryUpdate;
      final error = c.libraryUpdateError;
      final content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            copy.localized('资料更新', 'Library updates'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          SmoothProgress(
            visible: busy,
            label: copy.localized('正在检查资料更新', 'Checking library updates'),
          ),
          if (busy)
            Text(
              copy.localized(
                '正在读取最新资料版本…',
                'Checking the latest library version…',
              ),
            ),
          if (!busy && error == null)
            Text(copy.localized('当前资料已是最新。', 'Your library is up to date.')),
          if (error != null)
            Semantics(
              liveRegion: true,
              child: Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (update != null && update.changedGameTitles.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              copy.localized('最近更新的桌游', 'Recently updated games'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            for (final title in update.changedGameTitles)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(title),
              ),
          ],
          const SizedBox(height: 20),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: busy
                    ? null
                    : () => unawaited(c.checkForLibraryUpdates()),
                child: Text(copy.localized('重新检查', 'Check again')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(copy.localized('关闭', 'Close')),
              ),
            ],
          ),
        ],
      );
      return widget.fullPage
          ? Scaffold(
              appBar: AppBar(
                title: Text(copy.localized('资料更新', 'Library updates')),
              ),
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: content,
              ),
            )
          : Dialog(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: content,
                ),
              ),
            );
    },
  );
}
