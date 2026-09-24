part of '../app_controller.dart';

extension AppAssistantController on AppController {
  void selectGame(String gameId) {
    final bool gameChanged = _selectedGameId != gameId;
    final String previousConversationId = _selectedConversationId ?? '';
    if (gameChanged) _invalidateGenerationForKey(previousConversationId);
    _selectedGameId = gameId;
    _selectConversationInternal(_conversationKeyForGameId(gameId));
    if (gameChanged || previousConversationId != _selectedConversationId) {
      _notifyListeners();
    }
  }

  /// Opens the game-scoped assistant for [gameId], creating its session only
  /// when the user explicitly enters that assistant context.
  bool openGameAssistant(String gameId, {String? greeting}) {
    final GameInfo? game = _games
        .where((GameInfo item) => item.id == gameId)
        .cast<GameInfo?>()
        .firstWhere((GameInfo? item) => item != null, orElse: () => null);
    if (game == null) {
      return false;
    }

    final String previousConversationId = _selectedConversationId ?? '';
    final String nextConversationId = _conversationKeyForGameId(game.id);
    if (previousConversationId != nextConversationId) {
      _invalidateGenerationForKey(previousConversationId);
    }
    _selectedGameId = game.id;
    final AiConversation conversation = _ensureConversationForContext(
      useGlobalMode: false,
      gameId: game.id,
      greeting: greeting,
    );
    _selectConversationInternal(conversation.id);
    _notifyListeners();
    return true;
  }

  /// Opens the cross-game assistant, creating its session on first entry.
  void openGlobalAssistant({String? greeting}) {
    final String previousConversationId = _selectedConversationId ?? '';
    if (previousConversationId !=
        AppConversationController._globalConversationKey) {
      _invalidateGenerationForKey(previousConversationId);
    }
    final AiConversation conversation = _ensureConversationForContext(
      useGlobalMode: true,
      greeting: greeting,
    );
    _selectConversationInternal(conversation.id);
    _notifyListeners();
  }

  /// Selects a persisted assistant conversation by its stable ID.
  ///
  /// Game sessions use `game:<gameId>` and the all-knowledge session uses
  /// `global`. Unknown IDs are ignored so stale preference data cannot point
  /// the UI at a conversation that no longer exists.
  void selectConversation(String conversationId) {
    final String normalized = conversationId.trim();
    if (!_conversations.containsKey(normalized) ||
        !_isConversationAvailable(_conversations[normalized]!)) {
      return;
    }
    final AiConversation conversation = _conversations[normalized]!;
    if (_selectedConversationId != normalized) {
      _invalidateGenerationForKey(_selectedConversationId ?? '');
    }
    if (conversation.scope == AiConversationScope.game &&
        conversation.gameId != null &&
        _games.any((GameInfo game) => game.id == conversation.gameId)) {
      _selectedGameId = conversation.gameId!;
    }
    if (_selectedConversationId == normalized) {
      return;
    }
    _selectedConversationId = normalized;
    _queueSelectedConversationSave(normalized);
    _notifyListeners();
  }

  void _selectConversationInternal(String conversationId) {
    if (!_conversations.containsKey(conversationId) ||
        !_isConversationAvailable(_conversations[conversationId]!) ||
        _selectedConversationId == conversationId) {
      return;
    }
    _selectedConversationId = conversationId;
    _queueSelectedConversationSave(conversationId);
  }

  Future<void> setVoiceReplyEnabled(bool enabled) async {
    if (!voiceReplyAvailable) {
      if (_voiceReplyEnabled) {
        _voiceReplyEnabled = false;
        _notifyListeners();
      }
      return;
    }
    _voiceReplyEnabled = enabled;
    await _preferencesService.saveVoiceReplyEnabled(enabled);
    if (!enabled) {
      await _ttsService.stop();
    }
    _notifyListeners();
  }

  Future<bool> setAssistantMode(AssistantMode mode) async {
    if (_assistantMode == mode) {
      return true;
    }
    if (mode == AssistantMode.realtimeVoice && !realtimeVoiceAvailable) {
      return false;
    }
    if (_isListening) {
      await stopListening();
    }
    await stopSpeaking();
    _assistantMode = mode;
    await _preferencesService.saveAssistantMode(mode);
    _notifyListeners();
    return true;
  }

