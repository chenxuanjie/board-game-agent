import 'package:flutter/material.dart';

import '../../models/assistant_mode.dart';
import '../../models/chat_message.dart';
import '../../state/app_controller.dart';
import '../../theme/app_palette.dart';
import '../widgets/message_bubble.dart';

class AssistantChatScreen extends StatefulWidget {
  const AssistantChatScreen({
    super.key,
    required this.controller,
    this.initialDraft,
    this.customTitle,
    this.customSubtitle,
    this.customGreeting,
    this.useGlobalMode = false,
  });

  final AppController controller;
  final String? initialDraft;
  final String? customTitle;
  final String? customSubtitle;
  final String? customGreeting;
  final bool useGlobalMode;

  @override
  State<AssistantChatScreen> createState() => _AssistantChatScreenState();
}

class _AssistantChatScreenState extends State<AssistantChatScreen> {
  late final TextEditingController _textController;
  late final ScrollController _scrollController;
  bool _didInitializeConversation = false;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.initialDraft ?? '');
    _scrollController = ScrollController();
    _textController.addListener(_onDraftChanged);
    widget.controller.addListener(_onControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_didInitializeConversation) {
        return;
      }
      _didInitializeConversation = true;
      if (widget.controller
          .messagesForContext(useGlobalMode: widget.useGlobalMode)
          .isEmpty) {
        widget.controller.resetConversation(
          greeting: widget.customGreeting,
          useGlobalMode: widget.useGlobalMode,
        );
      }
    });
  }

  @override
  void dispose() {
    widget.controller.stopSpeaking();
    widget.controller.removeListener(_onControllerChanged);
    _textController.removeListener(_onDraftChanged);
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final copy = controller.copy;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final canSend =
        _textController.text.trim().isNotEmpty && !controller.isSending;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        titleSpacing: 6,
        title: _AssistantAppBarTitle(
          controller: controller,
          title: widget.customTitle ?? controller.featuredGame.title,
          subtitle: widget.customSubtitle ?? copy.assistantMode,
        ),
        actions: <Widget>[
          IconButton(
            tooltip: copy.clearChat,
            onPressed: () => controller.clearConversationForContext(
              useGlobalMode: widget.useGlobalMode,
            ),
            icon: const Icon(Icons.delete_sweep_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: screenWidth >= 980 ? 960 : double.infinity,
            ),
            child: Column(
              children: <Widget>[
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    screenWidth >= 720 ? 28 : 16,
                    4,
                    screenWidth >= 720 ? 28 : 16,
                    8,
                  ),
                  child: _ContextStrip(
                    controller: controller,
                    useGlobalMode: widget.useGlobalMode,
                    onTap: _openContextSheet,
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    screenWidth >= 720 ? 28 : 16,
                    0,
                    screenWidth >= 720 ? 28 : 16,
                    8,
                  ),
                  child: _AssistantModeStrip(
                    controller: controller,
                    onSelect: _selectAssistantMode,
                  ),
                ),
                Expanded(
                  child: AnimatedBuilder(
                    animation: controller,
                    builder: (context, _) {
                      final messages = controller.messagesForContext(
                        useGlobalMode: widget.useGlobalMode,
                      );
                      return _MessageList(
                        controller: controller,
                        messages: messages,
                        scrollController: _scrollController,
                        onQuickPrompt: _sendQuickPrompt,
                        useGlobalMode: widget.useGlobalMode,
                      );
                    },
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    screenWidth >= 720 ? 28 : 16,
                    8,
                    screenWidth >= 720 ? 28 : 16,
                    18,
                  ),
                  child: _Composer(
                    controller: controller,
                    textController: _textController,
                    canSend: canSend,
                    useGlobalMode: widget.useGlobalMode,
                    onSend: _sendCurrentText,
                    onMicTap: _toggleListening,
                    onOpenContext: _openContextSheet,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onControllerChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 96,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    });
  }

  void _onDraftChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _sendCurrentText() async {
    final text = _textController.text.trim();
    if (text.isEmpty || widget.controller.isSending) {
      return;
    }

    // Validate the model before clearing the draft. The controller also
    // guards this invariant for non-UI callers, but the chat page must give
    // immediate feedback while preserving the user's text.
    if (!widget.controller.hasSelectedAiModel) {
      final messenger = ScaffoldMessenger.of(context);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(widget.controller.copy.aiApiModelRequired)),
        );
      return;
    }

    _textController.clear();
    await widget.controller.sendPrompt(
      text,
      useGlobalMode: widget.useGlobalMode,
    );
  }

  Future<void> _sendQuickPrompt(String prompt) async {
    _textController.text = prompt;
    await _sendCurrentText();
  }

  Future<void> _toggleListening() async {
    final controller = widget.controller;
    if (controller.assistantMode == AssistantMode.realtimeVoice) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(controller.copy.assistantRealtimeUnavailable)),
        );
      }
      return;
    }
    if (!controller.speechAvailable) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            controller.speechError == null
                ? controller.copy.micUnavailable
                : '${controller.copy.micUnavailable} ${controller.speechError}',
          ),
        ),
      );
      return;
    }

    if (controller.isListening) {
      await controller.stopListening();
      return;
    }

    await controller.startListening(
      onRecognizedText: (String value) {
        _textController.value = TextEditingValue(
          text: value,
          selection: TextSelection.collapsed(offset: value.length),
        );
      },
    );
    if (!controller.isListening && controller.speechError != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(controller.speechError!)));
    }
  }

  Future<void> _selectAssistantMode(AssistantMode mode) async {
    final controller = widget.controller;
    final bool changed = await controller.setAssistantMode(mode);
    if (!mounted) {
      return;
    }
    if (!changed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(controller.copy.assistantRealtimeUnavailable)),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(controller.copy.assistantModeChanged)),
    );
  }

  Future<void> _openContextSheet() async {
    final controller = widget.controller;
    final copy = controller.copy;
    final palette = controller.palette;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: palette.cardSurface,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                final smartSupplement = controller.allowSmartSupplement(
                  useGlobalMode: widget.useGlobalMode,
                );
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      copy.assistantContextTitle,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      copy.assistantContextHint,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      secondary: Icon(
                        Icons.menu_book_rounded,
                        color: palette.accentPrimary,
                      ),
                      title: Text(copy.knowledgeOnlyLabel),
                      subtitle: Text(copy.assistantKnowledgeHint),
                      value: !smartSupplement,
                      onChanged: (value) {
                        if (value) {
                          controller.setAllowSmartSupplement(
                            false,
                            useGlobalMode: widget.useGlobalMode,
                          );
                        }
                      },
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      secondary: Icon(
                        Icons.auto_awesome_rounded,
                        color: palette.accentSecondary,
                      ),
                      title: Text(copy.smartSupplementLabel),
                      subtitle: Text(
                        smartSupplement
                            ? copy.smartSupplementSwitchHintOn
                            : copy.smartSupplementSwitchHintOff,
                      ),
                      value: smartSupplement,
                      onChanged: (value) {
                        controller.setAllowSmartSupplement(
                          value,
                          useGlobalMode: widget.useGlobalMode,
                        );
                      },
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      secondary: Icon(
                        Icons.graphic_eq_rounded,
                        color: palette.accentPrimary,
                      ),
                      title: Text(copy.voiceReplySwitchLabel),
                      subtitle: Text(copy.voiceReplyHint),
                      value: controller.voiceReplyEnabled,
                      onChanged: (value) {
                        controller.setVoiceReplyEnabled(value);
                      },
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _AssistantAppBarTitle extends StatelessWidget {
  const _AssistantAppBarTitle({
    required this.controller,
    required this.title,
    required this.subtitle,
  });

  final AppController controller;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        const _AssistantAvatar(size: 38),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                subtitle,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: controller.palette.homeTextSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ContextStrip extends StatelessWidget {
  const _ContextStrip({
    required this.controller,
    required this.useGlobalMode,
    required this.onTap,
  });

  final AppController controller;
  final bool useGlobalMode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final copy = controller.copy;
    final palette = controller.palette;
    final smart = controller.allowSmartSupplement(useGlobalMode: useGlobalMode);
    final modeLabel = smart
        ? copy.smartSupplementLabel
        : copy.knowledgeOnlyLabel;

    return Material(
      color: palette.aiPrimary.withValues(alpha: 0.32),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: <Widget>[
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: smart
                      ? palette.accentSecondary
                      : palette.accentPrimary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  modeLabel,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              Text(
                controller.speechAvailable
                    ? copy.speechReady
                    : copy.speechUnavailableShort,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: palette.homeTextSecondary,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.tune_rounded,
                size: 18,
                color: palette.homeTextSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssistantModeStrip extends StatelessWidget {
  const _AssistantModeStrip({required this.controller, required this.onSelect});

  final AppController controller;
  final Future<void> Function(AssistantMode mode) onSelect;

  @override
  Widget build(BuildContext context) {
    final copy = controller.copy;
    final palette = controller.palette;
    final bool realtimeAvailable = controller.realtimeVoiceAvailable;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: palette.cardSurface.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.cardBorder),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _AssistantModeChoice(
              palette: palette,
              selected:
                  controller.assistantMode == AssistantMode.textAndDictation,
              icon: Icons.keyboard_voice_rounded,
              label: copy.assistantTextModeLabel,
              onTap: () => onSelect(AssistantMode.textAndDictation),
            ),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: _AssistantModeChoice(
              palette: palette,
              selected: controller.assistantMode == AssistantMode.realtimeVoice,
              enabled: realtimeAvailable,
              icon: Icons.record_voice_over_rounded,
              label: copy.assistantRealtimeModeLabel,
              onTap: () => onSelect(AssistantMode.realtimeVoice),
              badge: realtimeAvailable ? null : Icons.lock_outline_rounded,
            ),
          ),
        ],
      ),
    );
  }
}

class _AssistantModeChoice extends StatelessWidget {
  const _AssistantModeChoice({
    required this.palette,
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.badge,
  });

  final AppPalette palette;
  final bool selected;
  final bool enabled;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final IconData? badge;

  @override
  Widget build(BuildContext context) {
    final Color foreground = !enabled
        ? palette.homeTextSecondary
        : selected
        ? Colors.white
        : palette.homeTextPrimary;
    final Color background = !enabled
        ? palette.cardBorder.withValues(alpha: 0.16)
        : selected
        ? palette.accentPrimary
        : Colors.transparent;

    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      label: label,
      child: Tooltip(
        message: label,
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: enabled ? onTap : onTap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(icon, size: 17, color: foreground),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (badge != null) ...<Widget>[
                    const SizedBox(width: 4),
                    Icon(badge, size: 14, color: foreground),
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

class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.controller,
    required this.messages,
    required this.scrollController,
    required this.onQuickPrompt,
    required this.useGlobalMode,
  });

  final AppController controller;
  final List<ChatMessage> messages;
  final ScrollController scrollController;
  final Future<void> Function(String prompt) onQuickPrompt;
  final bool useGlobalMode;

  @override
  Widget build(BuildContext context) {
    final copy = controller.copy;
    final showQuickPrompts = messages.length <= 1 && !controller.isSending;

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
      children: <Widget>[
        for (final ChatMessage message in messages)
          MessageBubble(
            message: message,
            palette: controller.palette,
            copy: copy,
            onSpeak: message.role == ChatRole.assistant
                ? () => controller.speakMessage(message.text)
                : () {},
            speakTooltip: copy.speakAgain,
            onRetry: message.canRetry
                ? () => controller.retryMessage(
                    message,
                    useGlobalMode: useGlobalMode,
                  )
                : null,
            retryTooltip: copy.retry,
          ),
        if (showQuickPrompts)
          _QuickPromptCard(controller: controller, onPrompt: onQuickPrompt),
      ],
    );
  }
}

class _QuickPromptCard extends StatelessWidget {
  const _QuickPromptCard({required this.controller, required this.onPrompt});

  final AppController controller;
  final Future<void> Function(String prompt) onPrompt;

  @override
  Widget build(BuildContext context) {
    final copy = controller.copy;
    final palette = controller.palette;
    final prompts = <String>[
      copy.quickPromptRule,
      copy.quickPromptFlow,
      copy.quickPromptTerm,
    ];

    return Container(
      margin: const EdgeInsets.only(top: 12, bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: palette.cardSurface.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: palette.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            copy.quickPromptsTitle,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: prompts
                .map(
                  (prompt) => ActionChip(
                    avatar: Icon(
                      Icons.arrow_outward_rounded,
                      size: 15,
                      color: palette.accentPrimary,
                    ),
                    label: Text(prompt),
                    onPressed: () {
                      onPrompt(prompt);
                    },
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.textController,
    required this.canSend,
    required this.useGlobalMode,
    required this.onSend,
    required this.onMicTap,
    required this.onOpenContext,
  });

  final AppController controller;
  final TextEditingController textController;
  final bool canSend;
  final bool useGlobalMode;
  final Future<void> Function() onSend;
  final Future<void> Function() onMicTap;
  final VoidCallback onOpenContext;

  @override
  Widget build(BuildContext context) {
    final copy = controller.copy;
    final palette = controller.palette;
    final smartSupplement = controller.allowSmartSupplement(
      useGlobalMode: useGlobalMode,
    );
    final activeFeatures = <Widget>[
      _FeatureChip(
        icon: smartSupplement
            ? Icons.auto_awesome_rounded
            : Icons.menu_book_rounded,
        label: smartSupplement
            ? copy.smartSupplementLabel
            : copy.knowledgeOnlyLabel,
        foregroundColor: smartSupplement
            ? palette.accentSecondary
            : palette.accentPrimary,
        backgroundColor:
            (smartSupplement ? palette.accentSecondary : palette.accentPrimary)
                .withValues(alpha: 0.14),
        onRemove: onOpenContext,
      ),
      if (controller.voiceReplyEnabled)
        _FeatureChip(
          icon: Icons.graphic_eq_rounded,
          label: copy.voiceReplySwitchLabel,
          foregroundColor: palette.accentPrimary,
          backgroundColor: palette.accentPrimary.withValues(alpha: 0.14),
          onRemove: () {
            controller.setVoiceReplyEnabled(false);
          },
        ),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (controller.isListening)
          _RecordingBanner(
            controller: controller,
            transcript: textController.text,
            onStop: onMicTap,
          ),
        Padding(
          padding: const EdgeInsets.only(bottom: 9),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(spacing: 8, runSpacing: 8, children: activeFeatures),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: palette.inputFill,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: palette.cardBorder),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: palette.cardShadow.withValues(alpha: 0.22),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                IconButton(
                  tooltip: copy.assistantContextTitle,
                  onPressed: onOpenContext,
                  icon: const Icon(Icons.add_rounded),
                ),
                Expanded(
                  child: TextField(
                    controller: textController,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: canSend
                        ? (_) {
                            onSend();
                          }
                        : null,
                    decoration: InputDecoration(
                      hintText: copy.messageHint,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: controller.isListening
                      ? copy.tapToStop
                      : copy.speechReady,
                  onPressed: controller.isSending
                      ? null
                      : () {
                          onMicTap();
                        },
                  style: IconButton.styleFrom(
                    backgroundColor: controller.isListening
                        ? palette.accentSecondary
                        : palette.accentPrimary,
                    foregroundColor: Colors.white,
                  ),
                  icon: Icon(
                    controller.isListening
                        ? Icons.stop_rounded
                        : Icons.mic_rounded,
                  ),
                ),
                const SizedBox(width: 5),
                IconButton(
                  tooltip: controller.isSending
                      ? copy.stopGenerating
                      : copy.send,
                  onPressed: controller.isSending
                      ? () {
                          controller.stopGenerating();
                        }
                      : canSend
                      ? () {
                          onSend();
                        }
                      : null,
                  style: IconButton.styleFrom(
                    backgroundColor: controller.isSending
                        ? palette.accentPrimary
                        : canSend
                        ? palette.accentSecondary
                        : palette.homeTextPrimary.withValues(alpha: 0.14),
                    foregroundColor: controller.isSending || canSend
                        ? Colors.white
                        : palette.homeTextPrimary.withValues(alpha: 0.38),
                  ),
                  icon: controller.isSending
                      ? const Icon(Icons.stop_rounded)
                      : const Icon(Icons.arrow_upward_rounded),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _RecordingBanner extends StatelessWidget {
  const _RecordingBanner({
    required this.controller,
    required this.transcript,
    required this.onStop,
  });

  final AppController controller;
  final String transcript;
  final Future<void> Function() onStop;

  @override
  Widget build(BuildContext context) {
    final copy = controller.copy;
    final palette = controller.palette;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: palette.accentPrimary,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.mic_rounded, color: Colors.white),
          const SizedBox(width: 10),
          SizedBox(
            width: 70,
            height: 28,
            child: _SpeechWaveform(level: controller.speechLevel),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  copy.assistantRecordingTitle,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 2),
                Text(
                  transcript.trim().isEmpty
                      ? copy.assistantRecordingHint
                      : transcript,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.82),
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              onStop();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            child: Text(copy.tapToStop),
          ),
        ],
      ),
    );
  }
}

class _SpeechWaveform extends StatelessWidget {
  const _SpeechWaveform({required this.level});

  final double level;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SpeechWaveformPainter(level: level),
      child: const SizedBox.expand(),
    );
  }
}

class _SpeechWaveformPainter extends CustomPainter {
  const _SpeechWaveformPainter({required this.level});

  final double level;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    const List<double> profile = <double>[
      0.34,
      0.56,
      0.82,
      1,
      0.68,
      0.45,
      0.78,
      0.54,
      0.32,
    ];
    final double center = size.height / 2;
    final double spacing = size.width / (profile.length - 1);
    for (int index = 0; index < profile.length; index += 1) {
      final double height = 5 + (size.height * 0.42 * profile[index] * level);
      final double x = spacing * index;
      canvas.drawLine(
        Offset(x, center - height / 2),
        Offset(x, center + height / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SpeechWaveformPainter oldDelegate) =>
      (oldDelegate.level - level).abs() > 0.01;
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip({
    required this.icon,
    required this.label,
    required this.foregroundColor,
    required this.backgroundColor,
    required this.onRemove,
  });

  final IconData icon;
  final String label;
  final Color foregroundColor;
  final Color backgroundColor;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onRemove,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 16, color: foregroundColor),
              const SizedBox(width: 6),
              Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: foregroundColor),
              ),
              const SizedBox(width: 4),
              Icon(Icons.close_rounded, size: 15, color: foregroundColor),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssistantAvatar extends StatelessWidget {
  const _AssistantAvatar({this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.28),
      child: Image.asset(
        'branding/app_icon.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        errorBuilder: (context, error, stackTrace) => Container(
          width: size,
          height: size,
          color: Theme.of(context).colorScheme.primary,
          alignment: Alignment.center,
          child: Icon(Icons.casino_rounded, size: size * 0.56),
        ),
      ),
    );
  }
}
