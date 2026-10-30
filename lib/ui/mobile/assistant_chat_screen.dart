import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/theme/app_motion.dart';
import 'package:flutter/services.dart';
import '../shared/app_modals.dart';

import '../../features/assistant/models/ai_run.dart';
import '../../features/assistant/models/assistant_mode.dart';
import '../../features/assistant/models/chat_message.dart';
import '../../app/state/app_controller.dart';
import '../../core/theme/app_palette.dart';
import '../shared/assistant/ai_run_activity.dart';
import '../shared/assistant/assistant_presentation.dart';
import '../shared/assistant/assistant_view_state.dart';
import '../shared/assistant/conversation_drawer.dart';
import '../shared/assistant/message_bubble.dart';
import '../shared/assistant/conversation_search_dialog.dart';
import '../shared/assistant/assistant_toolbar_icon.dart';
import '../shared/assistant/conversation_actions.dart';

class AssistantChatScreen extends StatefulWidget {
  const AssistantChatScreen({
    super.key,
    required this.controller,
    this.initialDraft,
    this.customTitle,
    this.useGlobalMode = false,
    this.keyboardVisible,
  });

  final AppController controller;
  final String? initialDraft;
  final String? customTitle;
  final bool useGlobalMode;
  final bool? keyboardVisible;

  @override
  State<AssistantChatScreen> createState() => _AssistantChatScreenState();
}

