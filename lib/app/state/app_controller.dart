import 'dart:collection';
import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:app_ai_client/app_ai_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import '../../features/assistant/models/ai_api_config.dart';
import '../../features/assistant/models/ai_model_policy.dart';
import '../../features/assistant/models/ai_answer_mode.dart';
import '../../features/assistant/models/ai_run.dart';
import '../../features/assistant/models/answer_source.dart';
import '../../features/assistant/models/assistant_mode.dart';
import '../../features/library/models/asset_source_config.dart';
import '../../core/localization/app_language.dart';
import '../../core/models/app_activity.dart';
import '../../features/assistant/models/board_game_ai_answer.dart';
import '../../features/assistant/models/chat_message.dart';
import '../../features/assistant/models/ai_conversation.dart';
import '../../features/library/models/cached_asset.dart';
import '../../core/models/connectivity_status.dart';
import '../../core/theme/color_scheme_option.dart';
import '../../features/library/models/desktop_library_resource.dart';
import '../../features/games/models/daily_recommendation_record.dart';
import '../../features/games/models/favorite_game_record.dart';
import '../../features/games/models/game_info.dart';
import '../../features/games/models/game_catalog_manifest.dart';
import '../../features/library/models/game_resource.dart';
import '../../features/library/models/remote_library_update.dart';
import '../../features/library/models/remote_asset_file.dart';
import '../../features/games/models/recent_game_record.dart';
import '../../features/library/models/resolved_document.dart';
import '../../features/games/models/search_history_record.dart';
import '../../features/assistant/models/evidence_chunk.dart';
import '../../features/assistant/models/rule_citation.dart';
import '../../features/assistant/services/ai_service.dart';
import '../../features/settings/services/preferences_service.dart';
import '../../features/games/services/daily_game_recommender.dart';
import '../../features/games/services/game_manifest_service.dart';
import '../../features/library/services/remote_asset_service.dart';
import '../../features/assistant/services/speech_service.dart';
import '../../features/assistant/services/tts_service.dart';
import '../../features/assistant/services/realtime_voice_service.dart';
import '../../features/assistant/services/ai_error_presenter.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/palette_registry.dart';
import '../../core/localization/app_copy.dart';

part 'app_controller/collections.dart';
part 'app_controller/ai_configuration.dart';
part 'app_controller/assistant.dart';
part 'app_controller/assistant_run.dart';
part 'app_controller/conversations.dart';
part 'app_controller/service_status.dart';
part 'app_controller/library.dart';
part 'app_controller/library_updates.dart';
part 'app_controller/documents.dart';

enum AiModelLoadState { idle, loading, success, empty, failure }

enum AiServiceCheckStage { models, chatProbe }

enum LibraryLoadState { idle, loading, success, empty, failure }

/// Result of reading the remote library manifests.
///
/// [warning] is non-fatal: a partial index can still be shown while the UI
/// exposes that one or more game manifests were unavailable.
class _RemoteLibraryIndexResult {
  const _RemoteLibraryIndexResult({
    required this.resources,
    this.warning,
    this.failedSlugs = const <String>{},
  });

  final List<DesktopLibraryResource> resources;
  final String? warning;
  final Set<String> failedSlugs;
}

class AppController extends ChangeNotifier {
  AppController({
    required PreferencesService preferencesService,
    required AiService aiService,
    required GameManifestService gameManifestService,
    required RemoteAssetService remoteAssetService,
    required SpeechService speechService,
    required TtsService ttsService,
    RealtimeVoiceService? realtimeVoiceService,
    ColorSchemeOption? initialColorScheme,
  }) : _preferencesService = preferencesService,
       _colorScheme = initialColorScheme ?? defaultColorScheme,
       _aiService = aiService,
       _gameManifestService = gameManifestService,
       _remoteAssetService = remoteAssetService,
       _speechService = speechService,
       _ttsService = ttsService,
       _realtimeVoiceService =
           realtimeVoiceService ?? const UnconfiguredRealtimeVoiceService();

  final PreferencesService _preferencesService;
  final AiService _aiService;
  final GameManifestService _gameManifestService;
  final RemoteAssetService _remoteAssetService;
  final SpeechService _speechService;
  final TtsService _ttsService;
  final RealtimeVoiceService _realtimeVoiceService;