  Future<void> setAllowSmartSupplement(
    bool enabled, {
    required bool useGlobalMode,
  }) async {
    final AiAnswerMode next = enabled
        ? AiAnswerMode.knowledgeThenDirect
        : AiAnswerMode.knowledgeOnly;
    if (useGlobalMode) {
      if (_globalAnswerMode == next) {
        return;
      }
      _globalAnswerMode = next;
      await _preferencesService.saveGlobalAnswerMode(next);
    } else {
      if (_gameAnswerMode == next) {
        return;
      }
      _gameAnswerMode = next;
      await _preferencesService.saveGameAnswerMode(next);
    }
    debugPrint(
      '[chat] answer mode updated: global=$useGlobalMode mode=${next.code}',
    );
    _notifyListeners();
  }

  Future<void> setGlobalUseCurrentGameKnowledge(bool enabled) async {
    if (_globalUseCurrentGameKnowledge == enabled) return;
    _globalUseCurrentGameKnowledge = enabled;
    await _preferencesService.saveGlobalUseCurrentGameKnowledge(enabled);
    _notifyListeners();
  }

  Future<void> speakMessage(String text) async {
    if (!voiceReplyAvailable) {
      return;
    }
    await _ttsService.setLanguage(_language);
    await _ttsService.speak(text);
  }

  Future<void> stopSpeaking() async {
    await _ttsService.stop();
  }

  Future<void> startListening({
    required ValueChanged<String> onRecognizedText,
  }) async {
    if (_isListening) {
      return;
    }

    if (!_speechAvailable) {
      _speechAvailable = await _speechService.reinitialize(
        onListeningStopped: _handleListeningStopped,
      );
      if (!_speechAvailable) {
        _notifyListeners();
        return;
      }
    }

    _isListening = true;
    _speechLevel = 0;
    _notifyListeners();

    final bool started = await _speechService.startListening(
      language: _language,
      onResult: onRecognizedText,
      onListeningStopped: _handleListeningStopped,
      onSoundLevel: _handleSpeechLevel,
    );
    if (!started) {
      _isListening = false;
      _speechLevel = 0;
      _notifyListeners();
    }
  }

  Future<void> stopListening() async {
    await _speechService.stopListening();
    _handleListeningStopped();
  }

  Future<void> stopGenerating({bool useGlobalMode = false}) async {
    final _ChatGenerationState generation = _generationStateForContext(
      useGlobalMode: useGlobalMode,
    );
    if (!generation.isSending) {
      return;
    }
    generation.wasStopped = true;
    final Completer<void>? abort = generation.abort;
    if (abort != null && !abort.isCompleted) {
      abort.complete();
    }
  }

  Future<void> clearConversation() async {
    await resetConversation();
  }

  Future<void> clearConversationForContext({
    required bool useGlobalMode,
  }) async {
    await resetConversation(useGlobalMode: useGlobalMode);
  }

  Future<void> resetConversation({
    String? greeting,
    bool useGlobalMode = false,
  }) async {
    final _ChatGenerationState generation = _generationStateForContext(
      useGlobalMode: useGlobalMode,
    );
    generation.contextEpoch += 1;
    await stopGenerating(useGlobalMode: useGlobalMode);
    final String conversationId = _conversationIdForContext(
      useGlobalMode: useGlobalMode,
    );
    final List<ChatMessage> messages = _messagesForContext(
      useGlobalMode: useGlobalMode,
    );
    final GameInfo game = selectedGame;
    messages
      ..clear()
      ..add(
        ChatMessage(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          role: ChatRole.assistant,
          text:
              greeting ??
              copy.assistantGreetingFor(
                useGlobalMode ? copy.globalAiTitle : game.title,
                useGlobalMode
                    ? copy.allKnowledgeGreeting
                    : game.assistantIntro.isNotEmpty
                    ? game.assistantIntro
                    : game.summary,
              ),
          timestamp: DateTime.now(),
        ),
      );
    final AiConversation? existingConversation = _conversations[conversationId];
    if (existingConversation != null && existingConversation.lastRun != null) {
      existingConversation.lastRun = null;
    }
    await _ttsService.stop();
    _trimConversationMessages(messages);
    _queueConversationSave(conversationId: conversationId);
    _notifyListeners();
  }

