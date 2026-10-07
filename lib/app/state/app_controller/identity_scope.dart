part of '../app_controller.dart';

extension AppIdentityScopeController on AppController {
  void _trackProviderCleanup(Future<void> cleanup) {
    _providerCleanups.add(cleanup);
    cleanup.then<void>(
      (_) => _providerCleanups.remove(cleanup),
      onError: (Object _, StackTrace _) => _providerCleanups.remove(cleanup),
    );
  }

  Future<void> _drainActivityWrites() async {
    try {
      await _activitySaveQueue;
    } catch (_) {
      await _preferencesService.saveActivities(
        List<AppActivity>.of(_activities),
      );
      _activitySaveQueue = Future<void>.value();
    }
  }

  Future<void> _trackVoiceOperation(Future<void> Function() action) {
    final operation = action();
    _voiceOperations.add(operation);
    operation.then<void>(
      (_) => _voiceOperations.remove(operation),
      onError: (Object _, StackTrace _) => _voiceOperations.remove(operation),
    );
    return operation;
  }

  /// Call and await before exposing a new authenticated identity to the UI.
  /// Null selects the legacy guest namespace; no data is copied or merged.
  /// A failed drain keeps personal actions locked until a successful retry.
  Future<void> switchIdentityScope(String? userId) {
    PreferencesService.validateIdentityUserId(userId);
    if (!_switchingIdentityScope && userId == identityUserId) {
      return Future<void>.value();
    }
    _identityScopeRequests++;
    _switchingIdentityScope = true;
    _invalidateActiveRuns();
    _gameVotes.dispose();
    _favoriteStatistics?.dispose();
    final operation = _identityScopeQueue
        .catchError((Object _) {})
        .then((_) async {
          await _accountCloudWork;
          await _switchIdentityScopeNow(userId);
        })
        .whenComplete(() => _identityScopeRequests--);
    _identityScopeQueue = operation;
    return operation;
  }

  Future<void> _switchIdentityScopeNow(String? userId) async {
    _switchingIdentityScope = true;
    _identityScopeEpoch++;
    _pendingLibraryUpdate = null;
    _libraryUpdateError = null;
    _libraryUpdatePromptSeen = false;
    _invalidateAssetAccessStatus();
    _invalidateActiveRuns();
    // Invalidate finally blocks as well as event/delta callbacks.
    for (final state in _generationStates.values) {
      state.operationToken++;
    }
    _isListening = false;
    _speechLevel = 0;
    final oldVotes = _gameVotes;
    final voteRemoteProvider = _guestVoteTemplate?.remoteProvider;
    final voteScopeProvider = _guestVoteTemplate?.scopeProvider;
    oldVotes.dispose();
    _favoriteStatistics?.dispose();
    _nationalDayList?.dispose();
    _nationalDayList = null;
    _notifyListeners();
    await _initializationFuture?.timeout(const Duration(seconds: 15));

    // Immutable services pin writes (including service-owned DAV/list writes)
    // to the old account. Controller queues must drain before clearing maps.
    await Future.wait<void>([
      _conversationSaveQueue,
      ?_aiConfigSaveQueue,
      _selectedConversationSaveQueue,
      _drainActivityWrites(),
      _favoriteMutationQueue,
      _searchHistoryMutationQueue,
      _recentGamesMutationQueue,
      _dailyRecommendationSaveQueue,
      _preferencesService.drainPersonalWrites(),
      ..._voiceOperations,
      for (final state in _generationStates.values)
        if (state.finished != null) state.finished!.future,
      _speechService.cancelListening(),
      _ttsService.stop(),
    ]).timeout(const Duration(seconds: 15));
    // Cancellation starts before the forwarding stream finishes. Drain its
    // acknowledgement after every run's finished future has settled.
    await Future.wait<void>([
      ..._providerCleanups,
    ]).timeout(const Duration(seconds: 15));
    // A voice start/speak may have been pending when cancellation began.
    await Future.wait<void>([
      _speechService.cancelListening(),
      _ttsService.stop(),
    ]).timeout(const Duration(seconds: 8));
    // Retry a failed fire-and-forget conversation snapshot before leaving it.
    if (_conversationDirty) {
      await _persistConversations(
        throwOnError: true,
      ).timeout(const Duration(seconds: 8));
    }
    if (_selectedConversationDirty) {
      await _persistSelectedConversationId().timeout(
        const Duration(seconds: 8),
      );
    }
    if (_dailyRecommendationsDirty) {
      await _preferencesService
          .saveDailyRecommendations(_dailyRecommendationHistory)
          .timeout(const Duration(seconds: 8));
      _dailyRecommendationsDirty = false;
    }
    await _preferencesService.drainPersonalWrites().timeout(
      const Duration(seconds: 8),
    );
    // A queued favorite mutation or a getter may have constructed a service
    // while the old queues were draining. Dispose those before clearing state.
    _favoriteStatistics?.dispose();
    _nationalDayList?.dispose();
    _nationalDayList = null;

    _conversations.clear();
    _generationStates.clear();
    _runExpandedByContext.clear();
    _favoriteCreatedAtBySlug.clear();
    _committedFavoriteSlugs.clear();
    _favoriteRecordsLoaded = false;
    _activities = [];
    _searchHistory = [];
    _recentGameRecords = [];
    _dailyRecommendationHistory = [];
    _searchHistoryStateVersion++;
    _recentGamesStateVersion++;
    _selectedConversationId = null;
    _voiceReplyEnabled = false;
    _assistantMode = AssistantMode.textAndDictation;
    _gameAnswerMode = AiAnswerMode.knowledgeOnly;
    _globalAnswerMode = AiAnswerMode.knowledgeThenDirect;
    _globalUseCurrentGameKnowledge = false;
    _selectedGameId = _games.firstOrNull?.id ?? 'puerto-rico';
    _favoriteStatistics = null;
    _nationalDayList = null;
    _preferencesService = _basePreferencesService.forIdentityScope(userId);
    _conversationStore = _baseConversationStore.forIdentityScope(userId);
    _gameVotes = GameVoteService(
      preferences: _preferencesService,
      // The anonymous DAV protocol owns one device ballot. Never use it for
      // accounts, even if a custom provider was injected by the app.
      remoteProvider: userId == null ? voteRemoteProvider : null,
      scopeProvider: userId == null ? voteScopeProvider : null,
    );
    _notifyListeners();
    await _reloadIdentityPersonalState();
    _switchingIdentityScope = _identityScopeRequests > 1;
    _notifyListeners();
  }