  AppLanguage _language = AppLanguage.zhHans;
  ColorSchemeOption _colorScheme;
  bool _voiceReplyEnabled = true;
  AssistantMode _assistantMode = AssistantMode.textAndDictation;
  bool _checkForUpdates = true;
  bool _speechAvailable = false;
  bool _isListening = false;
  double _speechLevel = 0;
  String _selectedGameId = 'puerto-rico';
  AiAnswerMode _gameAnswerMode = AiAnswerMode.knowledgeOnly;
  AiAnswerMode _globalAnswerMode = AiAnswerMode.knowledgeThenDirect;
  bool _globalUseCurrentGameKnowledge = false;
  AiApiConfig _aiApiConfig = AiApiConfig.defaultOpenAi;
  List<AiApiConfig> _customAiPresets = <AiApiConfig>[];
  List<AiModel> _availableAiModels = <AiModel>[];
  AiModelLoadState _aiModelLoadState = AiModelLoadState.idle;
  String? _aiModelLoadError;
  Future<List<AiModel>>? _aiModelRefreshFuture;
  String? _aiModelRefreshSignature;
  int _aiModelRefreshGeneration = 0;
  List<AssetSourceConfig> _assetSourceConfigs = AssetSourceConfig.defaults;
  List<GameInfo> _games = <GameInfo>[];
  List<DesktopLibraryResource> _libraryResources = <DesktopLibraryResource>[];
  LibraryLoadState _libraryLoadState = LibraryLoadState.idle;
  String? _libraryLoadError;
  Future<void>? _libraryRefreshFuture;
  Future<void>? _libraryCacheLoadFuture;
  bool _libraryCacheLoadAttempted = false;
  int _libraryRefreshGeneration = 0;
  ConnectivityStatus _aiConnectivityStatus = ConnectivityStatus(
    state: ConnectivityState.unknown,
    message: '未检测',
    checkedAt: DateTime.now(),
  );
  ConnectivityStatus _assetConnectivityStatus = ConnectivityStatus.unknown(
    '未检测',
  );
  final Map<String, ConnectivityStatus> _assetSourceStatuses =
      <String, ConnectivityStatus>{};
  final Map<String, String> _resolvedAssetPaths = <String, String>{};
  Timer? _assetStatusTimer;
  Future<void>? _assetStatusRefreshFuture;
  Future<void>? _serviceStatusRefreshFuture;
  Future<void>? _aiServiceStatusRefreshFuture;
  int _aiServiceStatusGeneration = 0;
  RemoteLibraryUpdate? _pendingLibraryUpdate;
  bool _checkingLibraryUpdate = false;
  bool _applyingLibraryUpdate = false;
  bool _libraryUpdatePromptSeen = false;
  bool _homeAssetsLoading = false;
  int _homeAssetsLoaded = 0;
  int _homeAssetsTotal = 0;
  Future<void> _conversationSaveQueue = Future<void>.value();
  Future<void> _selectedConversationSaveQueue = Future<void>.value();
  Future<void> _activitySaveQueue = Future<void>.value();
  Future<void> _favoriteMutationQueue = Future<void>.value();
  Future<void> _searchHistoryMutationQueue = Future<void>.value();
  Future<void> _recentGamesMutationQueue = Future<void>.value();
  int _searchHistoryStateVersion = 0;
  int _recentGamesStateVersion = 0;
  final Map<String, DateTime> _favoriteCreatedAtBySlug = <String, DateTime>{};
  final Map<String, AiConversation> _conversations = <String, AiConversation>{};
  List<AppActivity> _activities = <AppActivity>[];
  List<SearchHistoryRecord> _searchHistory = <SearchHistoryRecord>[];
  List<RecentGameRecord> _recentGameRecords = <RecentGameRecord>[];
  List<DailyRecommendationRecord> _dailyRecommendationHistory =
      <DailyRecommendationRecord>[];
  Future<void> _dailyRecommendationSaveQueue = Future<void>.value();
  String? _selectedConversationId;
  final Map<String, _ChatGenerationState> _generationStates =
      <String, _ChatGenerationState>{};
  final Map<String, bool> _runExpandedByContext = <String, bool>{};