  Future<void> sendPrompt(String prompt, {bool useGlobalMode = false}) async {
    final trimmed = prompt.trim();
    final _ChatGenerationState generation = _generationStateForContext(
      useGlobalMode: useGlobalMode,
    );
    if (trimmed.isEmpty || generation.isSending) {
      return;
    }
    if (_aiApiConfig.model.trim().isEmpty) {
      _aiConnectivityStatus = ConnectivityStatus(
        state: ConnectivityState.failure,
        message: copy.aiApiModelRequired,
        checkedAt: DateTime.now(),
      );
      _recordActivity(
        kind: AppActivityKind.aiFailed,
        title: copy.activityAiFailedTitle,
        message: copy.aiApiModelRequired,
        conversationId: _conversationIdForContext(useGlobalMode: useGlobalMode),
      );
      return;
    }
    final List<ChatMessage> messages = _messagesForContext(
      useGlobalMode: useGlobalMode,
    );
    final String conversationId = _conversationIdForContext(
      useGlobalMode: useGlobalMode,
    );

    final userMessage = ChatMessage(
      id: '${DateTime.now().microsecondsSinceEpoch}-user',
      role: ChatRole.user,
      text: trimmed,
      timestamp: DateTime.now(),
    );

    messages.add(userMessage);
    _trimConversationMessages(messages);
    _queueConversationSave(conversationId: conversationId);
    generation.isSending = true;
    generation.wasStopped = false;
    final int operationToken = ++generation.operationToken;
    final int contextEpoch = generation.contextEpoch;
    generation
      ..useGlobalMode = useGlobalMode
      ..contextKey = conversationId;
    _startRunPresentation(generation);
    final Completer<void> generationAbort = Completer<void>();
    generation.abort = generationAbort;
    final String draftId = '${DateTime.now().microsecondsSinceEpoch}-assistant';
    final ChatMessage draftMessage = ChatMessage(
      id: draftId,
      role: ChatRole.assistant,
      text: '',
      timestamp: DateTime.now(),
      state: ChatMessageState.streaming,
    );
    messages.add(draftMessage);
    _notifyListeners();
    final _StreamTextBatcher deltaBatcher = _StreamTextBatcher((String delta) {
      final ChatMessage? current = _messageById(messages, draftId);
      if (current == null) return;
      _replaceMessage(
        messages,
        current.copyWith(text: '${current.text}$delta'),
      );
      _notifyListeners();
    });

    final GameInfo game = featuredGame;
    final AiAnswerMode answerMode = chatAnswerMode(
      useGlobalMode: useGlobalMode,
    );
    debugPrint(
      '[chat] send prompt game=${game.slug} global=$useGlobalMode mode=${answerMode.code}',
    );

    try {
      BoardGameAiAnswer? finalAnswer;
      BoardGameAiStreamEvent? terminalEvent;
      AiRunResult? terminalRunResult;
      await for (final BoardGameAiStreamEvent event in _aiService.streamReply(
        prompt: trimmed,
        language: _language,
        game: game,
        answerMode: answerMode,
        useGlobalMode: useGlobalMode,
        config: _aiApiConfig,
        assetSourceConfigs: _assetSourceConfigs,
        remoteAssetService: _remoteAssetService,
        conversationHistory: List<ChatMessage>.unmodifiable(
          messages.where((ChatMessage item) => item.id != draftId),
        ),
        useCurrentGameKnowledge: useGlobalMode
            ? _globalUseCurrentGameKnowledge
            : true,
        abortTrigger: generationAbort.future,
      )) {
        if (generation.wasStopped ||
            generation.operationToken != operationToken ||
            generation.contextEpoch != contextEpoch) {
          break;
        }
        if (event.runEvent != null) {
          _recordRunEvent(generation, event.runEvent!);
        } else {
          _recordSyntheticProgress(generation, event);
        }
        if (event.isDone || event.isFailure) {
          terminalEvent = event;
        }
        if (event.runResult != null) {
          terminalRunResult = event.runResult;
        }
        if (event.delta.isNotEmpty) {
          // Coalesce deltas into one UI update per frame-sized window. The
          // activity timeline still receives each normalized event, while the
          // markdown message avoids rebuilding once per token.
          deltaBatcher.add(event.delta);
        } else {
          // Every non-text event can change the visible activity row (for
          // example a citation or retry has no textual status).
          _notifyListeners();
        }
        if (event.answer != null) {
          deltaBatcher.flush();
          finalAnswer = event.answer;
          _completeSyntheticAnswerStage(generation);
        }
      }

      if (generation.operationToken != operationToken ||
          generation.contextEpoch != contextEpoch) {
        return;
      }

      deltaBatcher.flush();
      final ChatMessage? currentDraft = _messageById(messages, draftId);
      if (generation.wasStopped) {
        _finishRunPresentation(generation, AiRunStatus.cancelled);
        if (currentDraft != null && currentDraft.text.trim().isNotEmpty) {
          _replaceMessage(
            messages,
            currentDraft.copyWith(
              state: ChatMessageState.complete,
              source: finalAnswer?.source ?? AnswerSource.generalAdvice,
              evidence: finalAnswer?.evidence ?? const <EvidenceChunk>[],
              citations: finalAnswer?.citations ?? const <RuleCitation>[],
            ),
          );
        } else {
          messages.removeWhere((ChatMessage item) => item.id == draftId);
        }
        _trimConversationMessages(messages);
        _queueConversationSave(conversationId: conversationId);
      } else if (finalAnswer != null) {
        _finishRunPresentation(generation, AiRunStatus.completed);
        final BoardGameAiAnswer answer = finalAnswer;
        final ChatMessage nextMessage = (currentDraft ?? draftMessage).copyWith(
          text: answer.text,
          source: answer.source,
          evidence: answer.evidence,
          citations: answer.citations,
          state: ChatMessageState.complete,
          canRetry: false,
          retryPrompt: null,
        );
        _replaceMessage(messages, nextMessage);
        _trimConversationMessages(messages);
        _queueConversationSave(conversationId: conversationId);
        _recordActivity(
          kind: AppActivityKind.aiCompleted,
          title: copy.activityAiCompletedTitle,
          message: copy.activityAiCompletedMessage(game.title),
          conversationId: conversationId,
          messageId: draftId,
        );
        if (_voiceReplyEnabled) {
          await speakMessage(answer.text);
        }
      } else if (terminalEvent != null) {
        _finishRunPresentation(
          generation,
          _runStatusFromEvent(terminalEvent.runEvent) ?? AiRunStatus.failed,
        );
        final AiRunEvent? runEvent = terminalEvent.runEvent;
        debugPrint(
          '[chat] stream ended without answer type=${runEvent?.type.name} '
          'stage=${runEvent?.stageId} code=${runEvent?.errorCode} '
          'message=${terminalEvent.errorMessage ?? runEvent?.errorMessage}',
        );
        final ChatMessage? draft = _messageById(messages, draftId);
        final String partialText = draft?.text.trim() ?? '';
        final String terminalNotice = switch (runEvent?.type) {
          AiRunEventType.incomplete => copy.aiReplyIncomplete,
          AiRunEventType.cancelled => copy.aiReplyIncomplete,
          _ => copy.aiReplyFailed,
        };
        final String reason = _streamFailureReason(
          terminalEvent,
          fallback: runEvent?.detail,
        );
        final String failureNotice = _failureNotice(
          terminalNotice,
          reason: reason,
          attempts: _runAttemptCount(generation),
          progressLines: _confirmedProgressLines(
            generation,
            runResult: terminalRunResult,
          ),
          partialOutputRetained: partialText.isNotEmpty,
        );
        final String text = partialText.isEmpty
            ? failureNotice
            : '${draft!.text}\n\n$failureNotice';
        _replaceMessage(
          messages,
          (draft ?? draftMessage).copyWith(
            text: text,
            state: ChatMessageState.failed,
            canRetry: true,
            retryPrompt: trimmed,
          ),
        );
        _recordActivity(
          kind: AppActivityKind.aiFailed,
          title: copy.activityAiFailedTitle,
          message: reason,
          conversationId: conversationId,
          messageId: draftId,
        );
        _trimConversationMessages(messages);
        _queueConversationSave(conversationId: conversationId);
      } else {
        _finishRunPresentation(generation, AiRunStatus.incomplete);
        throw StateError('The AI stream ended without an answer.');
      }
    } catch (error, stackTrace) {
      deltaBatcher.flush();
      debugPrint('[chat] sendPrompt failed: $error');
      debugPrint('$stackTrace');
      if (generation.operationToken != operationToken ||
          generation.contextEpoch != contextEpoch) {
        return;
      }
      if (generation.wasStopped) {
        _finishRunPresentation(generation, AiRunStatus.cancelled);
        final ChatMessage? currentDraft = _messageById(messages, draftId);
        if (currentDraft != null && currentDraft.text.trim().isNotEmpty) {
          _replaceMessage(
            messages,
            currentDraft.copyWith(
              state: ChatMessageState.complete,
              source: AnswerSource.generalAdvice,
            ),
          );
        } else {
          messages.removeWhere((ChatMessage item) => item.id == draftId);
        }
      } else {
        _finishRunPresentation(generation, AiRunStatus.failed);
        final ChatMessage? currentDraft = _messageById(messages, draftId);
        final String partialText = currentDraft?.text.trim() ?? '';
        final String failureNotice = _failureNotice(
          copy.aiReplyFailed,
          reason: _safeStatusError(error),
          attempts: _runAttemptCount(generation),
          progressLines: _confirmedProgressLines(generation),
          partialOutputRetained: partialText.isNotEmpty,
        );
        final String text = partialText.isEmpty
            ? failureNotice
            : '${currentDraft!.text}\n\n$failureNotice';
        _replaceMessage(
          messages,
          (currentDraft ?? draftMessage).copyWith(
            text: text,
            state: ChatMessageState.failed,
            canRetry: true,
            retryPrompt: trimmed,
          ),
        );
        _recordActivity(
          kind: AppActivityKind.aiFailed,
          title: copy.activityAiFailedTitle,
          message: _safeStatusError(error),
          conversationId: conversationId,
          messageId: draftId,
        );
      }
      _trimConversationMessages(messages);
      _queueConversationSave(conversationId: conversationId);
    } finally {
      deltaBatcher.dispose();
      if (generation.operationToken == operationToken) {
        generation.abort = null;
        generation.isSending = false;
        _notifyListeners();
      }
    }
  }

