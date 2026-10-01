part of '../app_controller.dart';

extension AppConversationController on AppController {
  AiConversation _ensureConversationForContext({
    required bool useGlobalMode,
    String? gameId,
  }) {
    final GameInfo game = gameId == null
        ? selectedGame
        : _games.firstWhere(
            (GameInfo item) => item.id == gameId,
            orElse: () => selectedGame,
          );
    final String id = useGlobalMode
        ? _globalConversationKey
        : _conversationKeyForGameId(game.id);
    final String title = useGlobalMode
        ? copy.globalAiTitle
        : copy.gameAiTitle(game.title);
    final AiConversation? existing = _conversations[id];
    if (existing != null) {
      if (existing.title != title ||
          existing.scope !=
              (useGlobalMode
                  ? AiConversationScope.global
                  : AiConversationScope.game) ||
          existing.gameId != (useGlobalMode ? null : game.id)) {
        final AiConversation updated = existing.copyWith(
          title: title,
          scope: useGlobalMode
              ? AiConversationScope.global
              : AiConversationScope.game,
          gameId: useGlobalMode ? null : game.id,
        );
        _conversations[id] = updated;
        _queueConversationSave(conversationId: id);
        return updated;
      }
      return existing;
    }

    final DateTime now = DateTime.now();
    final AiConversation created = AiConversation(
      id: id,
      title: title,
      scope: useGlobalMode
          ? AiConversationScope.global
          : AiConversationScope.game,
      gameId: useGlobalMode ? null : game.id,
      createdAt: now,
      updatedAt: now,
      messages: const <ChatMessage>[],
    );
    _conversations[id] = created;
    _queueConversationSave(conversationId: id);
    return created;
  }

  void _refreshConversationMetadata() {
    for (final MapEntry<String, AiConversation> entry
        in _conversations.entries.toList()) {
      final AiConversation conversation = entry.value;
      if (conversation.id.startsWith('conversation:')) {
        if (!conversation.hasUserMessages) {
          conversation.title = copy.newConversation;
        }
        continue;
      }
      if (conversation.isGlobal) {
        if (conversation.title != copy.globalAiTitle) {
          _conversations[entry.key] = conversation.copyWith(
            title: copy.globalAiTitle,
            scope: AiConversationScope.global,
            gameId: null,
          );
        }
        continue;
      }
      final String? gameId = conversation.gameId;
      if (gameId == null) {
        continue;
      }
      final GameInfo? game = _games
          .where((GameInfo item) => item.id == gameId)
          .cast<GameInfo?>()
          .firstWhere((GameInfo? item) => item != null, orElse: () => null);
      if (game == null) {
        continue;
      }
      final String title = copy.gameAiTitle(game.title);
      if (conversation.title != title) {
        _conversations[entry.key] = conversation.copyWith(title: title);
      }
    }
  }

  void _handleListeningStopped() {
    if (_isListening || _speechLevel != 0) {
      _isListening = false;
      _speechLevel = 0;
      _notifyListeners();
    }
  }

  void _handleSpeechLevel(double level) {
    final double normalized = ((level + 2) / 12).clamp(0.05, 1.0).toDouble();
    if ((normalized - _speechLevel).abs() < 0.02) {
      return;
    }
    _speechLevel = normalized;
    _notifyListeners();
  }

  static const String _globalConversationKey = 'global';
  static const int _conversationStoreVersion = 4;
  static const int _maxMessagesPerConversation = 100;

  String _conversationKeyForContext({required bool useGlobalMode}) {
    return _conversationIdForContext(useGlobalMode: useGlobalMode);
  }

  _ChatGenerationState _generationStateForContext({
    required bool useGlobalMode,
  }) {
    final String key = _conversationKeyForContext(useGlobalMode: useGlobalMode);
    final _ChatGenerationState generation = _generationStates.putIfAbsent(
      key,
      _ChatGenerationState.new,
    );
    if (!generation.checkpointRestored) {
      final AiRunCheckpoint? checkpoint = _conversations[key]?.lastRun;
      if (checkpoint != null && checkpoint.events.isNotEmpty) {
        generation
          ..runId = checkpoint.runId
          ..runEvents.addAll(checkpoint.events)
          ..runStartedAt = checkpoint.startedAt
          ..runCompletedAt = checkpoint.completedAt
          ..runStatus = checkpoint.status
          ..syntheticRun = false;
      }
      generation.checkpointRestored = true;
    }
    return generation;
  }

