import 'package:flutter/material.dart';

import '../../../core/localization/app_copy.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_palette.dart';
import 'assistant_toolbar_icon.dart';

/// The same conversation controls are used by compact and desktop layouts.
/// Pages retain ownership of async operations and conversation state.
class AssistantConversationActions extends StatelessWidget {
  const AssistantConversationActions({
    super.key,
    required this.copy,
    required this.title,
    required this.onCreate,
    required this.onFind,
    required this.onDelete,
    this.creating = false,
  });

  final AppCopy copy;
  final String title;
  final VoidCallback onCreate;
  final VoidCallback? onFind;
  final VoidCallback? onDelete;
  final bool creating;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Material(
      color: palette.surface.withValues(alpha: .95),
      borderRadius: BorderRadius.circular(32),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AssistantHeaderPressFeedback(
            child: IconButton(
              key: const ValueKey('assistant-header-new-conversation'),
              tooltip: copy.newConversation,
              onPressed: creating ? null : onCreate,
              constraints: const BoxConstraints.tightFor(width: 48, height: 48),
              icon: creating
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : AssistantToolbarIcon(
                      asset: 'assets/mobile/assistant/edit.png',
                      size: 24,
                      color: palette.textPrimary,
                    ),
            ),
          ),
          AssistantHeaderPressFeedback(
            child: PopupMenuButton<String>(
              key: const ValueKey('assistant-more-menu'),
              popUpAnimationStyle: AppMotion.menuStyle(context),
              tooltip: copy.desktopMore,
              icon: AssistantToolbarIcon(
                asset: 'assets/mobile/assistant/more.png',
                size: 24,
                color: palette.textPrimary,
              ),
              color: palette.surface,
              surfaceTintColor: Colors.transparent,
              elevation: 6,
              shadowColor: palette.shadow.withValues(alpha: .2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              constraints: const BoxConstraints(minWidth: 216, maxWidth: 288),
              position: PopupMenuPosition.under,
              onSelected: (value) {
                if (value == 'find') onFind?.call();
                if (value == 'delete') onDelete?.call();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  enabled: false,
                  height: 40,
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                ),
                PopupMenuItem(
                  key: const ValueKey('assistant-menu-find'),
                  value: 'find',
                  height: 52,
                  enabled: onFind != null,
                  child: Row(
                    children: [
                      AssistantToolbarIcon(
                        asset: 'assets/mobile/assistant/find.png',
                        size: 22,
                        color: onFind == null
                            ? palette.disabledForeground
                            : palette.textSecondary,
                      ),
                      const SizedBox(width: 12),
                      Text(copy.localized('查找', 'Find')),
                    ],
                  ),
                ),
                PopupMenuItem(
                  key: const ValueKey('assistant-menu-delete'),
                  value: 'delete',
                  height: 52,
                  enabled: onDelete != null,
                  child: Row(
                    children: [
                      AssistantToolbarIcon(
                        asset: 'assets/mobile/assistant/delete.png',
                        size: 22,
                        color: onDelete == null
                            ? palette.disabledForeground
                            : palette.error,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        copy.localized('删除', 'Delete'),
                        style: TextStyle(
                          color: onDelete == null
                              ? palette.disabledForeground
                              : palette.error,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AssistantHeaderPressFeedback extends StatefulWidget {
  const AssistantHeaderPressFeedback({super.key, required this.child});
  final Widget child;

  @override
  State<AssistantHeaderPressFeedback> createState() =>
      _AssistantHeaderPressFeedbackState();
}

class _AssistantHeaderPressFeedbackState
    extends State<AssistantHeaderPressFeedback> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => setState(() => _pressed = true),
    onPointerUp: (_) => setState(() => _pressed = false),
    onPointerCancel: (_) => setState(() => _pressed = false),
    child: AnimatedScale(
      scale: _pressed && !AppMotion.reduced(context) ? .95 : 1,
      duration: AppMotion.duration(context, AppMotion.feedback),
      curve: _pressed ? Curves.easeOut : Curves.easeOutBack,
      child: widget.child,
    ),
  );
}
