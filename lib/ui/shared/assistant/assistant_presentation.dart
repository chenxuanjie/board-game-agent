import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/state/app_controller.dart';
import '../../../core/localization/app_copy.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_motion.dart';
import 'model_selector.dart';

export 'assistant_motion.dart';

class AssistantWelcome extends StatelessWidget {
  const AssistantWelcome({
    super.key,
    required this.copy,
    required this.onPrompt,
    this.gameTitle,
  });

  final AppCopy copy;
  final String? gameTitle;
  final ValueChanged<String> onPrompt;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final prompts = [
      (
        Icons.format_list_numbered_rounded,
        copy.localized('梳理回合流程', 'Review turn order'),
        copy.localized('帮我梳理一遍回合流程', 'Walk me through the turn order'),
      ),
      (
        Icons.menu_book_outlined,
        copy.localized('解释一个术语', 'Explain a term'),
        copy.quickPromptTerm,
      ),
      (
        Icons.forum_outlined,
        copy.localized('讨论规则争议', 'Discuss a ruling'),
        copy.localized('我有一个规则争议，帮我看看', 'Help me resolve a rules question'),
      ),
    ];
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580),
        child: Column(
          key: const ValueKey('assistant-welcome'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (gameTitle != null) ...[
              Row(
                children: [
                  Icon(Icons.casino_outlined, color: palette.primary, size: 17),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      gameTitle!,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: palette.primary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
            ],
            Text(
              copy.localized('有什么规则疑问？', 'What would you like to ask?'),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              copy.localized(
                '可以从回合流程、术语或具体情境开始。',
                'Start with turn order, a term, or a situation at the table.',
              ),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: palette.textSecondary),
            ),
            const SizedBox(height: 24),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 520 ? 3 : 1;
                final width =
                    (constraints.maxWidth - (columns - 1) * 10) / columns;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (var index = 0; index < prompts.length; index++)
                      SizedBox(
                        width: width,
                        child: _PromptCard(
                          key: ValueKey('assistant-prompt-$index'),
                          icon: prompts[index].$1,
                          label: prompts[index].$2,
                          compact: columns == 1,
                          onPressed: () => onPrompt(prompts[index].$3),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PromptCard extends StatefulWidget {
  const _PromptCard({
    super.key,
    required this.icon,
    required this.label,
    required this.compact,
    required this.onPressed,
  });
  final IconData icon;
  final String label;
  final bool compact;
  final VoidCallback onPressed;

  @override
  State<_PromptCard> createState() => _PromptCardState();
}

class _PromptCardState extends State<_PromptCard> {
  bool _highlighted = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final contents = [
      Icon(widget.icon, size: 19, color: palette.primary),
      SizedBox(width: widget.compact ? 10 : 0, height: widget.compact ? 0 : 13),
      if (widget.compact)
        Expanded(child: Text(widget.label))
      else
        Text(widget.label),
    ];
    return AnimatedContainer(
      duration: AppMotion.duration(context),
      curve: AppMotion.curve,
      transform: Matrix4.translationValues(
        0,
        _highlighted && !reduceMotion ? -3 : 0,
        0,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: palette.shadow.withValues(alpha: _highlighted ? .10 : .035),
            blurRadius: _highlighted ? 18 : 7,
            offset: Offset(0, _highlighted ? 6 : 2),
          ),
        ],
      ),
      child: Material(
        color: palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: _highlighted
                ? palette.primary.withValues(alpha: .35)
                : palette.outline,
          ),
        ),
        child: InkWell(
          onTap: widget.onPressed,
          onHover: (value) => setState(() => _highlighted = value),
          onFocusChange: (value) => setState(() => _highlighted = value),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: EdgeInsets.all(widget.compact ? 14 : 17),
            child: widget.compact
                ? Row(children: contents)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: contents,
                  ),
          ),
        ),
      ),
    );
  }
}

/// Shared across desktop, narrow Web and Android; draft/run ownership stays
/// with the existing page and controller.
class AssistantComposer extends StatefulWidget {
  const AssistantComposer({
    super.key,
    required this.controller,
    required this.textController,
    required this.useGlobalMode,
    required this.onSend,
    required this.onOpenContext,
    this.onMicTap,
    this.desktop = false,
  });
  final AppController controller;
  final TextEditingController textController;
  final bool useGlobalMode;
  final Future<void> Function() onSend;
  final VoidCallback onOpenContext;
  final Future<void> Function()? onMicTap;
  final bool desktop;

  @override
  State<AssistantComposer> createState() => AssistantComposerState();
}