  Future<void> retryMessage(
    ChatMessage message, {
    required bool useGlobalMode,
  }) async {
    final String? prompt = message.retryPrompt;
    if (!message.canRetry ||
        prompt == null ||
        prompt.trim().isEmpty ||
        isSendingForContext(useGlobalMode: useGlobalMode)) {
      return;
    }
    final List<ChatMessage> messages = _messagesForContext(
      useGlobalMode: useGlobalMode,
    );
    final String conversationId = _conversationIdForContext(
      useGlobalMode: useGlobalMode,
    );
    final int failedIndex = messages.indexWhere(
      (ChatMessage item) => item.id == message.id,
    );
    if (failedIndex >= 0) {
      if (failedIndex > 0 &&
          messages[failedIndex - 1].role == ChatRole.user &&
          messages[failedIndex - 1].text.trim() == prompt.trim()) {
        messages.removeRange(failedIndex - 1, failedIndex + 1);
      } else {
        messages.removeAt(failedIndex);
      }
      _queueConversationSave(conversationId: conversationId);
      _notifyListeners();
    }
    await sendPrompt(prompt, useGlobalMode: useGlobalMode);
  }

  ChatMessage? _messageById(List<ChatMessage> messages, String id) {
    for (final ChatMessage message in messages) {
      if (message.id == id) return message;
    }
    return null;
  }

  void _replaceMessage(List<ChatMessage> messages, ChatMessage replacement) {
    final int index = messages.indexWhere(
      (ChatMessage message) => message.id == replacement.id,
    );
    if (index >= 0) {
      messages[index] = replacement;
    } else {
      messages.add(replacement);
    }
  }
}