  void _invalidateActiveRuns() {
    for (final _ChatGenerationState generation in _generationStates.values) {
      generation.contextEpoch += 1;
      if (!generation.isSending) continue;
      generation.wasStopped = true;
      final Completer<void>? abort = generation.abort;
      if (abort != null && !abort.isCompleted) abort.complete();
    }
  }

  void _invalidateGenerationForKey(String key) {
    if (key.isEmpty) return;
    final _ChatGenerationState? generation = _generationStates[key];
    if (generation == null) return;
    generation.contextEpoch += 1;
    if (!generation.isSending) return;
    generation.wasStopped = true;
    final Completer<void>? abort = generation.abort;
    if (abort != null && !abort.isCompleted) abort.complete();
  }

  List<ChatMessage> _messagesForCurrentContext() {
    return _messagesForContext(useGlobalMode: false);
  }

  String _conversationIdForContext({required bool useGlobalMode}) {
    final selected = _conversations[_selectedConversationId];
    if (selected != null &&
        selected.isGlobal == useGlobalMode &&
        (useGlobalMode || selected.gameId == selectedGame.id)) {
      return selected.id;
    }
    return useGlobalMode
        ? _globalConversationKey
        : _conversationKeyForGameId(selectedGame.id);
  }

  List<ChatMessage> _messagesForContext({required bool useGlobalMode}) {
    final String key = _conversationIdForContext(useGlobalMode: useGlobalMode);
    final AiConversation? existing = _conversations[key];
    if (existing != null) {
      return existing.messages;
    }
    return _ensureConversationForContext(useGlobalMode: useGlobalMode).messages;
  }

  String _conversationKeyForGameId(String gameId) => 'game:$gameId';

  bool _isConversationAvailable(AiConversation conversation) {
    return conversation.isGlobal ||
        (conversation.gameId != null &&
            _games.any((GameInfo game) => game.id == conversation.gameId));
  }

  void _trimConversationMessages(List<ChatMessage> messages) {
    if (messages.length <= _maxMessagesPerConversation) {
      return;
    }
    messages.removeRange(0, messages.length - _maxMessagesPerConversation);
  }

  void _queueConversationSave({String? conversationId}) {
    if (conversationId != null) {
      _touchConversation(conversationId);
    }
    _conversationSaveQueue = _conversationSaveQueue
        .then((_) async {
          await _persistConversations();
        })
        .catchError((Object error, StackTrace stackTrace) {
          debugPrint('[chat] persist conversations failed: $error');
          debugPrint('$stackTrace');
        });
  }

  void _touchConversation(String conversationId) {
    final AiConversation? conversation = _conversations[conversationId];
    if (conversation == null) return;
    // Keep the live message list intact while updating ordering metadata.
    // Replacing the model here would detach an in-flight streaming request
    // from the list that the UI and persistence queue are observing.
    conversation.updatedAt = DateTime.now();
    if (conversation.id.startsWith('conversation:')) {
      final question = conversation.messages
          .where((message) => message.role == ChatRole.user)
          .firstOrNull;
      if (question != null) {
        conversation.title = String.fromCharCodes(
          question.text.replaceAll(RegExp(r'\s+'), ' ').trim().runes.take(64),
        );
      } else {
        conversation.title = copy.newConversation;
      }
    }
  }

  void _queueSelectedConversationSave(String conversationId) {
    _selectedConversationSaveQueue = _selectedConversationSaveQueue
        .then(
          (_) => _preferencesService.saveSelectedConversationId(conversationId),
        )
        .catchError((Object error, StackTrace stackTrace) {
          debugPrint('[chat] persist selected conversation failed: $error');
          debugPrint('$stackTrace');
        });
  }

  Future<void> _persistSelectedConversationId() async {
    final String? id = _selectedConversationId;
    if (id == null || id.isEmpty) {
      await _preferencesService.clearSelectedConversationId();
      return;
    }
    await _preferencesService.saveSelectedConversationId(id);
  }