  AppLanguage get language => _language;
  ColorSchemeOption get colorScheme => _colorScheme;
  AppPalette get palette => PaletteRegistry.of(_colorScheme);
  bool get voiceReplyEnabled => _voiceReplyEnabled;
  bool get voiceReplyAvailable => _ttsService.isAvailable;
  AssistantMode get assistantMode => _assistantMode;
  bool get realtimeVoiceAvailable =>
      _realtimeVoiceService.availability == RealtimeVoiceAvailability.available;
  String get realtimeVoiceAvailabilityMessage =>
      _realtimeVoiceService.availabilityMessage;
  bool get checkForUpdates => _checkForUpdates;
  bool get speechAvailable => _speechAvailable;
  bool get isListening => _isListening;
  double get speechLevel => _speechLevel;
  String? get speechError => _speechService.lastError;
  bool get isSending => isSendingForContext(useGlobalMode: false);
  bool isSendingForContext({required bool useGlobalMode}) =>
      _generationStateForContext(useGlobalMode: useGlobalMode).isSending;
  List<AiRunEvent> aiRunEventsForContext({required bool useGlobalMode}) =>
      UnmodifiableListView<AiRunEvent>(
        _generationStateForContext(useGlobalMode: useGlobalMode).runEvents,
      );
  String? aiRunIdForContext({required bool useGlobalMode}) =>
      _generationStateForContext(useGlobalMode: useGlobalMode).runId;
  DateTime? aiRunStartedAtForContext({required bool useGlobalMode}) =>
      _generationStateForContext(useGlobalMode: useGlobalMode).runStartedAt;
  DateTime? aiRunCompletedAtForContext({required bool useGlobalMode}) =>
      _generationStateForContext(useGlobalMode: useGlobalMode).runCompletedAt;
  AiRunStatus? aiRunStatusForContext({required bool useGlobalMode}) =>
      _generationStateForContext(useGlobalMode: useGlobalMode).runStatus;
  bool? aiRunExpandedForContext({required bool useGlobalMode}) =>
      _runExpandedByContext[_conversationKeyForContext(
        useGlobalMode: useGlobalMode,
      )];

  void setAiRunExpandedForContext({
    required bool useGlobalMode,
    required bool expanded,
  }) {
    final String key = _conversationKeyForContext(useGlobalMode: useGlobalMode);
    if (_runExpandedByContext[key] == expanded) return;
    _runExpandedByContext[key] = expanded;
    notifyListeners();
  }

  bool get hasSelectedAiModel => _aiApiConfig.model.trim().isNotEmpty;
  AiModelResolution get selectedAiModelResolution =>
      AiModelPolicy.resolve(_aiApiConfig);
  AiAnswerMode get gameAnswerMode => _gameAnswerMode;
  AiAnswerMode get globalAnswerMode => _globalAnswerMode;
  bool get globalUseCurrentGameKnowledge => _globalUseCurrentGameKnowledge;
  AiApiConfig get aiApiConfig => _aiApiConfig;
  List<AiApiConfig> get customAiPresets =>
      List<AiApiConfig>.unmodifiable(_customAiPresets);
  List<AiModel> get availableAiModels =>
      List<AiModel>.unmodifiable(_availableAiModels);
  AiModelLoadState get aiModelLoadState => _aiModelLoadState;
  String? get aiModelLoadError => _aiModelLoadError;
  List<AssetSourceConfig> get assetSourceConfigs =>
      List<AssetSourceConfig>.unmodifiable(_assetSourceConfigs);
  ConnectivityStatus get aiConnectivityStatus => _aiConnectivityStatus;
  ConnectivityStatus get assetConnectivityStatus => _assetConnectivityStatus;
  Map<String, ConnectivityStatus> get assetSourceStatuses =>
      Map<String, ConnectivityStatus>.unmodifiable(_assetSourceStatuses);
  List<DesktopLibraryResource> get libraryResources =>
      List<DesktopLibraryResource>.unmodifiable(_libraryResources);
  LibraryLoadState get libraryLoadState => _libraryLoadState;
  String? get libraryLoadError => _libraryLoadError;
  bool get isRefreshingLibrary => _libraryRefreshFuture != null;
  bool get isRefreshingServiceStatuses => _serviceStatusRefreshFuture != null;
  String? get selectedConversationId => _selectedConversationId;
  List<AppActivity> get activities =>
      List<AppActivity>.unmodifiable(_activities);
  int get unreadActivityCount =>
      _activities.where((AppActivity activity) => !activity.isRead).length;
  bool get selectedConversationIsGlobal =>
      selectedConversation?.scope == AiConversationScope.global;
  AiConversation? get selectedConversation {
    final String? id = _selectedConversationId;
    return id == null ? null : _conversations[id]?.copyWith();
  }