  Future<void> _reloadIdentityPersonalState() async {
    _voiceReplyEnabled = await _preferencesService
        .loadVoiceReplyEnabled()
        .timeout(const Duration(seconds: 8));
    if (!voiceReplyAvailable) _voiceReplyEnabled = false;
    final mode = await _preferencesService.loadAssistantMode().timeout(
      const Duration(seconds: 8),
    );
    _assistantMode =
        mode == AssistantMode.realtimeVoice && !realtimeVoiceAvailable
        ? AssistantMode.textAndDictation
        : mode;
    _gameAnswerMode = await _preferencesService.loadGameAnswerMode().timeout(
      const Duration(seconds: 8),
    );
    _globalAnswerMode = await _preferencesService
        .loadGlobalAnswerMode()
        .timeout(const Duration(seconds: 8));
    _globalUseCurrentGameKnowledge = await _preferencesService
        .loadGlobalUseCurrentGameKnowledge()
        .timeout(const Duration(seconds: 8));
    _selectedConversationId = await _preferencesService
        .loadSelectedConversationId()
        .timeout(const Duration(seconds: 8));
    _activities = latestActivitiesByKind(
      await _preferencesService.loadActivities().timeout(
        const Duration(seconds: 8),
      ),
      maxEntries: AppController._maxActivities,
    );
    await _ensureFavoriteRecords().timeout(const Duration(seconds: 8));
    _searchHistory = await _preferencesService.loadSearchHistory().timeout(
      const Duration(seconds: 8),
    );
    _recentGameRecords = await _preferencesService.loadRecentGames().timeout(
      const Duration(seconds: 8),
    );
    _dailyRecommendationHistory = await _preferencesService
        .loadDailyRecommendations()
        .timeout(const Duration(seconds: 8));
    await _restoreConversations(throwOnError: true);
    _refreshConversationMetadata();
    _selectedConversationId = _resolveSelectedConversationId(
      _selectedConversationId,
    );
  }

  String _providerConversationId(String localId) {
    final scope = PreferencesService.identityStorageId(identityUserId);
    // ResponsesRulesWorkflow._scopeKey honors custom IDs only with this prefix;
    // it scopes session/context/compaction/telemetry identifiers together.
    return scope == null ? localId : 'conversation:personal_v1:$scope:$localId';
  }
}

/// Finish consumption independently from provider cleanup. A subscription may
/// return a cached cancellation future from outside the current zone; returning
/// it from onCancel can hold stream completion outside a widget's fake clock.
/// Account transitions drain the provider cleanup separately.
Stream<BoardGameAiStreamEvent> _abortableAiStream(
  Stream<BoardGameAiStreamEvent> source,
  Future<void> abort, {
  required void Function(Future<void> cleanup) onCancellation,
}) {
  late StreamSubscription<BoardGameAiStreamEvent> subscription;
  final controller = StreamController<BoardGameAiStreamEvent>();
  bool sourceDone = false;
  bool cancellationStarted = false;
  void cancelSource() {
    if (sourceDone || cancellationStarted) return;
    cancellationStarted = true;
    final cleanup = subscription.cancel();
    onCancellation(cleanup);
    cleanup.catchError((Object error) {
      debugPrint('[chat] provider stream cleanup failed: $error');
    });
  }

  controller.onListen = () {
    subscription = source.listen(
      controller.add,
      onError: controller.addError,
      onDone: () {
        sourceDone = true;
        unawaited(controller.close());
      },
    );
    unawaited(
      abort.then((_) {
        if (controller.isClosed) return;
        cancelSource();
        unawaited(controller.close());
      }),
    );
  };
  // Do not make forwarding stream completion wait for provider cleanup.
  controller.onCancel = cancelSource;
  return controller.stream;
}
