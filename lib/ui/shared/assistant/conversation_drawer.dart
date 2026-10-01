import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../../core/theme/app_motion.dart';

import '../../../app/state/app_controller.dart';
import '../../../core/theme/app_palette.dart';
import '../../../features/assistant/models/ai_conversation.dart';

/// A shared, floating history surface. The controller owns session data;
/// this route owns only animation, focus and the pending create operation.
Future<void> showConversationDrawer(
  BuildContext context, {
  required AppController controller,
}) {
  final palette = AppPalette.of(context);
  final render = context.findRenderObject();
  final bounds = render is RenderBox && render.hasSize
      ? render.localToGlobal(Offset.zero) & render.size
      : null;
  final themes = InheritedTheme.capture(
    from: context,
    to: Navigator.of(context, rootNavigator: true).context,
  );
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: controller.copy.closeConversations,
    barrierColor: palette.textPrimary.withValues(alpha: .16),
    transitionDuration: AppMotion.duration(context, AppMotion.panel),
    pageBuilder: (context, animation, secondaryAnimation) => themes.wrap(
      SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final left = (bounds?.left ?? 0)
                .clamp(0.0, math.max(0, constraints.maxWidth - 280))
                .toDouble();
            return Padding(
              padding: EdgeInsets.fromLTRB(left + 12, 12, 12, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: math.min(320, constraints.maxWidth - left - 46),
                  height: double.infinity,
                  child: FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: animation
                          .drive(CurveTween(curve: AppMotion.curve))
                          .drive(
                            Tween(begin: const Offset(-1, 0), end: Offset.zero),
                          ),
                      child: ConversationHistoryPanel(
                        controller: controller,
                        onClose: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
    transitionBuilder: (_, _, _, child) => child,
  );
}

class ConversationTitleButton extends StatefulWidget {
  const ConversationTitleButton({
    super.key,
    required this.title,
    required this.tooltip,
    required this.onPressed,
  });
  final String title;
  final String tooltip;
  final FutureOr<void> Function() onPressed;

  @override
  State<ConversationTitleButton> createState() =>
      _ConversationTitleButtonState();
}

class _ConversationTitleButtonState extends State<ConversationTitleButton> {
  bool _expanded = false;

  Future<void> _open() async {
    if (_expanded) return;
    setState(() => _expanded = true);
    try {
      await widget.onPressed();
    } finally {
      if (mounted) setState(() => _expanded = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Tooltip(
      message: '${widget.tooltip} · ${widget.title}',
      child: TextButton(
        key: const ValueKey('assistant-conversations-trigger'),
        onPressed: _open,
        style: TextButton.styleFrom(
          foregroundColor: palette.textPrimary,
          minimumSize: const Size(44, 48),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: palette.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.auto_awesome_rounded,
                size: 20,
                color: palette.primary,
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                widget.title,
                maxLines: 2,
                overflow: TextOverflow.clip,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(width: 8),
            AnimatedRotation(
              turns: _expanded ? .5 : 0,
              duration: AppMotion.duration(context),
              child: Icon(
                Icons.expand_more_rounded,
                size: 18,
                color: palette.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ConversationHistoryPanel extends StatefulWidget {
  const ConversationHistoryPanel({
    super.key,
    required this.controller,
    required this.onClose,
  });
  final AppController controller;
  final VoidCallback onClose;

  @override
  State<ConversationHistoryPanel> createState() =>
      _ConversationHistoryPanelState();
}

class _ConversationHistoryPanelState extends State<ConversationHistoryPanel> {
  bool _creating = false;
  String? _deletingId;
  String? _error;

  Future<void> _delete(AiConversation conversation) async {
    if (_creating || _deletingId != null) return;
    final copy = widget.controller.copy;
    final confirmed = await showDialog<bool>(
      context: context,
      animationStyle: AppMotion.menuStyle(context),
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(copy.localized('删除会话？', 'Delete conversation?')),
        content: Text(
          copy.localized(
            '将删除“${conversation.title}”及其消息，无法撤销。',
            'Delete “${conversation.title}” and its messages? This cannot be undone.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(copy.localized('取消', 'Cancel')),
          ),
          TextButton(
            key: const ValueKey('assistant-confirm-delete'),
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: AppPalette.of(context).error,
            ),
            child: Text(copy.localized('删除', 'Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _deletingId = conversation.id;
      _error = null;
    });
    try {
      await widget.controller.deleteConversation(conversation.id);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = copy.localized(
            '删除失败，会话已保留，请重试。',
            'Could not delete. The conversation was kept. Try again.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _deletingId = null);
    }
  }

  Future<void> _create() async {
    if (_creating || _deletingId != null) return;
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      await widget.controller.createConversation(
        useGlobalMode: widget.controller.selectedConversation?.isGlobal ?? true,
      );
      if (mounted) widget.onClose();
    } catch (_) {
      if (mounted) {
        setState(() {
          _creating = false;
          _error = widget.controller.copy.conversationSaveFailed;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final copy = controller.copy;
      final palette = AppPalette.of(context);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = DateTime(today.year, today.month, today.day - 1);
      final conversations = controller.conversations;
      final groups = <String, List<AiConversation>>{
        copy.conversationToday: [],
        copy.conversationYesterday: [],
        copy.conversationEarlier: [],
      };
      for (final conversation in conversations) {
        final date = conversation.updatedAt.toLocal();
        groups[date.isBefore(yesterday)
                ? copy.conversationEarlier
                : date.isBefore(today)
                ? copy.conversationYesterday
                : copy.conversationToday]!
            .add(conversation);
      }
      return Semantics(
        namesRoute: true,
        label: copy.conversationDrawerTitle,
        child: Material(
          key: const ValueKey('assistant-conversation-drawer'),
          color: palette.surface,
          elevation: 12,
          shadowColor: palette.shadow.withValues(alpha: .22),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(color: palette.outline.withValues(alpha: .65)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        copy.conversationDrawerTitle,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: copy.closeConversations,
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.menu_open_rounded),
                      style: IconButton.styleFrom(
                        foregroundColor: palette.textSecondary,
                        minimumSize: const Size(44, 44),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  key: const ValueKey('assistant-new-conversation'),
                  onPressed: _creating || _deletingId != null ? null : _create,
                  icon: _creating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_rounded, size: 20),
                  label: Text(copy.newConversation),
                  style: FilledButton.styleFrom(
                    backgroundColor: palette.primaryContainer,
                    foregroundColor: palette.onPrimaryContainer,
                    minimumSize: const Size(0, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        _error!,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: palette.error),
                      ),
                    ),
                  ),
                const SizedBox(height: 18),
                Expanded(
                  child: conversations.isEmpty
                      ? Center(
                          child: Text(
                            copy.conversationEmpty,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: palette.textSecondary),
                          ),
                        )
                      : ListView(
                          padding: EdgeInsets.zero,
                          children: [
                            for (final group in groups.entries)
                              if (group.value.isNotEmpty) ...[
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    10,
                                    8,
                                    10,
                                    8,
                                  ),
                                  child: Text(
                                    group.key,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: palette.textSecondary,
                                        ),
                                  ),
                                ),
                                for (final conversation in group.value)
                                  _row(context, conversation),
                                const SizedBox(height: 14),
                              ],
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _row(BuildContext context, AiConversation conversation) {
    final controller = widget.controller;
    final palette = AppPalette.of(context);
    final selected = conversation.id == controller.selectedConversationId;
    final scope = conversation.isGlobal
        ? controller.copy.conversationGeneral
        : controller.games
              .where((game) => game.id == conversation.gameId)
              .firstOrNull
              ?.title;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Semantics(
        selected: selected,
        child: Material(
          color: selected
              ? palette.primaryContainer.withValues(alpha: .65)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            key: ValueKey('assistant-conversation-${conversation.id}'),
            borderRadius: BorderRadius.circular(14),
            onTap: _creating || _deletingId != null
                ? null
                : () {
                    controller.selectConversation(conversation.id);
                    widget.onClose();
                  },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          conversation.title,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: palette.textPrimary,
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                        if (scope != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            scope,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: palette.textSecondary),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (selected) ...[
                    const SizedBox(width: 8),
                    Icon(Icons.check_rounded, size: 18, color: palette.primary),
                  ],
                  const SizedBox(width: 4),
                  IconButton(
                    key: ValueKey(
                      'assistant-delete-conversation-${conversation.id}',
                    ),
                    tooltip: controller.copy.localized(
                      '删除会话',
                      'Delete conversation',
                    ),
                    onPressed: _creating || _deletingId != null
                        ? null
                        : () => _delete(conversation),
                    style: IconButton.styleFrom(
                      minimumSize: const Size.square(36),
                      padding: EdgeInsets.zero,
                      foregroundColor: palette.textSecondary,
                    ),
                    icon: _deletingId == conversation.id
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.delete_outline_rounded, size: 18),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