  List<AiConversation> get conversations {
    final List<AiConversation> result = _conversations.values
        .where(_isConversationAvailable)
        .map((AiConversation conversation) => conversation.copyWith())
        .toList();
    result.sort((AiConversation left, AiConversation right) {
      if (left.isGlobal != right.isGlobal) {
        return left.isGlobal ? -1 : 1;
      }
      return right.updatedAt.compareTo(left.updatedAt);
    });
    return List<AiConversation>.unmodifiable(result);
  }

  RemoteLibraryUpdate? get pendingLibraryUpdate => _pendingLibraryUpdate;
  bool get checkingLibraryUpdate => _checkingLibraryUpdate;
  bool get applyingLibraryUpdate => _applyingLibraryUpdate;
  bool get homeAssetsLoading => _homeAssetsLoading;
  int get homeAssetsLoaded => _homeAssetsLoaded;
  int get homeAssetsTotal => _homeAssetsTotal;
  bool get hasGames => _games.isNotEmpty;
  String? resolvedAssetPath(String remotePath) =>
      _resolvedAssetPaths[remotePath];
  AppCopy get copy => AppCopy(_language);
  List<GameInfo> get games => List<GameInfo>.unmodifiable(_games);
  List<GameInfo> get dailyRecommendedGames {
    final today = DailyGameRecommender.localDateKey(DateTime.now());
    final before = _dailyRecommendationHistory
        .where((record) => record.date == today)
        .firstOrNull;
    final next = const DailyGameRecommender().update(
      now: DateTime.now(),
      games: _games,
      history: _dailyRecommendationHistory,
      favoriteSlugs: _favoriteCreatedAtBySlug.keys.toSet(),
      recentlyViewed: _recentGameRecords,
    );
    final current = next.where((record) => record.date == today).firstOrNull;
    if (current != null &&
        (before == null || !listEquals(before.gameIds, current.gameIds))) {
      _dailyRecommendationHistory = next;
      _dailyRecommendationSaveQueue = _dailyRecommendationSaveQueue
          .then((_) => _preferencesService.saveDailyRecommendations(next))
          .catchError((Object error) {
            debugPrint('[recommendations] save failed: $error');
          });
    }
    final gamesById = <String, GameInfo>{
      for (final game in _games) game.id: game,
    };
    return List<GameInfo>.unmodifiable(
      current?.gameIds.map((id) => gamesById[id]).whereType<GameInfo>() ??
          const <GameInfo>[],
    );
  }

  List<GameInfo> get favoriteGames {
    final result = _games.where(isFavorite).toList(growable: true)
      ..sort((left, right) {
        final leftCreatedAt =
            _favoriteCreatedAtBySlug[left.slug] ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
        final rightCreatedAt =
            _favoriteCreatedAtBySlug[right.slug] ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
        return rightCreatedAt.compareTo(leftCreatedAt);
      });
    return List<GameInfo>.unmodifiable(result);
  }

  int get favoriteCount => _favoriteCreatedAtBySlug.length;
  List<SearchHistoryRecord> get searchHistory =>
      List<SearchHistoryRecord>.unmodifiable(_searchHistory);

  List<RecentGameRecord> get recentGameRecords =>
      List<RecentGameRecord>.unmodifiable(_recentGameRecords);

  List<GameInfo> get recentlyViewedGames {
    final gamesBySlug = <String, GameInfo>{
      for (final game in _games) game.slug.trim().toLowerCase(): game,
    };
    return List<GameInfo>.unmodifiable(
      _recentGameRecords
          .map((record) => gamesBySlug[record.normalizedGameSlug])
          .whereType<GameInfo>(),
    );
  }