class _AssistantChatScreenState extends State<AssistantChatScreen> {
  late final TextEditingController _textController;
  late final ScrollController _scrollController;
  bool _showMessageTimes = false;
  bool _followNewMessages = true;
  bool _showJumpToBottom = false;
  bool _hasNewContent = false;
  String? _lastScrollContextKey;
  final Map<String, double> _scrollOffsets = <String, double>{};
  final Map<String, String> _drafts = <String, String>{};
  Timer? _messageTimeVisibilityTimer;
  final _composerKey = GlobalKey<AssistantComposerState>();
  bool _creating = false;
  final Set<String> _knownMessages = {};
  final Map<String, GlobalKey> _messageKeys = {};
  Timer? _searchHighlightTimer;
  String? _searchHighlight;
  bool _changingConversation = false;
  PageStorageBucket? _viewBucket;
  bool _restoredView = false;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.initialDraft ?? '');
    _scrollController = ScrollController();
    _textController.addListener(_onDraftChanged);
    final selectedConversation = widget.controller.selectedConversation;
    if (widget.useGlobalMode) {
      if (selectedConversation?.isGlobal != true) {
        widget.controller.openGlobalAssistant();
      }
    } else if (widget.controller.hasGames &&
        (selectedConversation?.isGlobal == true ||
            selectedConversation?.gameId !=
                widget.controller.selectedGame.id)) {
      widget.controller.openGameAssistant(widget.controller.selectedGame.id);
    }
    _rememberCurrentMessages();
    widget.controller.addListener(_onControllerChanged);
    _lastScrollContextKey = _conversationContextKey;
    _scrollController.addListener(_handleScrollChanged);
    _scheduleInitialScrollToBottom();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _viewBucket = PageStorage.maybeOf(context);
    if (_restoredView) return;
    _restoredView = true;
    final saved = _viewBucket?.readState(
      context,
      identifier: widget.controller,
    );
    if (saved is AssistantViewState) {
      _drafts.addAll(saved.drafts);
      _scrollOffsets.addAll(saved.offsets);
      _textController.text =
          widget.initialDraft ?? _drafts[_conversationContextKey] ?? '';
    }
  }

  @override
  void dispose() {
    widget.controller.stopSpeaking();
    widget.controller.removeListener(_onControllerChanged);
    _scrollController.removeListener(_handleScrollChanged);
    _saveScrollPosition();
    _drafts[_lastScrollContextKey ?? _conversationContextKey] =
        _textController.text;
    _viewBucket?.writeState(
      context,
      AssistantViewState(drafts: _drafts, offsets: _scrollOffsets),
      identifier: widget.controller,
    );
    _textController.removeListener(_onDraftChanged);
    _textController.dispose();
    _scrollController.dispose();
    _messageTimeVisibilityTimer?.cancel();
    _searchHighlightTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final copy = controller.copy;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final palette = AppPalette.of(context);
    final canGoBack = ModalRoute.of(context)?.canPop ?? false;
    final headerInset = MediaQuery.paddingOf(context).top + 76;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        toolbarHeight: 64,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        leading: canGoBack
            ? BackButton(
                key: const ValueKey('assistant-header-back'),
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null,
        leadingWidth: canGoBack ? 48 : 0,
        titleSpacing: canGoBack ? 0 : 16,
        flexibleSpace: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                palette.pageBackground,
                palette.pageBackground.withValues(alpha: .88),
                palette.pageBackground.withValues(alpha: 0),
              ],
              stops: const [0, .62, 1],
            ),
          ),
        ),
        title: Align(
          alignment: Alignment.centerLeft,
          child: Material(
            color: palette.surface.withValues(alpha: .95),
            shape: const CircleBorder(),
            child: AssistantHeaderPressFeedback(
              child: IconButton(
                key: const ValueKey('assistant-conversations-trigger'),
                tooltip: copy.openConversations,
                onPressed: () =>
                    showConversationDrawer(context, controller: controller),
                icon: AssistantToolbarIcon(
                  asset: 'assets/mobile/assistant/menu.png',
                  size: 24,
                  color: palette.textPrimary,
                ),
              ),
            ),
          ),
        ),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: AssistantConversationActions(
              copy: copy,
              title:
                  controller.selectedConversation?.title ??
                  widget.customTitle ??
                  copy.globalAiTitle,
              creating: _creating,
              onCreate: _createConversation,
              onFind:
                  controller
                      .messagesForContext(useGlobalMode: _useGlobalMode)
                      .isEmpty
                  ? null
                  : () => unawaited(_findInConversation()),
              onDelete:
                  controller.selectedConversation == null ||
                      _changingConversation
                  ? null
                  : () => unawaited(_deleteConversation()),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: screenWidth >= 980 ? 960 : double.infinity,
            ),
            child: Column(
              children: <Widget>[
                Expanded(
                  child: Stack(
                    children: <Widget>[
                      AnimatedBuilder(
                        animation: controller,
                        builder: (context, _) {
                          final messages = controller.messagesForContext(
                            useGlobalMode: _useGlobalMode,
                          );
                          return _MessageList(
                            controller: controller,
                            messages: messages,
                            scrollController: _scrollController,
                            onQuickPrompt: _sendQuickPrompt,
                            onCopy: _copyAssistantAnswer,
                            useGlobalMode: _useGlobalMode,
                            showMessageTimes: _showMessageTimes,
                            onMessageTap: _showMessageTimesTemporarily,
                            runContextKey: _conversationContextKey,
                            runExpanded: controller.aiRunExpandedForContext(
                              useGlobalMode: _useGlobalMode,
                            ),
                            onRunExpandedChanged: (bool expanded) =>
                                controller.setAiRunExpandedForContext(
                                  useGlobalMode: _useGlobalMode,
                                  expanded: expanded,
                                ),
                            animateMessage: _knownMessages.add,
                            messageKeys: _messageKeys,
                            highlightedId: _searchHighlight,
                            headerInset: headerInset,
                          );
                        },
                      ),
                      if (_showJumpToBottom)
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: 8,
                          child: Center(
                            child: _JumpToBottomButton(
                              label: _hasNewContent
                                  ? copy.aiNewMessages
                                  : copy.desktopJumpToBottom,
                              onPressed: _jumpToBottom,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    screenWidth >= 720 ? 28 : 16,
                    8,
                    screenWidth >= 720 ? 28 : 16,
                    12,
                  ),
                  child: _Composer(
                    controller: controller,
                    textController: _textController,
                    composerKey: _composerKey,
                    useGlobalMode: _useGlobalMode,
                    onSend: _sendCurrentText,
                    onMicTap: _toggleListening,
                    keyboardVisible:
                        widget.keyboardVisible ??
                        MediaQuery.viewInsetsOf(context).bottom > 0,
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
    final retainedIds = widget.controller.conversations
        .map((item) => item.id)
        .toSet();
    _drafts.removeWhere((id, _) => !retainedIds.contains(id));
    _scrollOffsets.removeWhere((id, _) => !retainedIds.contains(id));
    final String contextKey = _conversationContextKey;
    final bool contextChanged =
        _lastScrollContextKey != null && _lastScrollContextKey != contextKey;
    if (contextChanged) {
      _searchHighlightTimer?.cancel();
      _searchHighlight = null;
      _messageKeys.clear();
      _rememberCurrentMessages();
      if (retainedIds.contains(_lastScrollContextKey)) {
        _saveScrollPosition();
        _drafts[_lastScrollContextKey!] = _textController.text;
      }
      _textController.text = _drafts[contextKey] ?? '';
      _lastScrollContextKey = contextKey;
      _followNewMessages = true;
      _showJumpToBottom = false;
      _hasNewContent = false;
    } else if (!_followNewMessages) {
      _showJumpToBottom = true;
      _hasNewContent = true;
    }
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      if (contextChanged) {
        final double? saved = _scrollOffsets[contextKey];
        if (saved == null) {
          _scrollToBottom(animated: false);
        } else {
          _scrollController.jumpTo(
            saved.clamp(0.0, _scrollController.position.maxScrollExtent),
          );
        }
      } else if (_followNewMessages) {
        // During streaming, keeping the viewport pinned is more important
        // than animating every 16 ms batch; animation can lag behind deltas.
        _scrollToBottom(
          animated: !widget.controller.isSendingForContext(
            useGlobalMode: _useGlobalMode,
          ),
        );
      }
    });
  }

  void _rememberCurrentMessages() => _knownMessages.addAll(
    widget.controller
        .messagesForContext(useGlobalMode: _useGlobalMode)
        .map((m) => m.id),
  );

  bool get _useGlobalMode =>
      widget.controller.selectedConversation?.isGlobal ?? widget.useGlobalMode;

  String get _conversationContextKey =>
      widget.controller.selectedConversationId ??
      (_useGlobalMode ? 'global' : 'game:${widget.controller.selectedGame.id}');

  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;
    final ScrollPosition position = _scrollController.position;
    return position.maxScrollExtent - position.pixels < 96;
  }

  void _handleScrollChanged() {
    if (!mounted || !_scrollController.hasClients) return;
    final bool nearBottom = _isNearBottom();
    if (nearBottom) {
      if (_followNewMessages || !_showJumpToBottom) return;
      setState(() {
        _followNewMessages = true;
        _showJumpToBottom = false;
        _hasNewContent = false;
      });
      return;
    }
    _saveScrollPosition();
    if (_followNewMessages || !_showJumpToBottom) {
      setState(() {
        _followNewMessages = false;
        _showJumpToBottom = true;
      });
    }
  }

  void _saveScrollPosition() {
    if (_lastScrollContextKey == null || !_scrollController.hasClients) return;
    _scrollOffsets[_lastScrollContextKey!] = _scrollController.position.pixels;
  }

  void _scrollToBottom({bool animated = true}) {
    if (!_scrollController.hasClients) return;
    final double target = _scrollController.position.maxScrollExtent;
    if (!animated) {
      _scrollController.jumpTo(target);
      return;
    }
    _scrollController.animateTo(
      target,
      duration: AppMotion.duration(context, AppMotion.content),
      curve: Curves.easeOut,
    );
  }

  void _jumpToBottom() {
    _followNewMessages = true;
    _showJumpToBottom = false;
    _hasNewContent = false;
    _scrollToBottom();
    if (mounted) setState(() {});
  }

  void _scheduleInitialScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      final saved = _scrollOffsets[_conversationContextKey];
      if (saved == null) {
        _scrollToBottom(animated: false);
      } else {
        _scrollController.jumpTo(
          saved.clamp(0.0, _scrollController.position.maxScrollExtent),
        );
      }
      _followNewMessages = _isNearBottom();
      _showJumpToBottom = !_followNewMessages;
    });
  }

  void _onDraftChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _findInConversation() async {
    final controller = widget.controller;
    final id = controller.selectedConversationId;
    final identity = controller.identityUserId;
    final messages = controller.messagesForContext(
      useGlobalMode: _useGlobalMode,
    );
    if (id == null || messages.isEmpty) return;
    final target = await showAppDialog<String>(
      context: context,
      builder: (_) => ConversationSearchDialog(
        messages: List.of(messages),
        copy: controller.copy,
      ),
    );
    if (!mounted ||
        target == null ||
        id != controller.selectedConversationId ||
        identity != controller.identityUserId) {
      return;
    }
    await _revealSearchResult(target, id, identity);
  }

  Future<void> _revealSearchResult(
    String messageId,
    String conversationId,
    String? identity,
  ) async {
    if (!_scrollController.hasClients) return;
    _searchHighlightTimer?.cancel();
    setState(() {
      _followNewMessages = false;
      _searchHighlight = messageId;
    });
    _scrollController.jumpTo(0);
    await WidgetsBinding.instance.endOfFrame;
    for (var step = 0; step < 500; step++) {
      if (!mounted ||
          !_scrollController.hasClients ||
          widget.controller.selectedConversationId != conversationId ||
          widget.controller.identityUserId != identity) {
        return;
      }
      final targetContext = _messageKeys[messageId]?.currentContext;
      if (targetContext != null && targetContext.mounted && mounted) {
        await Scrollable.ensureVisible(
          targetContext,
          alignment: .2,
          duration: AppMotion.duration(context, AppMotion.content),
          curve: AppMotion.curve,
        );
        if (!mounted) return;
        _searchHighlightTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _searchHighlight = null);
        });
        return;
      }
      final position = _scrollController.position;
      final next = (position.pixels + position.viewportDimension * .8).clamp(
        0.0,
        position.maxScrollExtent,
      );
      if (next <= position.pixels) break;
      _scrollController.jumpTo(next);
      await WidgetsBinding.instance.endOfFrame;
    }
    if (mounted) {
      setState(() => _searchHighlight = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.controller.copy.localized(
              '暂时无法定位消息',
              'Could not locate this message',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _deleteConversation() async {
    if (_changingConversation) return;
    final controller = widget.controller;
    final conversation = controller.selectedConversation;
    if (conversation == null) return;
    final identity = controller.identityUserId;
    final copy = controller.copy;
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(copy.localized('删除对话？', 'Delete conversation?')),
        content: Text(
          copy.localized(
            '将删除“${conversation.title}”及其消息，此操作无法撤销。',
            'This conversation and its messages will be deleted.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(copy.localized('取消', 'Cancel')),
          ),
          TextButton(
            key: const ValueKey('assistant-confirm-change'),
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: AppPalette.of(context).error,
            ),
            child: Text(copy.localized('删除', 'Delete')),
          ),
        ],
      ),
    );
    if (!mounted ||
        confirmed != true ||
        controller.selectedConversationId != conversation.id ||
        controller.identityUserId != identity) {
      return;
    }
    setState(() => _changingConversation = true);
    try {
      await controller.deleteConversation(conversation.id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              copy.localized(
                '操作未完成，请重试',
                'Could not complete the action. Try again.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _changingConversation = false);
    }
  }

  Future<void> _copyAssistantAnswer(String text) async {
    final String value = text.trim();
    if (value.isEmpty) {
      return;
    }
    try {
      await Clipboard.setData(ClipboardData(text: value));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.controller.copy.localized(
                '复制失败，请重试',
                'Could not copy. Try again.',
              ),
            ),
          ),
        );
      }
      return;
    }
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(widget.controller.copy.answerCopied)),
      );
  }

  void _showMessageTimesTemporarily() {
    _messageTimeVisibilityTimer?.cancel();
    if (!mounted) {
      return;
    }
    if (_showMessageTimes) {
      setState(() {
        _showMessageTimes = false;
      });
      _messageTimeVisibilityTimer = null;
      return;
    }
    setState(() {
      _showMessageTimes = true;
    });
    _messageTimeVisibilityTimer = Timer(const Duration(seconds: 4), () {
      _messageTimeVisibilityTimer = null;
      if (!mounted) {
        return;
      }
      setState(() {
        _showMessageTimes = false;
      });
    });
  }

  Future<void> _createConversation() async {
    if (_creating) return;
    setState(() => _creating = true);
    try {
      await widget.controller.createConversation(useGlobalMode: _useGlobalMode);
      if (mounted) _composerKey.currentState?.focusDraft();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.controller.copy.conversationSaveFailed),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _sendCurrentText() async {
    final text = _textController.text.trim();
    if (text.isEmpty ||
        widget.controller.isSendingForContext(useGlobalMode: _useGlobalMode)) {
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
    await widget.controller.sendPrompt(text, useGlobalMode: _useGlobalMode);
  }

  Future<void> _sendQuickPrompt(String prompt) async {
    _textController.text = prompt;
    _textController.selection = TextSelection.collapsed(offset: prompt.length);
    _composerKey.currentState?.focusDraft();
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
}

class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.controller,
    required this.messages,
    required this.scrollController,
    required this.onQuickPrompt,
    required this.onCopy,
    required this.useGlobalMode,
    required this.showMessageTimes,
    required this.onMessageTap,
    required this.runContextKey,
    required this.runExpanded,
    required this.onRunExpandedChanged,
    required this.animateMessage,
    required this.messageKeys,
    required this.highlightedId,
    required this.headerInset,
  });

  final AppController controller;
  final List<ChatMessage> messages;
  final ScrollController scrollController;
  final Future<void> Function(String prompt) onQuickPrompt;
  final Future<void> Function(String text) onCopy;
  final bool useGlobalMode;
  final bool showMessageTimes;
  final VoidCallback onMessageTap;
  final String runContextKey;
  final bool? runExpanded;
  final ValueChanged<bool> onRunExpandedChanged;
  final bool Function(String id) animateMessage;
  final Map<String, GlobalKey> messageKeys;
  final String? highlightedId;
  final double headerInset;

  @override
  Widget build(BuildContext context) {
    final copy = controller.copy;
    final List<AiRunEvent> runEvents = controller.aiRunEventsForContext(
      useGlobalMode: useGlobalMode,
    );
    final bool showRun =
        runEvents.isNotEmpty ||
        controller.isSendingForContext(useGlobalMode: useGlobalMode);
    final int lastAssistantIndex = messages.lastIndexWhere(
      (ChatMessage message) => message.role == ChatRole.assistant,
    );
    if (messages.isEmpty && !showRun) {
      return LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, headerInset + 12, 20, 28),
              child: AssistantWelcome(
                copy: copy,
                compact: constraints.maxHeight - headerInset < 320,
                gameTitle:
                    !useGlobalMode || controller.globalUseCurrentGameKnowledge
                    ? controller.selectedGame.title
                    : null,
                onPrompt: (prompt) => onQuickPrompt(prompt),
              ),
            ),
          ),
        ),
      );
    }

    return ListView(
      controller: scrollController,
      padding: EdgeInsets.fromLTRB(16, headerInset + 6, 16, 16),
      children: <Widget>[
        for (int index = 0; index < messages.length; index++) ...<Widget>[
          if (showRun && index == lastAssistantIndex)
            AiRunActivity(
              events: runEvents,
              isRunning: controller.isSendingForContext(
                useGlobalMode: useGlobalMode,
              ),
              palette: AppPalette.of(context),
              copy: copy,
              contextKey: runContextKey,
              initialExpanded: runExpanded,
              onExpandedChanged: onRunExpandedChanged,
            ),
          if (!(messages[index].role == ChatRole.assistant &&
              messages[index].isStreaming &&
              messages[index].text.trim().isEmpty &&
              showRun))
            AssistantMessageEntrance(
              key: ValueKey('$runContextKey:${messages[index].id}'),
              animate: animateMessage(messages[index].id),
              child: AnimatedContainer(
                key: messageKeys.putIfAbsent(messages[index].id, GlobalKey.new),
                duration: AppMotion.duration(context),
                decoration: BoxDecoration(
                  color: highlightedId == messages[index].id
                      ? AppPalette.of(context).primary.withValues(alpha: .10)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: MessageBubble(
                  message: messages[index],
                  palette: AppPalette.of(context),
                  copy: copy,
                  onSpeak:
                      messages[index].role == ChatRole.assistant &&
                          controller.voiceReplyAvailable
                      ? () => controller.speakMessage(messages[index].text)
                      : null,
                  speakTooltip: copy.speakAgain,
                  onCopy:
                      messages[index].role == ChatRole.assistant &&
                          !messages[index].isStreaming &&
                          !messages[index].isFailed
                      ? () => onCopy(messages[index].text)
                      : null,
                  copyTooltip: copy.copyAnswer,
                  onRetry: messages[index].canRetry
                      ? () => controller.retryMessage(
                          messages[index],
                          useGlobalMode: useGlobalMode,
                        )
                      : null,
                  retryTooltip: copy.retry,
                  showTimestamp: showMessageTimes,
                  onTap: onMessageTap,
                ),
              ),
            ),
        ],
        if (showRun && lastAssistantIndex < 0)
          AiRunActivity(
            events: runEvents,
            isRunning: controller.isSendingForContext(
              useGlobalMode: useGlobalMode,
            ),
            palette: AppPalette.of(context),
            copy: copy,
            contextKey: runContextKey,
            initialExpanded: runExpanded,
            onExpandedChanged: onRunExpandedChanged,
          ),
      ],
    );
  }
}

