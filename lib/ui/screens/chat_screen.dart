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

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.initialDraft ?? '');
    _scrollController = ScrollController();
    _textController.addListener(_onDraftChanged);
    widget.controller.addListener(_onControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.customGreeting != null) {
        widget.controller.resetConversation(greeting: widget.customGreeting);
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
            onPressed: controller.clearConversation,
            icon: const Icon(Icons.delete_sweep_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: _StatusBanner(controller: controller),
            ),
            Expanded(
              child: AnimatedBuilder(
                animation: controller,
                builder: (context, _) {
                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                    itemCount: controller.messages.length + (controller.isSending ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= controller.messages.length) {
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

                      final ChatMessage message = controller.messages[index];
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
    await widget.controller.sendPrompt(text);
  }

  Future<void> _toggleListening() async {
    final controller = widget.controller;
    if (!controller.speechAvailable) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(controller.copy.micUnavailable)),
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
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.controller,
  });

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final copy = controller.copy;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: controller.palette.cardSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: controller.palette.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: controller.palette.accentSecondary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  copy.mockBadge,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: controller.palette.accentSecondary,
                      ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: controller.voiceReplyEnabled
                      ? controller.palette.accentPrimary.withValues(alpha: 0.12)
                      : controller.palette.homeTextPrimary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  controller.voiceReplyEnabled ? copy.voiceReplyTitle : copy.voiceReplyOff,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: controller.voiceReplyEnabled
                            ? controller.palette.accentPrimary
                            : controller.palette.homeTextPrimary,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(copy.assistantModeHint),
          const SizedBox(height: 10),
          SwitchListTile.adaptive(
            value: controller.voiceReplyEnabled,
            contentPadding: EdgeInsets.zero,
            activeThumbColor: controller.palette.accentPrimary,
            activeTrackColor: controller.palette.accentPrimary.withValues(alpha: 0.45),
            title: Text(copy.voiceReplySwitchLabel),
            subtitle: Text(copy.voiceReplyHint),
            onChanged: controller.setVoiceReplyEnabled,
          ),
          const SizedBox(height: 4),
          Text(
            controller.speechAvailable ? copy.speechReady : copy.micUnavailable,
            style: Theme.of(context).textTheme.bodyMedium,
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
    required this.onSend,
    required this.onMicTap,
  });

  final AppController controller;
  final TextEditingController textController;
  final bool canSend;
  final Future<void> Function() onSend;
  final Future<void> Function() onMicTap;

  @override
  Widget build(BuildContext context) {
    final copy = controller.copy;
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
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Colors.white,
                        ),
                  ),
                ),
              ],
            ),
          ),
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: textController,
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: copy.messageHint,
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
                    : controller.palette.homeTextPrimary.withValues(alpha: 0.16),
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