  int get recentlyViewedCount => _recentGameRecords.length;

  bool isFavorite(GameInfo game) {
    final slug = game.slug.trim();
    return slug.isNotEmpty && _favoriteCreatedAtBySlug.containsKey(slug);
  }

  GameInfo get featuredGame => selectedGame;
  GameInfo get selectedGame {
    if (_games.isEmpty) {
      return GameInfo.empty();
    }
    return _games.firstWhere(
      (game) => game.id == _selectedGameId,
      orElse: () => _games.first,
    );
  }

  UnmodifiableListView<ChatMessage> get messages =>
      UnmodifiableListView<ChatMessage>(_messagesForCurrentContext());
  UnmodifiableListView<ChatMessage> messagesForContext({
    required bool useGlobalMode,
  }) => UnmodifiableListView<ChatMessage>(
    _messagesForContext(useGlobalMode: useGlobalMode),
  );

  /// Returns the number of messages stored for a game's conversation.
  ///
  /// The desktop assistant uses this to render a lightweight session list
  /// without exposing the mutable conversation map to the UI layer.
  int messageCountForGame(String gameId) {
    return _conversations[_conversationKeyForGameId(gameId)]?.messageCount ?? 0;
  }

  AiAnswerMode chatAnswerMode({required bool useGlobalMode}) =>
      useGlobalMode ? _globalAnswerMode : _gameAnswerMode;

  bool allowSmartSupplement({required bool useGlobalMode}) =>
      chatAnswerMode(useGlobalMode: useGlobalMode) ==
      AiAnswerMode.knowledgeThenDirect;

  static const int _maxActivities = 50;

  void _recordActivity({
    required AppActivityKind kind,
    required String title,
    required String message,
    DateTime? createdAt,
    String? conversationId,
    String? messageId,
  }) {
    final DateTime occurredAt = createdAt ?? DateTime.now();
    final AppActivity? existing = _activities
        .where((AppActivity activity) => activity.kind == kind)
        .cast<AppActivity?>()
        .firstWhere(
          (AppActivity? activity) => activity != null,
          orElse: () => null,
        );
    final AppActivity activity = AppActivity(
      id: existing?.id ?? 'activity-${DateTime.now().microsecondsSinceEpoch}',
      kind: kind,
      title: title,
      message: message,
      createdAt: occurredAt,
      conversationId: conversationId,
      messageId: messageId,
    );
    _activities = latestActivitiesByKind(<AppActivity>[
      activity,
      ..._activities,
    ], maxEntries: _maxActivities);
    _queueActivitySave();
    notifyListeners();
  }

  void _recordLibraryLoadFailure(String message) {
    final String normalized = message.trim();
    if (normalized.isEmpty) return;
    _recordActivity(
      kind: AppActivityKind.libraryLoadFailed,
      title: copy.activityLibraryLoadFailedTitle,
      message: copy.activityLibraryLoadFailedMessage(normalized),
    );
  }

  void _queueActivitySave() {
    final List<AppActivity> snapshot = List<AppActivity>.from(_activities);
    _activitySaveQueue = _activitySaveQueue
        .catchError((Object _) {})
        .then((_) => _preferencesService.saveActivities(snapshot));
  }

  Future<void> markActivitiesRead() async {
    final bool hasUnread = _activities.any(
      (AppActivity activity) => !activity.isRead,
    );
    if (!hasUnread) {
      return;
    }
    _activities = _activities
        .map((AppActivity activity) => activity.copyWith(isRead: true))
        .toList(growable: false);
    _queueActivitySave();
    notifyListeners();
  }

  /// Marks one notification as read without changing the rest of the center.
  /// This is used when a user follows a notification into its target session.
  Future<void> markActivityRead(String activityId) async {
    final AppActivity? target = _activities
        .where((AppActivity activity) => activity.id == activityId)
        .cast<AppActivity?>()
        .firstWhere(
          (AppActivity? activity) => activity != null,
          orElse: () => null,
        );
    if (target == null || target.isRead) return;
    _activities = _activities
        .map(
          (AppActivity activity) => activity.id == activityId
              ? activity.copyWith(isRead: true)
              : activity,
        )
        .toList(growable: false);
    _queueActivitySave();
    notifyListeners();
  }

