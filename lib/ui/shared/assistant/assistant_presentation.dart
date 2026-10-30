import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/services.dart';

import '../../../app/state/app_controller.dart';
import '../../../core/localization/app_copy.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_motion.dart';
import 'model_selector.dart';
import 'assistant_context_menu.dart';

export 'assistant_motion.dart';

class AssistantWelcome extends StatelessWidget {
  const AssistantWelcome({
    super.key,
    required this.copy,
    required this.onPrompt,
    this.gameTitle,
    this.compact = false,
  });

  final AppCopy copy;
  final String? gameTitle;
  final bool compact;
  final ValueChanged<String> onPrompt;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final prompts = [
      (
        Icons.format_list_numbered_rounded,
        copy.localized('回合流程', 'Turn order'),
        copy.localized('帮我梳理一遍回合流程', 'Walk me through the turn order'),
      ),
      (
        Icons.menu_book_outlined,
        copy.localized('术语解释', 'Terms'),
        copy.quickPromptTerm,
      ),
      (
        Icons.forum_outlined,
        copy.localized('规则争议', 'Rulings'),
        copy.localized('我有一个规则争议，帮我看看', 'Help me resolve a rules question'),
      ),
    ];
    return Align(
      alignment: const Alignment(0, -.2),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580),
        child: Column(
          key: const ValueKey('assistant-welcome'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (gameTitle != null) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.casino_outlined, color: palette.primary, size: 17),
                  const SizedBox(width: 8),
                  Flexible(
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
            LayoutBuilder(
              builder: (context, constraints) {
                final style = Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: palette.textPrimary,
                    );
                var heading = copy.localized(
                  '有什么规则疑问？',
                  'What would you like to ask?',
                );
                if (copy.isChinese) {
                  final measure = TextPainter(
                    text: TextSpan(text: heading, style: style),
                    textDirection: Directionality.of(context),
                    textScaler: MediaQuery.textScalerOf(context),
                  )..layout();
                  if (measure.width > constraints.maxWidth) {
                    heading = '有什么\n规则疑问？';
                  }
                  measure.dispose();
                }
                return Text(heading, textAlign: TextAlign.center, style: style);
              },
            ),
            if (!compact) ...[
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Text(
                  copy.localized(
                    '可以从回合流程、术语或具体情境开始。',
                    'Start with turn order, a term, or a situation at the table.',
                  ),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              LayoutBuilder(
                builder: (context, constraints) {
                  return Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var index = 0; index < prompts.length; index++)
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: constraints.maxWidth,
                          ),
                          child: _PromptCard(
                            key: ValueKey('assistant-prompt-$index'),
                            icon: prompts[index].$1,
                            label: prompts[index].$2,
                            onPressed: () => onPrompt(prompts[index].$3),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
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
    required this.onPressed,
  });
  final IconData icon;
  final String label;
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
      const SizedBox(width: 8),
      Flexible(
        child: Text(
          widget.label,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: palette.textSecondary),
        ),
      ),
    ];
    return AnimatedContainer(
      duration: AppMotion.duration(context),
      curve: AppMotion.curve,
      transform: Matrix4.translationValues(
        0,
        _highlighted && !reduceMotion ? -2 : 0,
        0,
      ),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(18)),
      child: Material(
        color: palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: _highlighted
                ? palette.primary.withValues(alpha: .35)
                : palette.outline.withValues(alpha: .6),
          ),
        ),
        child: InkWell(
          onTap: widget.onPressed,
          onHover: (value) => setState(() => _highlighted = value),
          onFocusChange: (value) => setState(() => _highlighted = value),
          borderRadius: BorderRadius.circular(18),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(mainAxisSize: MainAxisSize.min, children: contents),
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
    this.onMicTap,
    this.desktop = false,
    this.keyboardVisible,
    this.onConfigureAi,
  });
  final AppController controller;
  final TextEditingController textController;
  final bool useGlobalMode;
  final Future<void> Function() onSend;
  final Future<void> Function()? onMicTap;
  final bool desktop;
  final bool? keyboardVisible;
  final VoidCallback? onConfigureAi;

  @override
  State<AssistantComposer> createState() => AssistantComposerState();
}

class AssistantComposerState extends State<AssistantComposer> {
  late final FocusNode _focus;
  final GlobalKey _fieldKey = GlobalKey();
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

