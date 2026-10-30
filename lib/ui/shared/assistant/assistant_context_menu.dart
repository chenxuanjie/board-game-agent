import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/state/app_controller.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_palette.dart';

/// Displays the real answer settings next to the composer instead of covering
/// the conversation with a full-width bottom sheet.
Future<void> showAssistantContextMenu(
  BuildContext anchorContext,
  AppController controller, {
  required bool useGlobalMode,
}) async {
  final box = anchorContext.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return;
  final initialAnchor = box.localToGlobal(Offset.zero) & box.size;
  final copy = controller.copy;
  await showGeneralDialog<void>(
    context: anchorContext,
    barrierDismissible: true,
    barrierLabel: copy.localized('关闭回答设置', 'Close answer settings'),
    barrierColor: Colors.transparent,
    transitionDuration: AppMotion.duration(anchorContext, AppMotion.menu),
    pageBuilder: (context, _, _) =>
        _ContextOptions(controller: controller, useGlobalMode: useGlobalMode),
    transitionBuilder: (context, animation, _, child) => LayoutBuilder(
      builder: (context, constraints) {
        final media = MediaQuery.of(context);
        final viewport = constraints.biggest;
        final anchor = box.attached && box.hasSize
            ? box.localToGlobal(Offset.zero) & box.size
            : initialAnchor;
        final top = media.padding.top + 8;
        final bottom = math.max(
          top + 1,
          viewport.height -
              math.max(media.viewInsets.bottom, media.padding.bottom) -
              8,
        );
        final width = math.min(330.0, math.max(1.0, viewport.width - 24));
        final left = anchor.left
            .clamp(12.0, math.max(12.0, viewport.width - width - 12))
            .toDouble();
        final above = math.max(0.0, anchor.top - top - 8);
        final below = math.max(0.0, bottom - anchor.bottom - 8);
        final openAbove = above >= below;
        final available = math.max(1.0, openAbove ? above : below);
        final height = math.min(460.0, math.min(bottom - top, available));
        final edge = (openAbove ? anchor.top - 8 : anchor.bottom + 8).clamp(
          top + (openAbove ? height : 0),
          bottom - (openAbove ? 0 : height),
        );
        final curved = CurvedAnimation(
          parent: animation,
          curve: AppMotion.curve,
          reverseCurve: AppMotion.exitCurve,
        );
        return Stack(
          children: [
            Positioned(
              left: left,
              top: openAbove ? null : edge,
              bottom: openAbove ? viewport.height - edge : null,
              width: width,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: height),
                child: FadeTransition(
                  opacity: curved,
                  child: SizeTransition(
                    sizeFactor: curved,
                    axisAlignment: openAbove ? 1 : -1,
                    child: child,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

class _ContextOptions extends StatelessWidget {
  const _ContextOptions({
    required this.controller,
    required this.useGlobalMode,
  });
  final AppController controller;
  final bool useGlobalMode;

  @override
  Widget build(BuildContext context) {
    final copy = controller.copy;
    final palette = AppPalette.of(context);
    return Material(
      key: const ValueKey('assistant-context-menu'),
      color: palette.surface,
      elevation: 8,
      shadowColor: palette.shadow.withValues(alpha: .18),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final smart = controller.allowSmartSupplement(
            useGlobalMode: useGlobalMode,
          );
          final available = controller.assistantKnowledgeAvailable;
          Future<void> save(Future<void> Function() action) async {
            try {
              await action();
            } catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                  SnackBar(
                    content: Text(
                      copy.localized(
                        '设置未保存，请重试',
                        'Could not save the setting. Try again.',
                      ),
                    ),
                  ),
                );
              }
            }
          }

          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    copy.assistantContextTitle,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (controller.isSendingForContext(
                  useGlobalMode: useGlobalMode,
                ))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
                    child: Text(
                      copy.localized('下次发送生效', 'Applies to your next message'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                if (!available)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
                    child: Text(
                      copy.assistantKnowledgeUnavailable,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ListTile(
                  key: const ValueKey('assistant-context-knowledge'),
                  title: Text(copy.knowledgeOnlyLabel),
                  leading: const Icon(Icons.menu_book_outlined),
                  trailing: !smart ? const Icon(Icons.check_rounded) : null,
                  enabled: available,
                  onTap: available
                      ? () => unawaited(
                          save(
                            () => controller.setAllowSmartSupplement(
                              false,
                              useGlobalMode: useGlobalMode,
                            ),
                          ),
                        )
                      : null,
                ),
                ListTile(
                  key: const ValueKey('assistant-context-smart'),
                  title: Text(copy.smartSupplementLabel),
                  leading: const Icon(Icons.auto_awesome_outlined),
                  trailing: smart ? const Icon(Icons.check_rounded) : null,
                  onTap: () => unawaited(
                    save(
                      () => controller.setAllowSmartSupplement(
                        true,
                        useGlobalMode: useGlobalMode,
                      ),
                    ),
                  ),
                ),
                if (useGlobalMode)
                  SwitchListTile.adaptive(
                    key: const ValueKey('assistant-context-current-game'),
                    title: Text(copy.useCurrentGameKnowledgeLabel),
                    subtitle: Text(copy.useCurrentGameKnowledgeHint),
                    value: controller.globalUseCurrentGameKnowledge,
                    onChanged: available
                        ? (value) => unawaited(
                            save(
                              () => controller.setGlobalUseCurrentGameKnowledge(
                                value,
                              ),
                            ),
                          )
                        : null,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
