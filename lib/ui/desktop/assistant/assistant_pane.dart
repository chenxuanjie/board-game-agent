part of '../business_panes.dart';

class DesktopAssistantPane extends StatefulWidget {
  const DesktopAssistantPane({
    super.key,
    required this.controller,
    this.onConfigureAi,
  });

  final AppController controller;
  final VoidCallback? onConfigureAi;

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
  bool _changingConversation = false;
  String? _searchHighlight;
  Timer? _searchHighlightTimer;
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
    controller.assistantContentChanges.addListener(_handleContentChanged);
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
    controller.assistantContentChanges.removeListener(_handleContentChanged);
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
    _searchHighlightTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                8,
                narrow ? 12 : 24,
                8,
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
                  AssistantConversationActions(
                    copy: controller.copy,
                    title: assistantTitle,
                    creating: _creating,
                    onCreate: _createConversation,
                    onFind: messages.isEmpty
                        ? null
                        : () => unawaited(_findInConversation()),
                    onDelete:
                        _changingConversation || selectedConversation.isDraft
                        ? null
                        : () => unawaited(_deleteConversation()),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                children: <Widget>[
                  AnimatedBuilder(
                    animation: controller.assistantContentChanges,
                    builder: (context, _) {
                      final messages = controller.messagesForContext(
                        useGlobalMode: useGlobalMode,
                      );
                      final runEvents = controller.aiRunEventsForContext(
                        useGlobalMode: useGlobalMode,
                      );
                      final showRun =
                          runEvents.isNotEmpty ||
                          controller.isSendingForContext(
                            useGlobalMode: useGlobalMode,
                          );
                      final lastAssistantIndex = messages.lastIndexWhere(
                        (m) => m.role == ChatRole.assistant,
                      );
                      return AssistantConversationTransition(
                        identity: selectedConversation.id,
                        onMetricsChanged: () {
                          if (_followNewMessages) _scheduleContentScroll();
                        },
                        compact: narrow,
                        showWelcome: messages.isEmpty && !showRun,
                        welcome: LayoutBuilder(
                          builder: (context, box) => SingleChildScrollView(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight: box.maxHeight,
                              ),
                              child: Padding(
                                padding: EdgeInsets.fromLTRB(
                                  contentInset,
                                  28,
                                  contentInset,
                                  28,
                                ),
                                child: AssistantWelcome(
                                  copy: controller.copy,
                                  compact: box.maxHeight < 320,
                                  gameTitle:
                                      !useGlobalMode ||
                                          controller
                                              .globalUseCurrentGameKnowledge
                                      ? game.title
                                      : null,
                                  onPrompt: _usePrompt,
                                ),
                              ),
                            ),
                          ),
                        ),
                        messages: ListView.builder(
                          key: const ValueKey('assistant-message-list'),
                          controller: _scrollController,
                          padding: EdgeInsets.fromLTRB(
                            contentInset,
                            30,
                            contentInset,
                            16,
                          ),
                          itemCount:
                              messages.length +
                              (showRun && lastAssistantIndex < 0 ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == messages.length) {
                              return AiRunActivity(
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
                              );
                            }
                            return Column(
                              key: ValueKey(
                                '${selectedConversation.id}:${messages[index].id}',
                              ),
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
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
                                if (!(messages[index].role ==
                                        ChatRole.assistant &&
                                    messages[index].isStreaming &&
                                    messages[index].text.trim().isEmpty &&
                                    showRun))
                                  AssistantMessageEntrance(
                                    key: ValueKey(
                                      '${selectedConversation.id}:${messages[index].id}',
                                    ),
                                    animate: _knownMessages.add(
                                      messages[index].id,
                                    ),
                                    child: AnimatedContainer(
                                      duration: AppMotion.duration(context),
                                      decoration: BoxDecoration(
                                        color:
                                            _searchHighlight ==
                                                messages[index].id
                                            ? palette.primaryContainer
                                                  .withValues(alpha: .35)
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(16),
                                      ),
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
                                        speakTooltip:
                                            controller.copy.speakAgain,
                                        onCopy: () =>
                                            _copyAnswer(messages[index].text),
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
                                  ),
                              ],
                            );
                          },
                        ),
                      );
                    },
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 14,
                    child: Center(
                      child: AssistantScrollToBottomButton(
                        visible: _showJumpToBottom,
                        tooltip: _hasNewContent
                            ? '${controller.copy.desktopJumpToBottom} · ${controller.copy.aiNewMessages}'
                            : controller.copy.desktopJumpToBottom,
                        onPressed: _jumpToBottom,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ConversationSaveNotice(controller: controller),
            Padding(
              padding: EdgeInsets.fromLTRB(composerInset, 9, composerInset, 18),
              child: AssistantComposer(
                key: _composerKey,
                desktop: true,
                controller: controller,
                textController: _draftController,
                useGlobalMode: useGlobalMode,
                onSend: _send,
                onConfigureAi: widget.onConfigureAi,
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
    final conversation = controller.selectedConversation;
    final identity = controller.identityUserId;
    if (conversation == null ||
        !conversation.messages.any((message) => message.id == normalized)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          controller.selectedConversationId != conversation.id ||
          controller.identityUserId != identity) {
        return;
      }
      // A lazy list may not have mounted the target message yet.
      unawaited(_revealSearchResult(normalized, conversation.id, identity));
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  bool _contentScrollPending = false;
  void _handleContentChanged() {
    if (!mounted) return;
    if (_followNewMessages) {
      _scheduleContentScroll();
    } else if (!_hasNewContent) {
      setState(() {
        _showJumpToBottom = true;
        _hasNewContent = true;
      });
    }
  }

  void _scheduleContentScroll() {
    if (_contentScrollPending) return;
    _contentScrollPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _contentScrollPending = false;
      if (mounted && _followNewMessages) _scrollToBottom(animated: false);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _handleControllerChanged() {
    if (!mounted) return;
    final retainedIds = controller.conversationContextIds;
    _drafts.removeWhere((id, _) => !retainedIds.contains(id));
    _scrollOffsets.removeWhere((id, _) => !retainedIds.contains(id));
    final String? conversationId = controller.selectedConversationId;
    final bool contextChanged = conversationId != _lastConversationId;
    if (contextChanged) {
      _searchHighlightTimer?.cancel();
      _searchHighlight = null;
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
    if ((target - _scrollController.position.pixels).abs() < .5) return;
    final duration = AppMotion.duration(context, AppMotion.content);
    if (!animated || duration == Duration.zero) {
      _scrollController.jumpTo(target);
      return;
    }
    _scrollController.animateTo(
      target,
      duration: duration,
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

  Future<void> _findInConversation() async {
    final controller = this.controller;
    final id = controller.selectedConversationId;
    final identity = controller.identityUserId;
    final messages = controller.messagesForContext(
      useGlobalMode: controller.selectedConversationIsGlobal,
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
          controller.selectedConversationId != conversationId ||
          controller.identityUserId != identity) {
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
            controller.copy.localized(
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
    final controller = this.controller;
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
    final conversationId = controller.selectedConversationId;
    _draftController.clear();
    final accepted = await controller.sendPrompt(
      text,
      useGlobalMode: useGlobalMode,
    );
    if (!accepted &&
        mounted &&
        _draftController.text.isEmpty &&
        controller.selectedConversationId == conversationId) {
      _draftController.text = text;
      final error = controller.lastPromptSaveError;
      if (error != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error)));
      }
    }
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
