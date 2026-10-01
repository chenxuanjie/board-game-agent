part of '../business_panes.dart';

class DesktopAssistantPane extends StatefulWidget {
  const DesktopAssistantPane({super.key, required this.controller});

  final AppController controller;

  @override
  State<DesktopAssistantPane> createState() => DesktopAssistantPaneState();
}

class DesktopAssistantPaneState extends State<DesktopAssistantPane> {
  late final TextEditingController _draftController;
  late final ScrollController _scrollController;
  bool _showMessageTimes = false;
  bool _showJumpToBottom = false;
  bool _hasNewContent = false;
  String? _lastConversationId;
  bool _followNewMessages = true;
  final Map<String, double> _scrollOffsets = <String, double>{};
  final Map<String, String> _drafts = <String, String>{};
  final Map<String, GlobalKey> _messageKeys = <String, GlobalKey>{};
  Timer? _messageTimesTimer;
  bool _creating = false;
  final _composerKey = GlobalKey<AssistantComposerState>();
  final Set<String> _knownMessages = {};
  PageStorageBucket? _viewBucket;
  bool _restoredView = false;

  AppController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _draftController = TextEditingController();
    _scrollController = ScrollController()..addListener(_handleScrollChanged);
    _lastConversationId = controller.selectedConversationId;
    _knownMessages.addAll(
      controller
          .messagesForContext(
            useGlobalMode: controller.selectedConversationIsGlobal,
          )
          .map((m) => m.id),
    );
    controller.addListener(_handleControllerChanged);
    _scheduleInitialScrollToBottom();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _viewBucket = PageStorage.maybeOf(context);
    if (_restoredView) return;
    _restoredView = true;
    final saved = _viewBucket?.readState(context, identifier: controller);
    if (saved is AssistantViewState) {
      _drafts.addAll(saved.drafts);
      _scrollOffsets.addAll(saved.offsets);
      _draftController.text = _drafts[_lastConversationId] ?? '';
    }
  }

  @override
  void dispose() {
    controller.removeListener(_handleControllerChanged);
    _scrollController.removeListener(_handleScrollChanged);
    _saveScrollPosition();
    if (_lastConversationId != null) {
      _drafts[_lastConversationId!] = _draftController.text;
    }
    _viewBucket?.writeState(
      context,
      AssistantViewState(drafts: _drafts, offsets: _scrollOffsets),
      identifier: controller,
    );
    _draftController.dispose();
    _scrollController.dispose();
    _messageTimesTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!controller.hasGames) {
      return _DesktopNoGamesPane(
        controller: controller,
        title: controller.copy.desktopAssistantUnavailable,
        message: controller.copy.desktopAssistantUnavailableMessage,
      );
    }
    final AppPalette palette = AppPalette.of(context);
    final AiConversation? selectedConversation =
        controller.selectedConversation;
    if (selectedConversation == null) {
      return _DesktopAssistantEmptyPane(controller: controller);
    }
    final bool useGlobalMode = selectedConversation.isGlobal;
    final List<ChatMessage> messages = controller.messagesForContext(
      useGlobalMode: useGlobalMode,
    );
    final List<AiRunEvent> runEvents = controller.aiRunEventsForContext(
      useGlobalMode: useGlobalMode,
    );
    final bool showRun =
        runEvents.isNotEmpty ||
        controller.isSendingForContext(useGlobalMode: useGlobalMode);
    final int lastAssistantIndex = messages.lastIndexWhere(
      (ChatMessage message) => message.role == ChatRole.assistant,
    );
    final GameInfo game = selectedConversation.gameId == null
        ? controller.featuredGame
        : controller.games.firstWhere(
            (GameInfo item) => item.id == selectedConversation.gameId,
            orElse: () => controller.featuredGame,
          );
    final String assistantTitle = selectedConversation.title;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool narrow = constraints.maxWidth < 760;
        final double contentInset = math.max(
          16,
          (constraints.maxWidth - 900) / 2,
        );
        final double composerInset = contentInset;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Container(
              constraints: const BoxConstraints(minHeight: 68),
              padding: EdgeInsets.fromLTRB(
                narrow ? 12 : 24,
                16,
                narrow ? 12 : 24,
                16,
              ),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: palette.outline)),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        ConversationTitleButton(
                          title: assistantTitle,
                          tooltip: controller.copy.openConversations,
                          onPressed: () => showConversationDrawer(
                            context,
                            controller: controller,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('assistant-header-new-conversation'),
                    tooltip: controller.copy.newConversation,
                    onPressed: _creating ? null : _createConversation,
                    style: _desktopIconButtonStyle(palette),
                    icon: _creating
                        ? const SizedBox(
                            width: 17,
                            height: 17,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.edit_square, size: 20),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                children: <Widget>[
                  if (messages.isEmpty && !showRun)
                    LayoutBuilder(
                      builder: (context, box) => SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: box.maxHeight),
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              contentInset,
                              28,
                              contentInset,
                              28,
                            ),
                            child: AssistantWelcome(
                              copy: controller.copy,
                              gameTitle:
                                  !useGlobalMode ||
                                      controller.globalUseCurrentGameKnowledge
                                  ? game.title
                                  : null,
                              onPrompt: _usePrompt,
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    ListView(
                      key: const ValueKey('assistant-message-list'),
                      controller: _scrollController,
                      padding: EdgeInsets.fromLTRB(
                        contentInset,
                        30,
                        contentInset,
                        16,
                      ),
                      children: <Widget>[
                        for (
                          int index = 0;
                          index < messages.length;
                          index++
                        ) ...<Widget>[
                          if (showRun && index == lastAssistantIndex)
                            AiRunActivity(
                              events: runEvents,
                              isRunning: controller.isSendingForContext(
                                useGlobalMode: useGlobalMode,
                              ),
                              palette: palette,
                              copy: controller.copy,
                              contextKey: selectedConversation.id,
                              initialExpanded: controller
                                  .aiRunExpandedForContext(
                                    useGlobalMode: useGlobalMode,
                                  ),
                              onExpandedChanged: (bool expanded) =>
                                  controller.setAiRunExpandedForContext(
                                    useGlobalMode: useGlobalMode,
                                    expanded: expanded,
                                  ),
                            ),
                          if (!(messages[index].role == ChatRole.assistant &&
                              messages[index].isStreaming &&
                              messages[index].text.trim().isEmpty &&
                              showRun))
                            AssistantMessageEntrance(
                              key: ValueKey(
                                '${selectedConversation.id}:${messages[index].id}',
                              ),
                              animate: _knownMessages.add(messages[index].id),
                              child: MessageBubble(
                                key: _messageKeys.putIfAbsent(
                                  messages[index].id,
                                  GlobalKey.new,
                                ),
                                message: messages[index],
                                palette: palette,
                                copy: controller.copy,
                                showAssistantAvatar: false,
                                showAssistantActionLabels: true,
                                maxWidth: 780,
                                desktopLayout: true,
                                onSpeak:
                                    messages[index].role ==
                                            ChatRole.assistant &&
                                        controller.voiceReplyAvailable
                                    ? () => controller.speakMessage(
                                        messages[index].text,
                                      )
                                    : null,
                                speakTooltip: controller.copy.speakAgain,
                                onCopy: () => _copyAnswer(messages[index].text),
                                copyTooltip: controller.copy.copyAnswer,
                                onRetry: messages[index].canRetry
                                    ? () => controller.retryMessage(
                                        messages[index],
                                        useGlobalMode: useGlobalMode,
                                      )
                                    : null,
                                retryTooltip: controller.copy.retry,
                                showTimestamp: _showMessageTimes,
                                onTap: _toggleMessageTimes,
                              ),
                            ),
                        ],
                        if (showRun && lastAssistantIndex < 0)
                          AiRunActivity(
                            events: runEvents,
                            isRunning: controller.isSendingForContext(
                              useGlobalMode: useGlobalMode,
                            ),
                            palette: palette,
                            copy: controller.copy,
                            contextKey: selectedConversation.id,
                            initialExpanded: controller.aiRunExpandedForContext(
                              useGlobalMode: useGlobalMode,
                            ),
                            onExpandedChanged: (bool expanded) =>
                                controller.setAiRunExpandedForContext(
                                  useGlobalMode: useGlobalMode,
                                  expanded: expanded,
                                ),
                          ),
                      ],
                    ),
                  if (_showJumpToBottom)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 14,
                      child: Center(
                        child: FilledButton.tonalIcon(
                          onPressed: _jumpToBottom,
                          icon: const Icon(Icons.south_rounded, size: 17),
                          label: Text(
                            _hasNewContent
                                ? controller.copy.aiNewMessages
                                : controller.copy.desktopJumpToBottom,
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: palette.surfaceContainer,
                            foregroundColor: palette.textPrimary,
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 9,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(composerInset, 9, composerInset, 18),
              child: AssistantComposer(
                key: _composerKey,
                desktop: true,
                controller: controller,
                textController: _draftController,
                useGlobalMode: useGlobalMode,
                onSend: _send,
              ),
            ),
          ],
        );
      },
    );
  }

  /// Reveals a specific answer after navigation from the notification center.
  /// Missing or expired message IDs are intentionally ignored because the
  /// conversation itself is still a valid destination.
  void revealMessage(String? messageId) {
    final String? normalized = messageId?.trim();
    if (normalized == null || normalized.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final BuildContext? target = _messageKeys[normalized]?.currentContext;
      if (target == null || !mounted) return;
      Scrollable.ensureVisible(
        target,
        duration: AppMotion.duration(context, AppMotion.content),
        curve: Curves.easeOut,
        alignment: 0.2,
      );
    });
  }

  void _handleControllerChanged() {
    if (!mounted) return;
    final retainedIds = controller.conversations.map((item) => item.id).toSet();
    _drafts.removeWhere((id, _) => !retainedIds.contains(id));
    _scrollOffsets.removeWhere((id, _) => !retainedIds.contains(id));
    final String? conversationId = controller.selectedConversationId;
    final bool contextChanged = conversationId != _lastConversationId;
    if (contextChanged) {
      if (_lastConversationId != null &&
          retainedIds.contains(_lastConversationId)) {
        _saveScrollPosition();
        _drafts[_lastConversationId!] = _draftController.text;
      }
      _draftController.text = _drafts[conversationId] ?? '';
      _lastConversationId = conversationId;
      _knownMessages.addAll(
        controller
            .messagesForContext(
              useGlobalMode: controller.selectedConversationIsGlobal,
            )
            .map((m) => m.id),
      );
      _showJumpToBottom = false;
      _hasNewContent = false;
      _followNewMessages = true;
      _forceScrollToBottom = false;
    } else if (!_followNewMessages) {
      _showJumpToBottom = true;
      _hasNewContent = true;
    }
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (contextChanged) {
        final double? saved = conversationId == null
            ? null
            : _scrollOffsets[conversationId];
        if (saved == null) {
          _scrollToBottom(animated: false);
        } else {
          _scrollController.jumpTo(
            saved.clamp(0.0, _scrollController.position.maxScrollExtent),
          );
        }
      } else if (_forceScrollToBottom || _followNewMessages) {
        _scrollToBottom(
          animated: !controller.isSendingForContext(
            useGlobalMode: controller.selectedConversation?.isGlobal ?? false,
          ),
        );
      }
      _forceScrollToBottom = false;
    });
  }

  bool _forceScrollToBottom = true;

  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;
    final ScrollPosition position = _scrollController.position;
    return position.maxScrollExtent - position.pixels < 96;
  }

  void _handleScrollChanged() {
    if (!mounted) return;
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
    final String? conversationId = _lastConversationId;
    if (conversationId == null || !_scrollController.hasClients) return;
    _scrollOffsets[conversationId] = _scrollController.position.pixels;
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
      final saved = _scrollOffsets[_lastConversationId];
      if (saved == null) {
        _scrollToBottom(animated: false);
      } else {
        _scrollController.jumpTo(
          saved.clamp(0.0, _scrollController.position.maxScrollExtent),
        );
      }
      _followNewMessages = _isNearBottom();
      _showJumpToBottom = !_followNewMessages;
      _hasNewContent = false;
    });
  }

  void _toggleMessageTimes() {
    _messageTimesTimer?.cancel();
    if (_showMessageTimes) {
      setState(() => _showMessageTimes = false);
      return;
    }
    setState(() => _showMessageTimes = true);
    _messageTimesTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showMessageTimes = false);
    });
  }

  Future<void> _copyAnswer(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(controller.copy.answerCopied)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            controller.copy.localized('复制失败，请重试', 'Could not copy. Try again.'),
          ),
        ),
      );
    }
  }

  void _usePrompt(String prompt) {
    _draftController.text = prompt;
    _draftController.selection = TextSelection.collapsed(offset: prompt.length);
    _composerKey.currentState?.focusDraft();
  }

  Future<void> _createConversation() async {
    if (_creating) return;
    setState(() => _creating = true);
    try {
      await controller.createConversation(
        useGlobalMode: controller.selectedConversationIsGlobal,
      );
      if (mounted) _composerKey.currentState?.focusDraft();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(controller.copy.conversationSaveFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _send() async {
    final String text = _draftController.text.trim();
    final bool useGlobalMode = controller.selectedConversationIsGlobal;
    if (text.isEmpty ||
        controller.isSendingForContext(useGlobalMode: useGlobalMode)) {
      return;
    }
    if (!controller.hasSelectedAiModel) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(controller.copy.aiApiModelRequired)),
      );
      return;
    }
    _draftController.clear();
    await controller.sendPrompt(text, useGlobalMode: useGlobalMode);
  }
}

class _DesktopAssistantEmptyPane extends StatelessWidget {
  const _DesktopAssistantEmptyPane({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final AppCopy copy = controller.copy;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.forum_outlined, size: 42, color: palette.primary),
            const SizedBox(height: 14),
            Text(
              copy.desktopNoSession,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              copy.desktopNoSessionHint,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: palette.textSecondary),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => controller.openGlobalAssistant(),
              icon: const Icon(Icons.auto_awesome_rounded),
              label: Text(copy.desktopOpenGlobalAssistant),
            ),
          ],
        ),
      ),
    );
  }
}