  void _focusChanged() {
    if (mounted) setState(() => _focused = _focus.hasFocus);
  }

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
        final sending = widget.controller.isSendingForContext(
          useGlobalMode: widget.useGlobalMode,
        );
        final canSend =
            widget.textController.text.trim().isNotEmpty && !sending;
        final listening =
            widget.controller.isListening && widget.onMicTap != null;
        final voiceAction = widget.onMicTap != null && !canSend;
        final actionIcon = sending || listening
            ? Icons.stop_rounded
            : voiceAction
            ? Icons.mic_none_rounded
            : Icons.arrow_upward_rounded;
        final actionLabel = sending
            ? copy.stopGenerating
            : listening
            ? copy.tapToStop
            : voiceAction
            ? copy.speechReady
            : copy.send;
        final enabled = sending || listening || canSend || voiceAction;
        final mobileKeyboard =
            !widget.desktop &&
            !kIsWeb &&
            (defaultTargetPlatform == TargetPlatform.android ||
                defaultTargetPlatform == TargetPlatform.iOS) &&
            (widget.keyboardVisible ??
                MediaQuery.viewInsetsOf(context).bottom > 0);
        final showModel =
            widget.desktop ||
                kIsWeb ||
                (defaultTargetPlatform != TargetPlatform.android &&
                    defaultTargetPlatform != TargetPlatform.iOS)
            ? _focused
            : mobileKeyboard;
        return LayoutBuilder(
          builder: (context, constraints) {
            final textWidth =
                (constraints.maxWidth - 24 - 48 - 48 - (showModel ? 48 : 0))
                    .clamp(32.0, double.infinity);
            final textStyle =
                (Theme.of(context).textTheme.bodyLarge ?? const TextStyle())
                    .copyWith(fontSize: 16, height: 1.45);
            final painter = TextPainter(
              text: TextSpan(
                text: widget.textController.text.isEmpty
                    ? ' '
                    : widget.textController.text,
                style: textStyle,
              ),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
              maxLines: 1,
            )..layout(maxWidth: textWidth);
            final expanded =
                mobileKeyboard ||
                widget.textController.text.contains('\n') ||
                painter.didExceedMaxLines;
            painter.dispose();

            final field = KeyedSubtree(
              key: _fieldKey,
              child: TextField(
                key: const ValueKey('assistant-draft'),
                focusNode: _focus,
                controller: widget.textController,
                style: textStyle,
                minLines: 1,
                maxLines: 5,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                textAlignVertical: TextAlignVertical.center,
                decoration: InputDecoration(
                  hintText: copy.localized(
                    '询问桌游助手',
                    'Ask the board game assistant',
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  filled: false,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 8,
                  ),
                ),
              ),
            );
            final contextButton = Builder(
              builder: (buttonContext) => IconButton(
                key: const ValueKey('assistant-context-button'),
                tooltip: copy.assistantContextTitle,
                onPressed: () => showAssistantContextMenu(
                  buttonContext,
                  widget.controller,
                  useGlobalMode: widget.useGlobalMode,
                ),
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.add_rounded),
                    if (widget.controller.assistantKnowledgeAvailable &&
                        (!widget.useGlobalMode ||
                            widget.controller.globalUseCurrentGameKnowledge))
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: palette.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
            final model = showModel
                ? AssistantModelSelector(
                    controller: widget.controller,
                    enabled: true,
                    compact: true,
                    iconOnly: true,
                    useGlobalMode: widget.useGlobalMode,
                    onConfigureAi:
                        widget.onConfigureAi ??
                        () => Navigator.of(context).pushNamed('/settings/ai'),
                  )
                : null;
            final action = TooltipTheme(
              data: TooltipTheme.of(
                context,
              ).copyWith(triggerMode: TooltipTriggerMode.manual),
              child: GestureDetector(
                onLongPress:
                    canSend && widget.onMicTap != null && !sending && !listening
                    ? widget.onMicTap
                    : null,
                child: AnimatedContainer(
                  duration: AppMotion.duration(context),
                  decoration: BoxDecoration(
                    color: enabled
                        ? palette.primary
                        : palette.disabledBackground,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: IconButton(
                    key: ValueKey(
                      widget.desktop
                          ? 'desktop-composer-send'
                          : 'assistant-composer-send',
                    ),
                    tooltip: actionLabel,
                    onPressed: sending
                        ? () => widget.controller.stopGenerating(
                            useGlobalMode: widget.useGlobalMode,
                          )
                        : listening
                        ? widget.onMicTap
                        : canSend
                        ? _send
                        : voiceAction
                        ? widget.onMicTap
                        : null,
                    style: IconButton.styleFrom(
                      foregroundColor: palette.onPrimary,
                      disabledForegroundColor: palette.disabledForeground,
                      minimumSize: const Size.square(48),
                      maximumSize: const Size.square(48),
                      padding: EdgeInsets.zero,
                    ),
                    icon: AnimatedSwitcher(
                      duration: AppMotion.duration(context),
                      child: Icon(
                        actionIcon,
                        key: ValueKey(actionIcon),
                        size: 21,
                      ),
                    ),
                  ),
                ),
              ),
            );
            final controls = Row(
              children: [contextButton, const Spacer(), ?model, action],
            );
            return AnimatedContainer(
              key: ValueKey(
                widget.desktop
                    ? 'desktop-composer-box'
                    : 'assistant-composer-box',
              ),
              duration: AppMotion.duration(context),
              curve: AppMotion.curve,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(expanded ? 25 : 32),
                border: Border.all(
                  color: _focused
                      ? palette.primary.withValues(alpha: .28)
                      : palette.outline.withValues(alpha: .5),
                ),
                boxShadow: [
                  BoxShadow(
                    color: palette.shadow.withValues(
                      alpha: _focused ? .10 : .065,
                    ),
                    blurRadius: _focused ? 24 : 18,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: AnimatedSize(
                duration: AppMotion.duration(context, AppMotion.content),
                curve: AppMotion.curve,
                alignment: Alignment.bottomCenter,
                child: expanded
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: field,
                          ),
                          controls,
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          contextButton,
                          Expanded(child: field),
                          ?model,
                          action,
                        ],
                      ),
              ),
            );
          },
        );
      },
    );
  }
}