  /// Resolves legacy AI notifications that were persisted before activities
  /// carried a conversation target. New notifications already contain these
  /// fields; migration keeps the existing notification center useful after an
  /// app update without guessing targets for unrelated activity kinds.
  AppActivity resolveActivityTarget(AppActivity activity) {
    if (!_isAiActivity(activity) ||
        (activity.conversationId?.trim().isNotEmpty ?? false)) {
      return activity;
    }
    final String? conversationId = _inferActivityConversationId(activity);
    if (conversationId == null) return activity;
    return activity.copyWith(
      conversationId: conversationId,
      messageId: _inferActivityMessageId(conversationId, activity.createdAt),
    );
  }

  bool _isAiActivity(AppActivity activity) {
    return activity.kind == AppActivityKind.aiCompleted ||
        activity.kind == AppActivityKind.aiFailed;
  }

  void _migrateActivityTargets() {
    bool changed = false;
    final List<AppActivity> migrated = _activities
        .map((AppActivity item) {
          final AppActivity resolved = resolveActivityTarget(item);
          if (resolved.conversationId != item.conversationId ||
              resolved.messageId != item.messageId) {
            changed = true;
          }
          return resolved;
        })
        .toList(growable: false);
    if (!changed) return;
    _activities = migrated;
    _queueActivitySave();
  }

  String? _inferActivityConversationId(AppActivity activity) {
    // Completed and failed notifications are timestamped next to the answer
    // commit. Prefer that temporal link so a global answer mentioning the
    // featured game's title is not mistaken for a game-scoped session.
    String? nearestId;
    Duration? nearestDistance;
    for (final AiConversation conversation in _conversations.values) {
      final bool hasAssistantMessage = conversation.messages.any(
        (ChatMessage message) => message.role == ChatRole.assistant,
      );
      if (!hasAssistantMessage) continue;
      final Duration distance = _conversationActivityDistance(
        conversation,
        activity.createdAt,
      );
      if (nearestDistance == null || distance < nearestDistance) {
        nearestDistance = distance;
        nearestId = conversation.id;
      }
    }
    if (nearestId != null) return nearestId;

    final RegExpMatch? titleMatch = RegExp(
      r'《([^》]+)》',
    ).firstMatch(activity.message);
    final String? gameTitle = titleMatch?.group(1)?.trim();
    if (gameTitle != null && gameTitle.isNotEmpty) {
      for (final GameInfo game in _games) {
        if (game.title.trim() == gameTitle ||
            game.title.toLowerCase().contains(gameTitle.toLowerCase()) ||
            gameTitle.toLowerCase().contains(game.title.toLowerCase())) {
          final String id = _conversationKeyForGameId(game.id);
          if (_conversations.containsKey(id)) return id;
        }
      }
    }

    return null;
  }

  String? _inferActivityMessageId(String conversationId, DateTime createdAt) {
    final AiConversation? conversation = _conversations[conversationId];
    if (conversation == null) return null;
    ChatMessage? nearest;
    Duration? nearestDistance;
    for (final ChatMessage message in conversation.messages) {
      if (message.role != ChatRole.assistant) continue;
      final Duration distance = message.timestamp.difference(createdAt).abs();
      if (nearestDistance == null || distance < nearestDistance) {
        nearestDistance = distance;
        nearest = message;
      }
    }
    return nearest?.id;
  }

  Duration _conversationActivityDistance(
    AiConversation conversation,
    DateTime createdAt,
  ) {
    Duration? nearest;
    for (final ChatMessage message in conversation.messages) {
      if (message.role != ChatRole.assistant) continue;
      final Duration distance = message.timestamp.difference(createdAt).abs();
      if (nearest == null || distance < nearest) nearest = distance;
    }
    return nearest ?? conversation.updatedAt.difference(createdAt).abs();
  }