  Future<void> _restoreConversations() async {
    try {
      final stored = await _conversationStore.load();
      if (stored == null) {
        return;
      }
      final Map<String, dynamic> json =
          jsonDecode(stored) as Map<String, dynamic>;
      final Map<String, dynamic> conversations =
          json['conversations'] as Map<String, dynamic>? ?? <String, dynamic>{};

      _conversations.clear();
      bool removedLegacyGreetings = false;
      for (final MapEntry<String, dynamic> entry in conversations.entries) {
        final AiConversation? restored = _conversationFromStoredEntry(
          entry.key,
          entry.value,
        );
        if (restored?.discardLegacyBootstrapGreeting() == true) {
          removedLegacyGreetings = true;
        }
        if (restored != null && !restored.isUnstarted) {
          _conversations[entry.key] = restored;
        } else if (restored != null) {
          debugPrint(
            '[chat] skipped unused session during migration: ${restored.id}',
          );
        }
      }
      final String? persistedSelection =
          (json['selectedConversationId'] as String?)?.trim();
      if ((_selectedConversationId == null ||
              _selectedConversationId!.isEmpty) &&
          persistedSelection != null &&
          persistedSelection.isNotEmpty) {
        _selectedConversationId = persistedSelection;
      }
      debugPrint(
        '[chat] restored conversations: ${_conversations.keys.join(', ')}',
      );
      for (final _ChatGenerationState generation in _generationStates.values) {
        generation.checkpointRestored = false;
      }
      if (removedLegacyGreetings) await _persistConversations();
    } catch (error, stackTrace) {
      debugPrint('[chat] restore conversations failed: $error');
      debugPrint('$stackTrace');
    }
  }

  Future<void> _persistConversations({bool throwOnError = false}) async {
    try {
      final Map<String, dynamic> payload = <String, dynamic>{
        'version': _conversationStoreVersion,
        'savedAt': DateTime.now().toIso8601String(),
        'selectedConversationId': _selectedConversationId,
        'conversations': <String, dynamic>{
          for (final MapEntry<String, AiConversation> entry
              in _conversations.entries)
            entry.key: entry.value.toMap(),
        },
      };
      await _conversationStore.save(jsonEncode(payload));
    } catch (error, stackTrace) {
      debugPrint('[chat] persist conversations failed: $error');
      debugPrint('$stackTrace');
      if (throwOnError) rethrow;
    }
  }

  AiConversation? _conversationFromStoredEntry(String id, Object? raw) {
    if (raw is Map<String, dynamic>) {
      try {
        final AiConversation parsed = AiConversation.fromMap(raw);
        return parsed.id == id ? parsed : parsed.copyWith(id: id);
      } catch (error) {
        debugPrint('[chat] skipped malformed conversation $id: $error');
        return null;
      }
    }
    if (raw is! List<dynamic>) {
      return null;
    }
    final List<ChatMessage> messages = <ChatMessage>[];
    for (final Map<String, dynamic> messageMap
        in raw.whereType<Map<String, dynamic>>()) {
      try {
        messages.add(ChatMessage.fromMap(messageMap));
      } catch (error) {
        debugPrint('[chat] skipped malformed message in $id: $error');
      }
    }
    _trimConversationMessages(messages);
    // The v1 store represented conversations as bare message lists. Entries
    // that contain a user message are considered explicitly opened; a bare
    // greeting-only entry is a legacy bootstrap artifact and is discarded by
    // the restore migration.
    final DateTime now = DateTime.now();
    final DateTime updatedAt = messages.isEmpty ? now : messages.last.timestamp;
    final bool global = id == _globalConversationKey;
    final GameInfo? game = global
        ? null
        : _games
              .where(
                (GameInfo item) => _conversationKeyForGameId(item.id) == id,
              )
              .cast<GameInfo?>()
              .firstWhere((GameInfo? item) => item != null, orElse: () => null);
    return AiConversation(
      id: id,
      title: global
          ? copy.globalAiTitle
          : game == null
          ? '规则问答'
          : copy.gameAiTitle(game.title),
      scope: global ? AiConversationScope.global : AiConversationScope.game,
      gameId: game?.id ?? (global ? null : id.replaceFirst('game:', '')),
      createdAt: messages.isEmpty ? now : messages.first.timestamp,
      updatedAt: updatedAt,
      opened: messages.any(
        (ChatMessage message) => message.role == ChatRole.user,
      ),
      messages: messages,
    );
  }

  String? _resolveSelectedConversationId(String? preferredId) {
    final String? preferred = preferredId?.trim();
    if (preferred != null && _conversations.containsKey(preferred)) {
      final AiConversation conversation = _conversations[preferred]!;
      if (conversation.isGlobal ||
          (conversation.gameId != null &&
              _games.any((GameInfo game) => game.id == conversation.gameId))) {
        if (conversation.scope == AiConversationScope.game &&
            conversation.gameId != null) {
          _selectedGameId = conversation.gameId!;
        }
        return preferred;
      }
    }
    return null;
  }
}
