import 'dart:math' as math;

import 'package:flutter/material.dart';

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
  final reduceMotion = MediaQuery.disableAnimationsOf(context);
  final themes = InheritedTheme.capture(
    from: context,
    to: Navigator.of(context, rootNavigator: true).context,
  );
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: controller.copy.closeConversations,
    barrierColor: palette.textPrimary.withValues(alpha: .16),
    transitionDuration: Duration(milliseconds: reduceMotion ? 0 : 240),
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
                  child: ConversationHistoryPanel(
                    controller: controller,
                    onClose: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(-1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class ConversationTitleButton extends StatelessWidget {
  const ConversationTitleButton({
    super.key,
    required this.title,
    required this.tooltip,
    required this.onPressed,
  });
  final String title;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Tooltip(
      message: '$tooltip · $title',
      child: TextButton(
        key: const ValueKey('assistant-conversations-trigger'),
        onPressed: onPressed,
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
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: palette.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.auto_awesome_rounded,
                size: 23,
                color: palette.primary,
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.clip,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.expand_more_rounded,
              size: 20,
              color: palette.textSecondary,
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
  String? _error;

  Future<void> _create() async {
    if (_creating) return;
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
                  onPressed: _creating ? null : _create,
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
            onTap: _creating
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