  void _setPendingLibraryUpdate(RemoteLibraryUpdate update) {
    final RemoteLibraryUpdate? previous = _pendingLibraryUpdate;
    _pendingLibraryUpdate = update;
    _libraryUpdatePromptSeen = false;
    final bool isSame =
        previous != null &&
        previous.changedPaths.length == update.changedPaths.length &&
        previous.changedPaths.toSet().containsAll(update.changedPaths) &&
        update.changedPaths.toSet().containsAll(previous.changedPaths);
    if (!isSame) {
      _recordActivity(
        kind: AppActivityKind.libraryUpdate,
        title: copy.activityLibraryUpdateTitle,
        message: copy.activityLibraryUpdateMessage(update.changedCount),
      );
    }
  }

  Future<void> initialize() async {
    _language = await _preferencesService.loadLanguage();
    _colorScheme = await _preferencesService.loadColorScheme();
    _voiceReplyEnabled = await _preferencesService.loadVoiceReplyEnabled();
    final AssistantMode savedAssistantMode = await _preferencesService
        .loadAssistantMode();
    _assistantMode =
        savedAssistantMode == AssistantMode.realtimeVoice &&
            !realtimeVoiceAvailable
        ? AssistantMode.textAndDictation
        : savedAssistantMode;
    _checkForUpdates = await _preferencesService.loadCheckForUpdates();
    _gameAnswerMode = await _preferencesService.loadGameAnswerMode();
    _globalAnswerMode = await _preferencesService.loadGlobalAnswerMode();
    _globalUseCurrentGameKnowledge = await _preferencesService
        .loadGlobalUseCurrentGameKnowledge();
    _customAiPresets = await _preferencesService.loadAiCustomPresets();
    _aiApiConfig = await _preferencesService.loadAiApiConfig();
    _selectedConversationId = await _preferencesService
        .loadSelectedConversationId();
    final List<AppActivity> storedActivities = await _preferencesService
        .loadActivities();
    _activities = latestActivitiesByKind(
      storedActivities,
      maxEntries: _maxActivities,
    );
    if (_activities.length != storedActivities.length) {
      _queueActivitySave();
    }
    try {
      final records = await _preferencesService.loadFavoriteGames();
      _favoriteCreatedAtBySlug
        ..clear()
        ..addEntries(
          records.map(
            (record) => MapEntry(record.gameSlug.trim(), record.createdAt),
          ),
        )
        ..removeWhere((slug, _) => slug.isEmpty);
    } catch (error) {
      debugPrint('[favorites] load failed: $error');
      _favoriteCreatedAtBySlug.clear();
    }
    try {
      _searchHistory = await _preferencesService.loadSearchHistory();
    } catch (error) {
      debugPrint('[search-history] load failed: $error');
      _searchHistory = <SearchHistoryRecord>[];
    }
    try {
      _recentGameRecords = await _preferencesService.loadRecentGames();
    } catch (error) {
      debugPrint('[recent-games] load failed: $error');
      _recentGameRecords = <RecentGameRecord>[];
    }
    try {
      _dailyRecommendationHistory = await _preferencesService
          .loadDailyRecommendations();
    } catch (error) {
      debugPrint('[recommendations] load failed: $error');
      _dailyRecommendationHistory = <DailyRecommendationRecord>[];
    }
    if (_isSaveableCustomPreset(_aiApiConfig)) {
      _customAiPresets = _upsertCustomPreset(_customAiPresets, _aiApiConfig);
      await _preferencesService.saveAiCustomPresets(_customAiPresets);
    }
    _assetSourceConfigs = await _preferencesService.loadAssetSourceConfigs();
    _games = await _loadGamesForLanguage(_language);
    await _ensureLibraryCacheLoaded();
    _selectedGameId = _resolveSelectedGameId(_selectedGameId);
    await _restoreConversations();
    _migrateActivityTargets();
    _selectedConversationId = _resolveSelectedConversationId(
      _selectedConversationId,
    );
    await _persistSelectedConversationId();
    debugPrint(
      '[updates] initialize loaded games: ${_games.map((g) => '${g.slug}:${g.title}').join(', ')}',
    );
    _aiConnectivityStatus = ConnectivityStatus.unknown(
      _aiApiConfig.baseUrl.trim().isEmpty || _aiApiConfig.apiKey.trim().isEmpty
          ? '未配置 AI 服务'
          : '未检测',
    );
    for (final source in _assetSourceConfigs) {
      _assetSourceStatuses[source.id] = ConnectivityStatus.unknown('未检测');
    }
    try {
      _speechAvailable = await _speechService.initialize(
        onListeningStopped: _handleListeningStopped,
      );
    } catch (_) {
      _speechAvailable = false;
    }
    await _ttsService.initialize(_language);
    if (!voiceReplyAvailable) {
      _voiceReplyEnabled = false;
    }
    _queueConversationSave();
    unawaited(_initializeRemoteLibrary());
    if (_aiApiConfig.baseUrl.trim().isNotEmpty &&
        _aiApiConfig.apiKey.trim().isNotEmpty) {
      unawaited(_refreshAiModelsOnInitialize());
    }
    notifyListeners();
  }