class AssistantComposerState extends State<AssistantComposer> {
  late final FocusNode _focus;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus = FocusNode(
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.enter &&
            !HardwareKeyboard.instance.isShiftPressed &&
            widget.textController.value.composing.isCollapsed) {
          _send();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
    )..addListener(_focusChanged);
  }

  void _focusChanged() => setState(() => _focused = _focus.hasFocus);

  void focusDraft() => _focus.requestFocus();

  void _send() {
    if (widget.textController.text.trim().isNotEmpty &&
        !widget.controller.isSendingForContext(
          useGlobalMode: widget.useGlobalMode,
        )) {
      unawaited(widget.onSend());
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_focusChanged);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final copy = widget.controller.copy;
    return ListenableBuilder(
      listenable: Listenable.merge([widget.textController, widget.controller]),
      builder: (context, _) {
        final isSending = widget.controller.isSendingForContext(
          useGlobalMode: widget.useGlobalMode,
        );
        final canSend =
            widget.textController.text.trim().isNotEmpty && !isSending;
        final smart = widget.controller.allowSmartSupplement(
          useGlobalMode: widget.useGlobalMode,
        );
        return AnimatedContainer(
          key: ValueKey(
            widget.desktop ? 'desktop-composer-box' : 'assistant-composer-box',
          ),
          duration: AppMotion.duration(context),
          curve: AppMotion.curve,
          padding: const EdgeInsets.fromLTRB(15, 13, 10, 10),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(19),
            border: Border.all(
              color: _focused
                  ? palette.primary.withValues(alpha: .65)
                  : palette.outline,
            ),
            boxShadow: [
              BoxShadow(
                color: (_focused ? palette.primary : palette.shadow).withValues(
                  alpha: _focused ? .075 : .055,
                ),
                blurRadius: 24,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('assistant-draft'),
                focusNode: _focus,
                controller: widget.textController,
                minLines: 2,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: copy.localized('输入你的问题', 'Ask a question'),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  filled: false,
                  isDense: true,
                  contentPadding: const EdgeInsets.only(left: 2, bottom: 10),
                ),
              ),
              LayoutBuilder(
                builder: (context, constraints) {
                  final expandedText =
                      MediaQuery.textScalerOf(context).scale(14) > 17;
                  final stacked = constraints.maxWidth < 370 || expandedText;
                  final mode = PopupMenuButton<String>(
                    popUpAnimationStyle: AppMotion.menuStyle(context),
                    key: const ValueKey('desktop-answer-mode-selector'),
                    enabled: !isSending,
                    tooltip: copy.desktopAnswerModeTitle,
                    onSelected: (value) {
                      if (value == 'context') {
                        widget.onOpenContext();
                      } else {
                        unawaited(
                          widget.controller.setAllowSmartSupplement(
                            value == 'smart',
                            useGlobalMode: widget.useGlobalMode,
                          ),
                        );
                      }
                    },
                    itemBuilder: (_) => [
                      CheckedPopupMenuItem(
                        value: 'sources',
                        checked: !smart,
                        child: Text(copy.knowledgeOnlyLabel),
                      ),
                      CheckedPopupMenuItem(
                        value: 'smart',
                        checked: smart,
                        child: Text(copy.smartSupplementLabel),
                      ),
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'context',
                        child: Text(copy.assistantContextTitle),
                      ),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 10,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            smart
                                ? Icons.auto_awesome_outlined
                                : Icons.menu_book_outlined,
                            color: palette.primary,
                            size: 17,
                          ),
                          const SizedBox(width: 7),
                          Flexible(
                            child: Text(
                              smart
                                  ? copy.smartSupplementLabel
                                  : copy.knowledgeOnlyLabel,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: palette.primary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                  final controls = Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: AssistantModelSelector(
                            controller: widget.controller,
                            enabled: !isSending,
                          ),
                        ),
                      ),
                      if (widget.onMicTap != null)
                        IconButton(
                          tooltip: widget.controller.isListening
                              ? copy.tapToStop
                              : copy.speechReady,
                          onPressed: isSending ? null : widget.onMicTap,
                          icon: Icon(
                            widget.controller.isListening
                                ? Icons.stop_rounded
                                : Icons.mic_none_rounded,
                            color: widget.controller.isListening
                                ? palette.primary
                                : palette.textSecondary,
                          ),
                        ),
                      const SizedBox(width: 3),
                      AnimatedContainer(
                        duration: AppMotion.duration(context),
                        decoration: BoxDecoration(
                          color: isSending || canSend
                              ? palette.primary
                              : palette.disabledBackground,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: IconButton(
                          key: ValueKey(
                            widget.desktop
                                ? 'desktop-composer-send'
                                : 'assistant-composer-send',
                          ),
                          tooltip: isSending ? copy.stopGenerating : copy.send,
                          onPressed: isSending
                              ? () => widget.controller.stopGenerating(
                                  useGlobalMode: widget.useGlobalMode,
                                )
                              : canSend
                              ? _send
                              : null,
                          style: IconButton.styleFrom(
                            foregroundColor: palette.onPrimary,
                            disabledForegroundColor: palette.disabledForeground,
                            minimumSize: const Size.square(40),
                            maximumSize: const Size.square(40),
                            padding: EdgeInsets.zero,
                          ),
                          icon: AnimatedSwitcher(
                            duration: AppMotion.duration(context),
                            child: Icon(
                              isSending
                                  ? Icons.stop_rounded
                                  : Icons.arrow_upward_rounded,
                              key: ValueKey(isSending),
                              size: 21,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                  return stacked
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [mode, controls],
                        )
                      : Row(
                          children: [
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: mode,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(flex: 2, child: controls),
                          ],
                        );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
