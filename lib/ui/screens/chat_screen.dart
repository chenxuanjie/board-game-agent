import 'package:flutter/material.dart';

import '../../models/chat_message.dart';
import '../../state/app_controller.dart';
import '../widgets/message_bubble.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
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
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
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
    final palette = controller.palette;
    final canSend =
        _textController.text.trim().isNotEmpty && !controller.isSending;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(widget.customTitle ?? controller.featuredGame.title),
            Text(
              widget.customSubtitle ?? copy.assistantMode,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            tooltip: copy.clearChat,
            onPressed: () => controller.clearConversationForContext(
              useGlobalMode: widget.useGlobalMode,
            ),
            icon: const Icon(Icons.delete_sweep_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: AnimatedBuilder(
                animation: controller,
                builder: (context, _) {
                  final messages = controller.messagesForContext(
                    useGlobalMode: widget.useGlobalMode,
                  );
                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                    itemCount: messages.length + (controller.isSending ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= messages.length) {
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(top: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: palette.messageAssistantBubble,
                              borderRadius: BorderRadius.circular(22),
                            ),
                            child: Text(copy.listening),
                          ),
                        );
                      }

                      final ChatMessage message = messages[index];
                      return MessageBubble(
                        message: message,
                        palette: palette,
                        onSpeak: message.role == ChatRole.assistant
                            ? () => controller.speakMessage(message.text)
                            : () {},
                      );
                    },
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _Composer(
                controller: controller,
                textController: _textController,
                canSend: canSend,
                useGlobalMode: widget.useGlobalMode,
                onSend: _sendCurrentText,
                onMicTap: _toggleListening,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) {
          return;
        }
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 80,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
        );
      });
    }
  }

  void _onDraftChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _sendCurrentText() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      return;
    }

    _textController.clear();
    await widget.controller.sendPrompt(
      text,
      useGlobalMode: widget.useGlobalMode,
    );
  }

  Future<void> _toggleListening() async {
    final controller = widget.controller;
    if (!controller.speechAvailable) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(controller.copy.micUnavailable)));
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
  });

  final AppController controller;
  final TextEditingController textController;
  final bool canSend;
  final bool useGlobalMode;
  final Future<void> Function() onSend;
  final Future<void> Function() onMicTap;

  @override
  Widget build(BuildContext context) {
    final copy = controller.copy;
    final palette = controller.palette;
    final bool smartSupplement = controller.allowSmartSupplement(
      useGlobalMode: useGlobalMode,
    );
    final List<Widget> activeFeatureChips = <Widget>[
      if (smartSupplement)
        _FeatureChip(
          icon: Icons.auto_awesome_rounded,
          label: copy.smartSupplementLabel,
          foregroundColor: palette.accentSecondary,
          backgroundColor: palette.accentSecondary.withValues(alpha: 0.14),
          onRemove: () => controller.setAllowSmartSupplement(
            false,
            useGlobalMode: useGlobalMode,
          ),
        ),
      if (controller.voiceReplyEnabled)
        _FeatureChip(
          icon: Icons.graphic_eq_rounded,
          label: copy.voiceReplyTitle,
          foregroundColor: palette.accentPrimary,
          backgroundColor: palette.accentPrimary.withValues(alpha: 0.14),
          onRemove: () => controller.setVoiceReplyEnabled(false),
        ),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (controller.isListening)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: controller.palette.accentPrimary,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: <Widget>[
                const Icon(Icons.mic, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    copy.tapToStop,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyLarge?.copyWith(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        if (activeFeatureChips.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: activeFeatureChips,
              ),
            ),
          ),
        Row(
          children: <Widget>[
            _ComposerActionsButton(
              controller: controller,
              useGlobalMode: useGlobalMode,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: textController,
                minLines: 1,
                maxLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: canSend ? (_) => onSend() : null,
                decoration: InputDecoration(
                  hintText: copy.messageHint,
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 10),
            IconButton.filled(
              style: IconButton.styleFrom(
                backgroundColor: controller.isListening
                    ? controller.palette.accentSecondary
                    : controller.palette.accentPrimary,
                foregroundColor: Colors.white,
              ),
              onPressed: onMicTap,
              icon: Icon(
                controller.isListening ? Icons.stop_rounded : Icons.mic_rounded,
              ),
            ),
            const SizedBox(width: 10),
            IconButton.filledTonal(
              style: IconButton.styleFrom(
                backgroundColor: canSend
                    ? controller.palette.accentSecondary
                    : controller.palette.homeTextPrimary.withValues(
                        alpha: 0.16,
                      ),
                foregroundColor: canSend
                    ? Colors.white
                    : controller.palette.homeTextPrimary.withValues(alpha: 0.4),
              ),
              onPressed: canSend ? onSend : null,
              icon: const Icon(Icons.send_rounded),
            ),
          ],
        ),
      ],
    );
  }
}

enum _ComposerAction { smartSupplement, voiceReply }

class _ComposerActionsButton extends StatelessWidget {
  const _ComposerActionsButton({
    required this.controller,
    required this.useGlobalMode,
  });

  final AppController controller;
  final bool useGlobalMode;

  @override
  Widget build(BuildContext context) {
    final copy = controller.copy;
    final palette = controller.palette;
    final bool smartSupplement = controller.allowSmartSupplement(
      useGlobalMode: useGlobalMode,
    );

    return PopupMenuButton<_ComposerAction>(
      tooltip: copy.askAnything,
      color: palette.cardSurface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: palette.cardBorder),
      ),
      onSelected: (_ComposerAction action) async {
        switch (action) {
          case _ComposerAction.smartSupplement:
            await controller.setAllowSmartSupplement(
              !smartSupplement,
              useGlobalMode: useGlobalMode,
            );
            break;
          case _ComposerAction.voiceReply:
            await controller.setVoiceReplyEnabled(!controller.voiceReplyEnabled);
            break;
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<_ComposerAction>>[
        CheckedPopupMenuItem<_ComposerAction>(
          value: _ComposerAction.smartSupplement,
          checked: smartSupplement,
          child: Row(
            children: <Widget>[
              Icon(
                Icons.auto_awesome_rounded,
                size: 18,
                color: palette.accentSecondary,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(copy.smartSupplementSwitchLabel)),
            ],
          ),
        ),
        CheckedPopupMenuItem<_ComposerAction>(
          value: _ComposerAction.voiceReply,
          checked: controller.voiceReplyEnabled,
          child: Row(
            children: <Widget>[
              Icon(
                Icons.graphic_eq_rounded,
                size: 18,
                color: palette.accentPrimary,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(copy.voiceReplySwitchLabel)),
            ],
          ),
        ),
      ],
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: palette.inputFill,
          shape: BoxShape.circle,
          border: Border.all(color: palette.cardBorder),
        ),
        child: Icon(
          Icons.add_rounded,
          color: palette.homeTextPrimary.withValues(alpha: 0.9),
          size: 28,
        ),
      ),
    );
  }
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 18, color: foregroundColor),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: foregroundColor,
              fontSize: 15,
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(
                Icons.close_rounded,
                size: 18,
                color: foregroundColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