  Future<void> setLanguage(AppLanguage next) async {
    if (_language == next) {
      return;
    }

    _language = next;
    _games = await _loadGamesForLanguage(_language);
    _refreshLibraryGameTitles();
    _selectedGameId = _resolveSelectedGameId(_selectedGameId);
    _refreshConversationMetadata();
    _selectedConversationId = _resolveSelectedConversationId(
      _selectedConversationId,
    );
    await _persistSelectedConversationId();
    await _preferencesService.saveLanguage(next);
    await _ttsService.setLanguage(next);
    notifyListeners();
  }

  Future<void> reloadGames() async {
    _games = await _loadGamesForLanguage(_language);
    _refreshLibraryGameTitles();
    _selectedGameId = _resolveSelectedGameId(_selectedGameId);
    _refreshConversationMetadata();
    _selectedConversationId = _resolveSelectedConversationId(
      _selectedConversationId,
    );
    await _persistSelectedConversationId();
    notifyListeners();
  }

  Future<void> setColorScheme(ColorSchemeOption next) async {
    if (_colorScheme == next) {
      return;
    }

    _colorScheme = next;
    await _preferencesService.saveColorScheme(next);
    notifyListeners();
  }

  Future<void> setCheckForUpdates(bool enabled) async {
    if (_checkForUpdates == enabled) return;
    _checkForUpdates = enabled;
    await _preferencesService.saveCheckForUpdates(enabled);
    notifyListeners();
  }

  Future<void> disposeServices() async {
    _assetStatusTimer?.cancel();
    for (final _ChatGenerationState generation in _generationStates.values) {
      generation.wasStopped = true;
      final Completer<void>? generationAbort = generation.abort;
      if (generationAbort != null && !generationAbort.isCompleted) {
        generationAbort.complete();
      }
    }
    await _conversationSaveQueue;
    await _selectedConversationSaveQueue;
    await _activitySaveQueue;
    await _searchHistoryMutationQueue;
    await _recentGamesMutationQueue;
    await _speechService.cancelListening();
    await _ttsService.stop();
    _aiService.dispose();
  }

  void _notifyListeners() => notifyListeners();

  void _startAssetStatusPolling() {
    _assetStatusTimer?.cancel();
    _assetStatusTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(refreshAssetAccessStatus());
    });
  }
}

class _StreamTextBatcher {
  _StreamTextBatcher(this._onFlush);

  final void Function(String delta) _onFlush;
  final StringBuffer _buffer = StringBuffer();
  Timer? _timer;

  void add(String delta) {
    if (delta.isEmpty) return;
    _buffer.write(delta);
    _timer ??= Timer(const Duration(milliseconds: 16), flush);
  }

  void flush() {
    _timer?.cancel();
    _timer = null;
    if (_buffer.isEmpty) return;
    final String delta = _buffer.toString();
    _buffer.clear();
    _onFlush(delta);
  }

  void dispose() {
    flush();
  }
}

class _ChatGenerationState {
  bool isSending = false;
  Completer<void>? abort;
  bool wasStopped = false;
  bool syntheticRun = false;
  bool checkpointRestored = false;
  AiRunResult? runResult;
  int runSequence = 0;
  String? runId;
  String? contextKey;
  DateTime? runStartedAt;
  DateTime? runCompletedAt;
  AiRunStatus? runStatus;
  int operationToken = 0;
  int contextEpoch = 0;
  final List<AiRunEvent> runEvents = <AiRunEvent>[];
  bool useGlobalMode = false;
}