class _JumpToBottomButton extends StatelessWidget {
  const _JumpToBottomButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      icon: const Icon(Icons.south_rounded, size: 17),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: palette.surfaceContainer,
        foregroundColor: palette.textPrimary,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.textController,
    required this.composerKey,
    required this.useGlobalMode,
    required this.onSend,
    required this.onMicTap,
    required this.keyboardVisible,
  });
  final AppController controller;
  final TextEditingController textController;
  final GlobalKey<AssistantComposerState> composerKey;
  final bool useGlobalMode;
  final Future<void> Function() onSend;
  final Future<void> Function() onMicTap;
  final bool keyboardVisible;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (controller.isListening)
        _RecordingBanner(
          controller: controller,
          transcript: textController.text,
          onStop: onMicTap,
        ),
      AssistantComposer(
        key: composerKey,
        controller: controller,
        textController: textController,
        useGlobalMode: useGlobalMode,
        onSend: onSend,
        onMicTap: onMicTap,
        keyboardVisible: keyboardVisible,
      ),
    ],
  );
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
    final palette = AppPalette.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: palette.primary,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.mic_rounded, color: palette.onPrimary),
          const SizedBox(width: 10),
          SizedBox(
            width: 70,
            height: 28,
            child: _SpeechWaveform(
              level: controller.speechLevel,
              color: palette.onPrimary,
            ),
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
                  ).textTheme.titleSmall?.copyWith(color: palette.onPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  transcript.trim().isEmpty
                      ? copy.assistantRecordingHint
                      : transcript,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: palette.onPrimary.withValues(alpha: 0.82),
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              onStop();
            },
            style: TextButton.styleFrom(foregroundColor: palette.onPrimary),
            child: Text(copy.tapToStop),
          ),
        ],
      ),
    );
  }
}

class _SpeechWaveform extends StatelessWidget {
  const _SpeechWaveform({required this.level, required this.color});

  final double level;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SpeechWaveformPainter(level: level, color: color),
      child: const SizedBox.expand(),
    );
  }
}

class _SpeechWaveformPainter extends CustomPainter {
  const _SpeechWaveformPainter({required this.level, required this.color});

  final double level;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color.withValues(alpha: 0.9)
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
      (oldDelegate.level - level).abs() > 0.01 || oldDelegate.color != color;
}
