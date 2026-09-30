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
  final Map<String, GlobalKey> _messageKeys = <String, GlobalKey>{};
  Timer? _messageTimesTimer;

  AppController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _draftController = TextEditingController();
    _scrollController = ScrollController()..addListener(_handleScrollChanged);
    _lastConversationId = controller.selectedConversationId;
    controller.addListener(_handleControllerChanged);
    _scheduleInitialScrollToBottom();
  }

  @override
  void dispose() {
    controller.removeListener(_handleControllerChanged);
    _scrollController.removeListener(_handleScrollChanged);
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
    final String assistantTitle = useGlobalMode
        ? controller.copy.globalAiTitle
        : '${game.title}助手';
    final String messageSummary = controller.copy.desktopAssistantMessages(
      messages.length,
    );
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool narrow = constraints.maxWidth < 760;
        final double contentInset = math.max(
          17,
          (constraints.maxWidth - 780) / 2,
        );
        // The message column stays readable at 780px, while the composer
        // follows the wider desktop reference layout. Keeping its inset
        // independent prevents a wide window from squeezing the input row
        // into the message column.
        final double composerInset = math.max(
          17,
          (constraints.maxWidth - 1360) / 2,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Container(
              constraints: const BoxConstraints(minHeight: 79),
              padding: EdgeInsets.fromLTRB(
                narrow ? 17 : 28,
                16,
                narrow ? 17 : 28,
                16,
              ),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: palette.outline)),
              ),
              child: Row(
                children: <Widget>[
                  const _AssistantAppMark(),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          assistantTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: <Widget>[
                            _AssistantStatusDot(color: palette.success),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                messageSummary,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: palette.textSecondary),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (!narrow &&
                      (!useGlobalMode ||
                          controller.globalUseCurrentGameKnowledge)) ...[
                    _AssistantStatusLabel(label: game.title, palette: palette),
                    const SizedBox(width: 14),
                    _AssistantStatusLabel(
                      label: controller.copy.desktopRulebookCached,
                      palette: palette,
                    ),
                    const SizedBox(width: 7),
                  ],
                  if (narrow)
                    IconButton(
                      tooltip: controller.copy.desktopSessionTitle,
                      onPressed: () => _showAssistantSheet(
                        title: controller.copy.desktopSessionTitle,
                        child: _DesktopAssistantSessions(
                          controller: controller,
                          embedded: false,
                        ),
                      ),
                      style: _desktopIconButtonStyle(palette),
                      icon: const Icon(Icons.forum_outlined),
                    ),
                  if (narrow)
                    IconButton(
                      tooltip: controller.copy.desktopContextTitle,
                      onPressed: () => _showAssistantSheet(
                        title: controller.copy.desktopContextTitle,
                        child: _DesktopContextPanel(
                          controller: controller,
                          useGlobalMode: useGlobalMode,
                        ),
                      ),
                      style: _desktopIconButtonStyle(palette),
                      icon: const Icon(Icons.tune_rounded),
                    ),
                  IconButton(
                    tooltip: controller.copy.desktopClearConversation,
                    onPressed: () => controller.clearConversationForContext(
                      useGlobalMode: useGlobalMode,
                    ),
                    style: _desktopIconButtonStyle(palette),
                    icon: const Icon(Icons.delete_sweep_outlined),
                  ),
                  PopupMenuButton<String>(
                    tooltip: controller.copy.desktopMore,
                    onSelected: (String value) {
                      if (value == 'context') {
                        _showAssistantSheet(
                          title: controller.copy.desktopContextTitle,
                          child: _DesktopContextPanel(
                            controller: controller,
                            useGlobalMode: useGlobalMode,
                          ),
                        );
                      }
                    },
                    itemBuilder: (BuildContext context) =>
                        <PopupMenuEntry<String>>[
                          PopupMenuItem<String>(
                            value: 'context',
                            child: Text(controller.copy.desktopContextTitle),
                          ),
                        ],
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 34,
                      height: 34,
                    ),
                    iconSize: 18,
                    icon: const Icon(Icons.more_horiz_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                children: <Widget>[
                  ListView(
                    controller: _scrollController,
                    padding: EdgeInsets.fromLTRB(
                      contentInset,
                      30,
                      contentInset,
                      16,
                    ),
                    children: <Widget>[
                      if (messages.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            controller.copy.messageHint,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: palette.textSecondary),
                          ),
                        ),
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
                            initialExpanded: controller.aiRunExpandedForContext(
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
                          MessageBubble(
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
                            onSpeak: messages[index].role == ChatRole.assistant
                                ? () => controller.speakMessage(
                                    messages[index].text,
                                  )
                                : () {},
                            speakTooltip: controller.copy.speakAgain,
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
              child: _DesktopComposer(
                controller: controller,
                draftController: _draftController,
                useGlobalMode: useGlobalMode,
                onSend: _send,
                onOpenContext: () => _showAssistantSheet(
                  title: controller.copy.desktopContextTitle,
                  child: _DesktopContextPanel(
                    controller: controller,
                    useGlobalMode: useGlobalMode,
                  ),
                ),
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
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        alignment: 0.2,
      );
    });
  }

  void _handleControllerChanged() {
    if (!mounted) return;
    final String? conversationId = controller.selectedConversationId;
    final bool contextChanged = conversationId != _lastConversationId;
    if (contextChanged) {
      _saveScrollPosition();
      _lastConversationId = conversationId;
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
      duration: const Duration(milliseconds: 220),
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
      _scrollToBottom(animated: false);
      _followNewMessages = true;
      _showJumpToBottom = false;
      _hasNewContent = false;
    });
  }

  Future<void> _showAssistantSheet({
    required String title,
    required Widget child,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext context) => SafeArea(
        child: SizedBox(
          height: math.min(MediaQuery.sizeOf(context).height * 0.72, 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
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
