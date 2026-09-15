import 'dart:collection';
import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:app_ai_client/app_ai_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:path_provider/path_provider.dart';

import '../models/ai_api_config.dart';
import '../models/ai_answer_mode.dart';
import '../models/ai_run.dart';
import '../models/answer_source.dart';
import '../models/assistant_mode.dart';
import '../models/asset_source_config.dart';
import '../models/app_language.dart';
import '../models/app_activity.dart';
import '../models/board_game_ai_answer.dart';
import '../models/chat_message.dart';
import '../models/ai_conversation.dart';
import '../models/cached_asset.dart';
import '../models/connectivity_status.dart';
import '../models/color_scheme_option.dart';
import '../models/desktop_library_resource.dart';
import '../models/favorite_game_record.dart';
import '../models/game_info.dart';
import '../models/game_catalog_manifest.dart';
import '../models/game_resource.dart';
import '../models/remote_library_update.dart';
import '../models/remote_asset_file.dart';
import '../models/resolved_document.dart';
import '../models/evidence_chunk.dart';
import '../models/rule_citation.dart';
import '../services/ai_service.dart';
import '../services/preferences_service.dart';
import '../services/game_manifest_service.dart';
import '../services/remote_asset_service.dart';
import '../services/speech_service.dart';
import '../services/tts_service.dart';
import '../services/realtime_voice_service.dart';
import '../services/ai_error_presenter.dart';
import '../theme/app_palette.dart';
import '../theme/palette_registry.dart';
import '../ui/app_copy.dart';

enum AiModelLoadState { idle, loading, success, empty, failure }

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
       _colorScheme = initialColorScheme ?? ColorSchemeOption.sunsetCoast,
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
  final Map<String, DateTime> _favoriteCreatedAtBySlug = <String, DateTime>{};
  final Map<String, AiConversation> _conversations = <String, AiConversation>{};
  List<AppActivity> _activities = <AppActivity>[];
  String? _selectedConversationId;
  final Map<String, _ChatGenerationState> _generationStates =
      <String, _ChatGenerationState>{};
  final Map<String, bool> _runExpandedByContext = <String, bool>{};
  late final http.Client _assetTestClient = IOClient(
    HttpClient()
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true,
  );

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

  Future<bool> toggleFavorite(GameInfo game) {
    final Future<bool> operation = _favoriteMutationQueue
        .catchError((Object _) {})
        .then<bool>((_) => _toggleFavoriteNow(game));
    _favoriteMutationQueue = operation.then<void>((_) {});
    return operation;
  }

  Future<bool> _toggleFavoriteNow(GameInfo game) async {
    final slug = game.slug.trim();
    if (slug.isEmpty) return false;

    final previous = Map<String, DateTime>.of(_favoriteCreatedAtBySlug);
    if (_favoriteCreatedAtBySlug.containsKey(slug)) {
      _favoriteCreatedAtBySlug.remove(slug);
    } else {
      _favoriteCreatedAtBySlug[slug] = DateTime.now().toUtc();
    }
    notifyListeners();

    try {
      await _preferencesService.saveFavoriteGames(
        _favoriteCreatedAtBySlug.entries.map(
          (entry) =>
              FavoriteGameRecord(gameSlug: entry.key, createdAt: entry.value),
        ),
      );
      return true;
    } catch (error) {
      _favoriteCreatedAtBySlug
        ..clear()
        ..addAll(previous);
      notifyListeners();
      debugPrint('[favorites] save failed: $error');
      return false;
    }
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

  Future<void> saveAiApiConfig(AiApiConfig next) async {
    final AiApiConfig previous = _aiApiConfig;
    final bool runContextChanged = _aiRunContextChanged(previous, next);
    _invalidateActiveRuns();
    _aiApiConfig = next;
    if (runContextChanged) {
      // A response id, compaction snapshot, and activity timeline belong to
      // one provider/model context. Keep the conversation messages, but do
      // not show or reuse a Run produced by an incompatible endpoint.
      _clearIncompatibleRunState();
    }
    _aiConnectivityStatus = ConnectivityStatus.unknown(
      next.baseUrl.trim().isEmpty || next.apiKey.trim().isEmpty
          ? '未配置 AI 服务'
          : '等待检查',
    );
    invalidateAiModels();
    await _preferencesService.saveAiApiConfig(next);
    if (_isSaveableCustomPreset(next)) {
      _customAiPresets = _upsertCustomPreset(_customAiPresets, next);
      await _preferencesService.saveAiCustomPresets(_customAiPresets);
    }
    if (runContextChanged) {
      _queueConversationSave();
    }
    notifyListeners();
  }

  /// Selects the model used by subsequent assistant runs.
  ///
  /// Keeping this operation at the controller boundary ensures the desktop
  /// composer, settings and any future platform UI share the same persistence,
  /// model-cache invalidation and active-run isolation behavior.
  Future<void> setAiModel(String model) async {
    final String normalized = model.trim();
    if (normalized.isEmpty || normalized == _aiApiConfig.model.trim()) {
      return;
    }
    await saveAiApiConfig(_aiApiConfig.copyWith(model: normalized));
  }

  /// Selects the reasoning effort sent to providers that support it.
  ///
  /// Automatic deliberately omits the optional request field, preserving
  /// compatibility with OpenAI-compatible providers that do not implement it.
  Future<void> setAiReasoningEffort(AiReasoningEffort effort) async {
    if (_aiApiConfig.reasoningEffort == effort) return;
    await saveAiApiConfig(_aiApiConfig.copyWith(reasoningEffort: effort));
  }

  bool _aiRunContextChanged(AiApiConfig previous, AiApiConfig next) {
    return previous.name.trim() != next.name.trim() ||
        previous.baseUrl.trim() != next.baseUrl.trim() ||
        previous.apiKey.trim() != next.apiKey.trim() ||
        previous.model.trim() != next.model.trim() ||
        previous.apiKeyHeader.trim() != next.apiKeyHeader.trim() ||
        previous.chatPath.trim() != next.chatPath.trim() ||
        previous.reasoningEffort != next.reasoningEffort ||
        previous.responseSpeed != next.responseSpeed;
  }

  void _clearIncompatibleRunState() {
    for (final AiConversation conversation in _conversations.values) {
      conversation.lastRun = null;
    }
    for (final _ChatGenerationState generation in _generationStates.values) {
      generation
        ..runEvents.clear()
        ..runId = null
        ..contextKey = null
        ..runStartedAt = null
        ..runCompletedAt = null
        ..runStatus = null
        ..runResult = null
        ..runSequence = 0
        ..syntheticRun = false
        ..checkpointRestored = true;
    }
    _runExpandedByContext.clear();
  }

  bool _isSaveableCustomPreset(AiApiConfig config) {
    return config.providerPreset == AiProviderPreset.custom &&
        config.normalizedName.isNotEmpty &&
        !AiApiConfig.isBuiltInProviderName(config.name);
  }

  List<AiApiConfig> _upsertCustomPreset(
    Iterable<AiApiConfig> existing,
    AiApiConfig next,
  ) {
    final List<AiApiConfig> result = List<AiApiConfig>.from(existing);
    final int index = result.indexWhere(
      (AiApiConfig item) => item.normalizedName == next.normalizedName,
    );
    if (index == -1) {
      result.add(next);
    } else {
      result[index] = next;
    }
    return result;
  }

  Future<List<AiModel>> refreshAiModels({
    AiApiConfig? config,
    bool persistSelection = false,
  }) {
    final AiApiConfig target = config ?? _aiApiConfig;
    final String signature = _aiModelSignature(target);
    final Future<List<AiModel>>? active = _aiModelRefreshFuture;
    if (active != null && _aiModelRefreshSignature == signature) {
      return active;
    }

    final int generation = ++_aiModelRefreshGeneration;
    _aiModelRefreshSignature = signature;
    _aiModelLoadState = AiModelLoadState.loading;
    _aiModelLoadError = null;
    notifyListeners();

    final Future<List<AiModel>> future = _aiService
        .listModels(target)
        .then((List<AiModel> models) async {
          if (generation != _aiModelRefreshGeneration) {
            return models;
          }
          _availableAiModels = List<AiModel>.from(models);
          _aiModelLoadState = models.isEmpty
              ? AiModelLoadState.empty
              : AiModelLoadState.success;
          _aiModelLoadError = null;
          if (persistSelection && identical(config, null)) {
            final String selected = _aiApiConfig.model.trim();
            final bool stillAvailable = models.any(
              (AiModel model) => model.id == selected,
            );
            if (selected.isNotEmpty && !stillAvailable) {
              _aiApiConfig = _aiApiConfig.copyWith(model: '');
              await _preferencesService.saveAiApiConfig(_aiApiConfig);
            }
          }
          notifyListeners();
          return models;
        })
        .catchError((Object error, StackTrace stackTrace) {
          if (generation != _aiModelRefreshGeneration) {
            return Future<List<AiModel>>.error(error, stackTrace);
          }
          final bool empty =
              error is AiProtocolException &&
              error.message.toLowerCase().contains('empty model list');
          _aiModelLoadState = empty
              ? AiModelLoadState.empty
              : AiModelLoadState.failure;
          _aiModelLoadError = _safeStatusError(error);
          _availableAiModels = <AiModel>[];
          notifyListeners();
          return Future<List<AiModel>>.error(error, stackTrace);
        });
    _aiModelRefreshFuture = future;
    future
        .whenComplete(() {
          if (identical(_aiModelRefreshFuture, future)) {
            _aiModelRefreshFuture = null;
            _aiModelRefreshSignature = null;
          }
        })
        .catchError((Object _) => <AiModel>[]);
    return future;
  }

  Future<void> _refreshAiModelsOnInitialize() async {
    try {
      await refreshAiModels(persistSelection: true);
    } catch (_) {
      // The settings screen exposes the retryable failure state.
    }
  }

  void invalidateAiModels() {
    ++_aiModelRefreshGeneration;
    _aiModelRefreshFuture = null;
    _aiModelRefreshSignature = null;
    _availableAiModels = <AiModel>[];
    _aiModelLoadState = AiModelLoadState.idle;
    _aiModelLoadError = null;
    notifyListeners();
  }

  String _aiModelSignature(AiApiConfig config) {
    return '${config.baseUrl.trim()}\n${config.apiKey.trim()}';
  }

  Future<void> saveAssetSourceConfigs(List<AssetSourceConfig> next) async {
    _assetSourceConfigs = List<AssetSourceConfig>.from(next);
    await _preferencesService.saveAssetSourceConfigs(_assetSourceConfigs);
    for (final source in _assetSourceConfigs) {
      _assetSourceStatuses.putIfAbsent(
        source.id,
        () => ConnectivityStatus.unknown('未检测'),
      );
    }
    notifyListeners();
  }

  Future<String> testAiApiConfig(AiApiConfig config) async {
    final result = await _aiService.checkConnection(config);
    if (result.success) {
      _aiConnectivityStatus = ConnectivityStatus(
        state: ConnectivityState.success,
        message: copy.aiApiTestSuccess,
        checkedAt: DateTime.now(),
      );
      debugPrint('[ai] ${_aiConnectivityStatus.message}');
      notifyListeners();
      return copy.aiApiTestSuccess;
    }

    final String message = '连接失败: ${_safeStatusError(result.message)}';
    _aiConnectivityStatus = ConnectivityStatus(
      state: ConnectivityState.failure,
      message: message,
      checkedAt: DateTime.now(),
    );
    debugPrint('[ai] $message');
    notifyListeners();
    return message;
  }

  void selectGame(String gameId) {
    final bool gameChanged = _selectedGameId != gameId;
    final String previousConversationId = _selectedConversationId ?? '';
    if (gameChanged) _invalidateGenerationForKey(previousConversationId);
    _selectedGameId = gameId;
    _selectConversationInternal(_conversationKeyForGameId(gameId));
    if (gameChanged || previousConversationId != _selectedConversationId) {
      notifyListeners();
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
    notifyListeners();
    return true;
  }

  /// Opens the cross-game assistant, creating its session on first entry.
  void openGlobalAssistant({String? greeting}) {
    final String previousConversationId = _selectedConversationId ?? '';
    if (previousConversationId != _globalConversationKey) {
      _invalidateGenerationForKey(previousConversationId);
    }
    final AiConversation conversation = _ensureConversationForContext(
      useGlobalMode: true,
      greeting: greeting,
    );
    _selectConversationInternal(conversation.id);
    notifyListeners();
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
    notifyListeners();
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
        notifyListeners();
      }
      return;
    }
    _voiceReplyEnabled = enabled;
    await _preferencesService.saveVoiceReplyEnabled(enabled);
    if (!enabled) {
      await _ttsService.stop();
    }
    notifyListeners();
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
    notifyListeners();
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
    notifyListeners();
  }

  Future<void> setGlobalUseCurrentGameKnowledge(bool enabled) async {
    if (_globalUseCurrentGameKnowledge == enabled) return;
    _globalUseCurrentGameKnowledge = enabled;
    await _preferencesService.saveGlobalUseCurrentGameKnowledge(enabled);
    notifyListeners();
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
        notifyListeners();
        return;
      }
    }

    _isListening = true;
    _speechLevel = 0;
    notifyListeners();

    final bool started = await _speechService.startListening(
      language: _language,
      onResult: onRecognizedText,
      onListeningStopped: _handleListeningStopped,
      onSoundLevel: _handleSpeechLevel,
    );
    if (!started) {
      _isListening = false;
      _speechLevel = 0;
      notifyListeners();
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
    notifyListeners();
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
    notifyListeners();
    final _StreamTextBatcher deltaBatcher = _StreamTextBatcher((String delta) {
      final ChatMessage? current = _messageById(messages, draftId);
      if (current == null) return;
      _replaceMessage(
        messages,
        current.copyWith(text: '${current.text}$delta'),
      );
      notifyListeners();
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
          notifyListeners();
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
        notifyListeners();
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
      notifyListeners();
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
    await _speechService.cancelListening();
    await _ttsService.stop();
    _aiService.dispose();
    _assetTestClient.close();
  }

  Future<void> refreshAssetAccessStatus() {
    final Future<void>? active = _assetStatusRefreshFuture;
    if (active != null) {
      return active;
    }
    final Future<void> future = _refreshAssetAccessStatus();
    _assetStatusRefreshFuture = future;
    future
        .whenComplete(() {
          if (identical(_assetStatusRefreshFuture, future)) {
            _assetStatusRefreshFuture = null;
          }
        })
        .catchError((Object _) {});
    return future;
  }

  Future<void> _refreshAssetAccessStatus() async {
    final DateTime startedAt = DateTime.now();
    if (_games.isEmpty) {
      _assetSourceStatuses.clear();
      _assetConnectivityStatus = ConnectivityStatus(
        state: ConnectivityState.unknown,
        message: '暂无游戏资料',
        checkedAt: startedAt,
      );
      notifyListeners();
      return;
    }

    _assetConnectivityStatus = ConnectivityStatus(
      state: ConnectivityState.loading,
      message: '正在检查规则资料',
      checkedAt: startedAt,
    );
    for (final source in _assetSourceConfigs) {
      _assetSourceStatuses[source.id] = ConnectivityStatus(
        state: ConnectivityState.loading,
        message: '正在检查',
        checkedAt: startedAt,
      );
    }
    notifyListeners();

    final Map<String, ConnectivityStatus> nextStatuses =
        <String, ConnectivityStatus>{};
    for (final source in _assetSourceConfigs) {
      try {
        final CachedAsset? asset = await _remoteAssetService.ensureCached(
          sources: <AssetSourceConfig>[source],
          remotePath: 'assets/games/${featuredGame.slug}/images/cover.jpg',
          forceRefresh: true,
          allowCachedFallback: false,
        );
        final ConnectivityStatus status = asset != null
            ? ConnectivityStatus(
                state: ConnectivityState.success,
                message: '图片拉取成功',
                checkedAt: DateTime.now(),
              )
            : ConnectivityStatus(
                state: ConnectivityState.failure,
                message: '图片拉取失败',
                checkedAt: DateTime.now(),
              );
        debugPrint('[assets] ${source.id} => ${status.message}');
        nextStatuses[source.id] = status;
      } catch (error) {
        final failureStatus = ConnectivityStatus(
          state: ConnectivityState.failure,
          message: '超时或失败',
          checkedAt: DateTime.now(),
        );
        debugPrint('[assets] ${source.id} => ${failureStatus.message}: $error');
        nextStatuses[source.id] = failureStatus;
      }
    }
    _assetSourceStatuses
      ..clear()
      ..addAll(nextStatuses);
    final int successCount = nextStatuses.values
        .where(
          (ConnectivityStatus status) =>
              status.state == ConnectivityState.success,
        )
        .length;
    final int failureCount = nextStatuses.values
        .where(
          (ConnectivityStatus status) =>
              status.state == ConnectivityState.failure,
        )
        .length;
    final ConnectivityState aggregateState;
    final String aggregateMessage;
    if (nextStatuses.isEmpty) {
      aggregateState = ConnectivityState.unknown;
      aggregateMessage = '未配置资料来源';
    } else if (successCount == 0) {
      aggregateState = ConnectivityState.failure;
      aggregateMessage = '规则资料访问失败';
    } else if (failureCount > 0) {
      aggregateState = ConnectivityState.warning;
      aggregateMessage = '部分资料来源可用';
    } else {
      aggregateState = ConnectivityState.success;
      aggregateMessage = '规则资料访问正常';
    }
    _assetConnectivityStatus = ConnectivityStatus(
      state: aggregateState,
      message: aggregateMessage,
      checkedAt: DateTime.now(),
    );
    notifyListeners();
  }

  /// Refreshes every user-visible service status from its real endpoint.
  ///
  /// Model discovery validates the AI endpoint even before a model is chosen.
  /// When a model is selected, a small completion request is also issued so
  /// the status reflects the actual chat path rather than only `/models`.
  Future<void> refreshServiceStatuses() {
    final Future<void>? active = _serviceStatusRefreshFuture;
    if (active != null) {
      return active;
    }
    final Future<void> future = _refreshServiceStatuses();
    _serviceStatusRefreshFuture = future;
    future
        .whenComplete(() {
          if (identical(_serviceStatusRefreshFuture, future)) {
            _serviceStatusRefreshFuture = null;
          }
        })
        .catchError((Object _) {});
    return future;
  }

  Future<void> _refreshServiceStatuses() async {
    final DateTime startedAt = DateTime.now();
    _aiConnectivityStatus = ConnectivityStatus(
      state: ConnectivityState.loading,
      message: '正在检查 AI 服务',
      checkedAt: startedAt,
    );
    _assetConnectivityStatus = ConnectivityStatus(
      state: ConnectivityState.loading,
      message: '正在检查规则资料',
      checkedAt: startedAt,
    );
    for (final source in _assetSourceConfigs) {
      _assetSourceStatuses[source.id] = ConnectivityStatus(
        state: ConnectivityState.loading,
        message: '正在检查',
        checkedAt: startedAt,
      );
    }
    notifyListeners();

    try {
      await Future.wait<void>(<Future<void>>[
        _refreshAiServiceStatus(),
        refreshAssetAccessStatus(),
      ]);
      _recordActivity(
        kind: AppActivityKind.serviceRefresh,
        title: copy.activityServiceRefreshTitle,
        message: copy.activityServiceRefreshMessage(
          _aiConnectivityStatus.message,
          _assetConnectivityStatus.message,
        ),
      );
    } catch (error) {
      _recordActivity(
        kind: AppActivityKind.serviceRefresh,
        title: copy.activityServiceRefreshFailedTitle,
        message: _safeStatusError(error),
      );
      rethrow;
    }
  }

  Future<void> _refreshAiServiceStatus() async {
    final AiApiConfig config = _aiApiConfig;
    if (config.baseUrl.trim().isEmpty || config.apiKey.trim().isEmpty) {
      _availableAiModels = <AiModel>[];
      _aiModelLoadState = AiModelLoadState.idle;
      _aiModelLoadError = null;
      _aiConnectivityStatus = ConnectivityStatus(
        state: ConnectivityState.failure,
        message: '未配置 AI 服务',
        checkedAt: DateTime.now(),
      );
      notifyListeners();
      return;
    }

    try {
      final List<AiModel> models = await refreshAiModels(
        persistSelection: true,
      );
      if (models.isEmpty) {
        _aiConnectivityStatus = ConnectivityStatus(
          state: ConnectivityState.failure,
          message: '模型列表为空',
          checkedAt: DateTime.now(),
        );
      } else if (!hasSelectedAiModel) {
        _aiConnectivityStatus = ConnectivityStatus(
          state: ConnectivityState.warning,
          message: '接口可用，请选择模型',
          checkedAt: DateTime.now(),
        );
      } else {
        final AiHealthResult health = await _aiService.checkConnection(config);
        _aiConnectivityStatus = ConnectivityStatus(
          state: health.success
              ? ConnectivityState.success
              : ConnectivityState.failure,
          message: health.success
              ? 'AI 服务与聊天接口正常'
              : '聊天接口失败: ${_safeStatusError(health.message)}',
          checkedAt: DateTime.now(),
        );
      }
    } catch (error) {
      _aiConnectivityStatus = ConnectivityStatus(
        state: ConnectivityState.failure,
        message: 'AI 服务失败: ${_safeStatusError(error)}',
        checkedAt: DateTime.now(),
      );
    }
    notifyListeners();
  }

  String _safeStatusError(Object error) {
    return AiErrorPresentation.from(error, language: _language).message;
  }

  String _streamFailureReason(
    BoardGameAiStreamEvent event, {
    String? fallback,
  }) {
    final String value = (event.errorMessage ?? fallback ?? '').trim();
    if (value.isEmpty) {
      return _language == AppLanguage.zhHans
          ? '服务暂时不可用'
          : 'The service is temporarily unavailable';
    }
    if (value.startsWith('模型不可用') ||
        value.startsWith('服务商暂时不可用') ||
        value.startsWith('网络请求超时') ||
        value.startsWith('网络连接不可用') ||
        value.startsWith('鉴权失败') ||
        value.startsWith('服务返回格式无法解析')) {
      return value;
    }
    return AiErrorPresentation.from(value, language: _language).message;
  }

  int _runAttemptCount(_ChatGenerationState generation) {
    int attempts = 1;
    for (final AiRunEvent event in generation.runEvents) {
      final int reported = event.attempt ?? 0;
      if (reported > attempts) attempts = reported;
    }
    return attempts;
  }

  String _failureNotice(
    String base, {
    required String reason,
    required int attempts,
    List<String> progressLines = const <String>[],
    bool partialOutputRetained = false,
  }) {
    final String attemptText = _language == AppLanguage.zhHans
        ? '尝试 $attempts 次'
        : 'Attempted $attempts time${attempts == 1 ? '' : 's'}';
    final String reasonText = _language == AppLanguage.zhHans
        ? '失败原因：$reason'
        : 'Reason: $reason';
    final List<String> lines = <String>['$base\n$reasonText · $attemptText'];
    if (partialOutputRetained) {
      lines.add(
        _language == AppLanguage.zhHans
            ? '已保留已生成的部分答案，可点击重试继续。'
            : 'The generated partial answer was kept. Retry to continue.',
      );
    }
    if (progressLines.isNotEmpty) {
      lines.add(
        '${_language == AppLanguage.zhHans ? '已确认进度：' : 'Confirmed progress:'}\n'
        '${progressLines.join('\n')}',
      );
    }
    return lines.join('\n');
  }

  /// Builds user-readable progress from validated stage results only.
  ///
  /// Raw JSON, tool arguments and partial structured output are intentionally
  /// excluded. This preserves useful work after a failed run without making
  /// an unvalidated intermediate response look like an answer. The summary
  /// line is followed by every validated source and citation detail so a
  /// failed run does not hide work that was already confirmed.
  List<String> _confirmedProgressLines(
    _ChatGenerationState generation, {
    AiRunResult? runResult,
  }) {
    final List<AiStageResult> stageResults = <AiStageResult>[];
    if (runResult != null) {
      stageResults.addAll(runResult.stages);
    }
    if (stageResults.isEmpty) {
      for (final AiRunEvent event in generation.runEvents) {
        final AiStageResult? result = event.stageResult;
        if (event.type != AiRunEventType.stageCompleted || result == null) {
          continue;
        }
        stageResults.add(result);
      }
    }

    final Map<String, AiStageResult> latestByStage = <String, AiStageResult>{
      for (final AiStageResult result in stageResults) result.stageId: result,
    };
    final List<String> lines = <String>[];
    void addLine(String value) {
      final String normalized = value.trimRight();
      if (normalized.isNotEmpty && !lines.contains(normalized)) {
        lines.add(normalized);
      }
    }

    for (final AiStageResult result in latestByStage.values) {
      final String label = _progressStageLabel(result.stageId);
      final int inspected = result.inspectedSources.length;
      final int citations = result.citations.length;
      switch (result.status) {
        case AiStageStatus.answered:
          addLine(
            citations > 0
                ? _language == AppLanguage.zhHans
                      ? '$label：已确认 $citations 条依据'
                      : '$label: $citations verified references'
                : _language == AppLanguage.zhHans
                ? '$label：已得到阶段结果'
                : '$label: stage result confirmed',
          );
        case AiStageStatus.insufficient:
          addLine(
            _language == AppLanguage.zhHans
                ? '$label：已检查 $inspected 份资料，未找到可直接引用的内容'
                : '$label: checked $inspected source(s), no directly citable result',
          );
        case AiStageStatus.unavailable:
          addLine(
            _language == AppLanguage.zhHans
                ? '$label：资料暂时不可用'
                : '$label: sources were temporarily unavailable',
          );
        case AiStageStatus.skipped:
          addLine(
            _language == AppLanguage.zhHans
                ? '$label：按当前知识范围跳过'
                : '$label: skipped by the active knowledge scope',
          );
        case AiStageStatus.failed:
        case AiStageStatus.incomplete:
        case AiStageStatus.cancelled:
          if (inspected == 0 && citations == 0) continue;
          addLine(
            citations > 0
                ? _language == AppLanguage.zhHans
                      ? '$label：阶段未完成，但已确认 $citations 条依据'
                      : '$label: incomplete, but $citations references were verified'
                : _language == AppLanguage.zhHans
                ? '$label：阶段未完成，但已保留 $inspected 份已检查资料'
                : '$label: incomplete, but $inspected inspected source(s) were kept',
          );
      }

      // Keep the compact stage summary, then expose every confirmed item.
      // These are already validated RuleCitation values, never raw provider
      // payloads or unparsed structured output.
      final bool canDescribeInspectedSources =
          result.status != AiStageStatus.unavailable &&
          result.status != AiStageStatus.skipped;
      if (canDescribeInspectedSources && result.inspectedSources.isNotEmpty) {
        addLine(
          _language == AppLanguage.zhHans
              ? '$label：已检查 ${result.inspectedSources.length} 份资料'
              : '$label: checked ${result.inspectedSources.length} source(s)',
        );
        for (final RuleCitation citation in result.inspectedSources) {
          for (final String detail in _confirmedCitationLines(
            citation,
            confirmed: false,
          )) {
            addLine('  $detail');
          }
        }
      }
      if (result.citations.isNotEmpty) {
        for (int index = 0; index < result.citations.length; index++) {
          final RuleCitation citation = result.citations[index];
          final List<String> citationLines = _confirmedCitationLines(
            citation,
            confirmed: true,
            index: index + 1,
          );
          for (final String detail in citationLines) {
            addLine('  $detail');
          }
        }
      }
    }
    return List<String>.unmodifiable(lines);
  }

  /// Formats only fields that were supplied by a validated [RuleCitation].
  ///
  /// A source can be inspected without becoming a citation, so both kinds of
  /// detail are retained. Missing title/page/section/quote fields are omitted
  /// rather than replaced with guessed values.
  List<String> _confirmedCitationLines(
    RuleCitation citation, {
    required bool confirmed,
    int? index,
  }) {
    final List<String> lines = <String>[];
    final String title = citation.title?.trim() ?? '';
    final String path = citation.path?.trim() ?? '';
    final String? label = title.isNotEmpty
        ? title
        : path.isNotEmpty
        ? path.substring(path.lastIndexOf(RegExp(r'[\\/]')) + 1)
        : null;
    final String prefix = confirmed
        ? _language == AppLanguage.zhHans
              ? '已确认依据${index == null ? '' : ' $index'}'
              : 'Verified basis${index == null ? '' : ' $index'}'
        : _language == AppLanguage.zhHans
        ? '已检查资料'
        : 'Inspected source';
    if (label != null && label.isNotEmpty) {
      lines.add('$prefix：$label');
    } else {
      // A source ID is an internal join key, not a user-facing citation.
      // Keep the confirmed item visible without leaking that identifier.
      lines.add(prefix);
    }
    final String section = citation.section?.trim() ?? '';
    if (section.isNotEmpty) {
      lines.add(
        _language == AppLanguage.zhHans ? '章节：$section' : 'Section: $section',
      );
    }
    if (citation.page != null) {
      lines.add(
        _language == AppLanguage.zhHans
            ? '页码：第 ${citation.page} 页'
            : 'Page: ${citation.page}',
      );
    }
    final String quote = citation.quote?.trim() ?? '';
    if (quote.isNotEmpty) {
      lines.add(
        _language == AppLanguage.zhHans ? '引用：$quote' : 'Quote: $quote',
      );
    }
    final Uri? uri = Uri.tryParse(citation.url?.trim() ?? '');
    if (uri != null && uri.host.isNotEmpty) {
      lines.add(
        _language == AppLanguage.zhHans
            ? '来源：${uri.host}'
            : 'Domain: ${uri.host}',
      );
    }
    return lines;
  }

  String _progressStageLabel(String stageId) => switch (stageId) {
    'official' => _language == AppLanguage.zhHans ? '官方资料' : 'Official sources',
    'community' =>
      _language == AppLanguage.zhHans ? '社区资料' : 'Community sources',
    'web' => _language == AppLanguage.zhHans ? '联网搜索' : 'Web search',
    'general' ||
    'fallback' ||
    'answering' => _language == AppLanguage.zhHans ? '回答整理' : 'Answer drafting',
    _ => _language == AppLanguage.zhHans ? '阶段 $stageId' : 'Stage $stageId',
  };

  Future<void> prefetchHomeImages() async {
    final imagePaths = <String>{
      for (final game in games) ...[
        game.coverAssetPath,
        game.bannerAssetPath,
        ...game.galleryAssetPaths,
      ],
    }.toList();

    _homeAssetsLoading = imagePaths.isNotEmpty;
    _homeAssetsLoaded = 0;
    _homeAssetsTotal = imagePaths.length;
    notifyListeners();

    for (final String path in imagePaths) {
      await _cacheImage(path);
      _homeAssetsLoaded += 1;
      notifyListeners();
    }

    _homeAssetsLoading = false;
    notifyListeners();
  }

  /// Loads the persisted index first, then checks the authoritative WebDAV
  /// manifests in the background. A single in-flight request is shared by all
  /// callers so opening the page and pressing refresh cannot race each other.
  /// Existing cached rows stay visible while this network request runs.
  Future<void> refreshLibraryResources({bool force = false}) {
    final Future<void>? active = _libraryRefreshFuture;
    if (active != null) {
      return active;
    }

    final int generation = ++_libraryRefreshGeneration;
    // Only a cold start without any local index should occupy the content
    // area with a spinner. Refresh-button callers can force a network check,
    // but still keep already-rendered rows in place.
    if (_libraryResources.isEmpty) {
      _libraryLoadState = LibraryLoadState.loading;
      _libraryLoadError = null;
      notifyListeners();
    } else if (force) {
      _libraryLoadError = null;
      notifyListeners();
    }

    final Future<void> future = _refreshLibraryResources(generation);
    _libraryRefreshFuture = future;
    future
        .whenComplete(() {
          if (identical(_libraryRefreshFuture, future)) {
            _libraryRefreshFuture = null;
          }
        })
        .catchError((Object _) {});
    return future;
  }

  Future<void> _refreshLibraryResources(int generation) async {
    await _ensureLibraryCacheLoaded();
    if (generation != _libraryRefreshGeneration) {
      return;
    }

    // Cache loading can provide the first visible rows when this method is
    // called before AppController.initialize() has completed.
    if (_libraryResources.isNotEmpty &&
        _libraryLoadState == LibraryLoadState.loading) {
      _libraryLoadState = LibraryLoadState.success;
      notifyListeners();
    }

    try {
      final _RemoteLibraryIndexResult index = await _loadRemoteLibraryIndex();
      if (generation != _libraryRefreshGeneration) {
        return;
      }

      final List<DesktopLibraryResource> remoteResources =
          _localizeLibraryResources(index.resources);
      final List<DesktopLibraryResource> nextResources =
          _mergePartialLibraryResources(remoteResources, index.failedSlugs);
      final bool changed = !_sameLibraryIndex(_libraryResources, nextResources);
      if (changed || _libraryResources.isEmpty) {
        _libraryResources = nextResources;
        try {
          await _preferencesService.saveDesktopLibraryResources(
            _libraryResources,
          );
        } catch (error) {
          // A persistence failure must not turn a successful remote request
          // into a false network failure. The next launch can retry caching.
          debugPrint(
            '[assets] desktop library index cache write failed: $error',
          );
        }
      }
      _libraryLoadState = index.resources.isEmpty
          ? LibraryLoadState.empty
          : LibraryLoadState.success;
      _libraryLoadError = index.warning;
      if (index.failedSlugs.isNotEmpty && index.warning != null) {
        _recordLibraryLoadFailure(index.warning!);
      }
    } catch (error) {
      if (generation != _libraryRefreshGeneration) {
        return;
      }
      if (_libraryResources.isEmpty) {
        _libraryResources = _buildBundledLibraryResources();
      }
      _libraryLoadState = LibraryLoadState.failure;
      _libraryLoadError = _safeStatusError(error);
      _recordLibraryLoadFailure(_libraryLoadError!);
      debugPrint('[assets] desktop library index unavailable: $error');
    }
    notifyListeners();
  }

  /// Restores only index metadata. The actual PDF/Markdown/HTML bytes remain
  /// in [RemoteAssetService]'s document cache and are never read here.
  Future<void> _ensureLibraryCacheLoaded() {
    if (_libraryCacheLoadAttempted) {
      return Future<void>.value();
    }
    final Future<void>? active = _libraryCacheLoadFuture;
    if (active != null) {
      return active;
    }

    final Future<void> future = () async {
      try {
        final List<DesktopLibraryResource> cached = await _preferencesService
            .loadDesktopLibraryResources();
        if (cached.isNotEmpty) {
          _libraryResources = _localizeLibraryResources(cached);
          _libraryLoadState = LibraryLoadState.success;
        }
      } catch (error) {
        debugPrint('[assets] desktop library index cache read failed: $error');
      } finally {
        _libraryCacheLoadAttempted = true;
      }
    }();
    _libraryCacheLoadFuture = future;
    return future.whenComplete(() {
      if (identical(_libraryCacheLoadFuture, future)) {
        _libraryCacheLoadFuture = null;
      }
    });
  }

  List<DesktopLibraryResource> _localizeLibraryResources(
    Iterable<DesktopLibraryResource> resources,
  ) {
    final Map<String, GameInfo> gamesBySlug = <String, GameInfo>{
      for (final GameInfo game in _games) game.slug: game,
    };
    return resources
        .map(
          (DesktopLibraryResource resource) => resource.copyWith(
            gameTitle:
                gamesBySlug[resource.gameSlug]?.title ?? resource.gameTitle,
            type: _normalizeLibraryResourceType(resource.type),
          ),
        )
        .toList(growable: false);
  }

  void _refreshLibraryGameTitles() {
    if (_libraryResources.isEmpty) {
      return;
    }
    _libraryResources = _localizeLibraryResources(_libraryResources);
  }

  DesktopLibraryResourceType _normalizeLibraryResourceType(
    DesktopLibraryResourceType type,
  ) {
    switch (type) {
      case DesktopLibraryResourceType.rulebook:
        return DesktopLibraryResourceType.rulebook;
      case DesktopLibraryResourceType.faq:
        return DesktopLibraryResourceType.faq;
      case DesktopLibraryResourceType.assetIndex:
      case DesktopLibraryResourceType.reference:
      case DesktopLibraryResourceType.playerAid:
      case DesktopLibraryResourceType.supplement:
      case DesktopLibraryResourceType.other:
        return DesktopLibraryResourceType.other;
    }
  }

  bool _sameLibraryIndex(
    List<DesktopLibraryResource> left,
    List<DesktopLibraryResource> right,
  ) {
    if (left.length != right.length) {
      return false;
    }
    final Map<String, DesktopLibraryResource> leftByPath =
        <String, DesktopLibraryResource>{
          for (final DesktopLibraryResource resource in left)
            resource.remotePath: resource,
        };
    final Map<String, DesktopLibraryResource> rightByPath =
        <String, DesktopLibraryResource>{
          for (final DesktopLibraryResource resource in right)
            resource.remotePath: resource,
        };
    if (leftByPath.length != rightByPath.length) {
      return false;
    }
    for (final String path in leftByPath.keys) {
      final DesktopLibraryResource? a = leftByPath[path];
      final DesktopLibraryResource? b = rightByPath[path];
      if (a == null ||
          b == null ||
          a.id != b.id ||
          a.gameSlug != b.gameSlug ||
          a.title != b.title ||
          a.language != b.language ||
          a.typeCode != b.typeCode ||
          a.formatCode != b.formatCode ||
          a.isRemote != b.isRemote ||
          a.status != b.status ||
          a.enabled != b.enabled ||
          a.sourceClass != b.sourceClass) {
        return false;
      }
    }
    return true;
  }

  List<DesktopLibraryResource> _mergePartialLibraryResources(
    List<DesktopLibraryResource> remoteResources,
    Set<String> failedSlugs,
  ) {
    if (failedSlugs.isEmpty || _libraryResources.isEmpty) {
      return remoteResources;
    }
    final Set<String> remotePaths = <String>{
      for (final DesktopLibraryResource resource in remoteResources)
        resource.remotePath,
    };
    final List<DesktopLibraryResource> merged = <DesktopLibraryResource>[
      ...remoteResources,
      for (final DesktopLibraryResource resource in _libraryResources)
        if (failedSlugs.contains(resource.gameSlug) &&
            remotePaths.add(resource.remotePath))
          resource,
    ];
    merged.sort(_compareLibraryResources);
    return List<DesktopLibraryResource>.unmodifiable(merged);
  }

  /// Reads the authoritative per-game `manifest.json` files from WebDAV.
  ///
  /// A manifest is small metadata, not a document download. The actual PDF or
  /// Markdown bytes are fetched only when the user opens or downloads one
  /// resource. The remote catalog is used only to discover games that are not
  /// present in the bundled catalog yet.
  Future<_RemoteLibraryIndexResult> _loadRemoteLibraryIndex() async {
    final List<String> slugs = await _remoteLibraryGameSlugs();
    if (slugs.isEmpty) {
      throw StateError('远端资料库没有可检查的游戏资料');
    }

    final List<DesktopLibraryResource> resources = <DesktopLibraryResource>[];
    final List<String> failedSlugs = <String>[];
    int loadedManifestCount = 0;

    await Future.wait<void>(
      slugs.map((String slug) async {
        final String path = 'assets/games/$slug/manifest.json';
        try {
          final String? source = await _remoteAssetService.fetchRemoteText(
            sources: _assetSourceConfigs,
            remotePath: path,
          );
          if (source == null || source.trim().isEmpty) {
            failedSlugs.add(slug);
            return;
          }
          final Map<String, dynamic> manifest =
              jsonDecode(source) as Map<String, dynamic>;
          resources.addAll(_parseRemoteManifestResources(slug, manifest));
          loadedManifestCount += 1;
        } catch (error) {
          failedSlugs.add(slug);
          debugPrint('[assets] manifest unavailable for $slug: $error');
        }
      }),
    );

    if (loadedManifestCount == 0) {
      // If a legacy remote library has no manifests, retain the existing
      // bounded directory walk as a compatibility fallback.
      final List<RemoteAssetFile> files = await _remoteAssetService
          .listFilesRecursively(
            sources: _assetSourceConfigs,
            remotePath: 'assets/games',
          );
      final List<DesktopLibraryResource> fallback =
          _buildRemoteLibraryResources(files);
      if (fallback.isEmpty) {
        throw StateError('远端资料库为空或格式不可识别');
      }
      return _RemoteLibraryIndexResult(
        resources: fallback,
        warning: '远端未提供标准 manifest，已使用目录清单。',
      );
    }

    final Map<String, DesktopLibraryResource> unique =
        <String, DesktopLibraryResource>{};
    for (final DesktopLibraryResource resource in resources) {
      unique[resource.remotePath] = resource;
    }
    final List<DesktopLibraryResource> normalized = unique.values.toList()
      ..sort(_compareLibraryResources);
    final String? warning = failedSlugs.isEmpty
        ? null
        : '已有 $loadedManifestCount 个游戏资料同步，${failedSlugs.length} 个资料暂不可用。';
    return _RemoteLibraryIndexResult(
      resources: List<DesktopLibraryResource>.unmodifiable(normalized),
      warning: warning,
      failedSlugs: Set<String>.unmodifiable(failedSlugs),
    );
  }

  Future<List<String>> _remoteLibraryGameSlugs() async {
    final Set<String> slugs = <String>{
      for (final GameInfo game in _games) game.slug,
    };
    try {
      final String? source = await _remoteAssetService.fetchRemoteText(
        sources: _assetSourceConfigs,
        remotePath: 'assets/catalog.json',
      );
      if (source != null && source.trim().isNotEmpty) {
        final Map<String, dynamic> catalog =
            jsonDecode(source) as Map<String, dynamic>;
        final List<dynamic> games =
            catalog['games'] as List<dynamic>? ?? const <dynamic>[];
        for (final dynamic entry in games) {
          if (entry is! Map<String, dynamic> || entry['enabled'] == false) {
            continue;
          }
          final String? slug = entry['slug'] as String?;
          if (slug != null && _isSafeGameSlug(slug)) {
            slugs.add(slug);
          }
        }
      }
    } catch (error) {
      debugPrint(
        '[assets] remote catalog unavailable for library index: $error',
      );
    }
    final List<String> sorted = slugs.toList();
    sorted.sort();
    return sorted;
  }

  bool _isSafeGameSlug(String slug) {
    return slug.isNotEmpty && RegExp(r'^[a-z0-9][a-z0-9_-]*$').hasMatch(slug);
  }

  List<DesktopLibraryResource> _parseRemoteManifestResources(
    String slug,
    Map<String, dynamic> manifest,
  ) {
    final GameInfo? localGame = _games
        .where((GameInfo game) => game.slug == slug)
        .cast<GameInfo?>()
        .firstWhere((GameInfo? game) => game != null, orElse: () => null);
    final String gameTitle =
        localGame?.title ?? _remoteManifestTitle(manifest, slug);
    final List<dynamic> entries =
        manifest['resources'] as List<dynamic>? ?? const <dynamic>[];
    final List<DesktopLibraryResource> resources = <DesktopLibraryResource>[];

    for (final dynamic raw in entries) {
      if (raw is! Map<String, dynamic>) {
        continue;
      }
      final String relativePath = (raw['path'] as String? ?? '')
          .replaceAll('\\', '/')
          .replaceFirst(RegExp(r'^/+'), '')
          .trim();
      final String status = (raw['status'] as String? ?? 'unknown').trim();
      if (relativePath.isEmpty ||
          relativePath.split('/').contains('..') ||
          relativePath.startsWith('/') ||
          !_isDisplayableManifestStatus(status) ||
          raw['enabled'] == false) {
        continue;
      }
      // The resource-management skill explicitly excludes unclassified raw
      // material from runtime reading, caching, and download operations.
      final String relativeLower = relativePath.toLowerCase();
      if (relativeLower.startsWith('docs/others/')) {
        continue;
      }
      if (!relativePath.startsWith('docs/')) {
        continue;
      }

      final String remotePath = 'assets/games/$slug/$relativePath';
      final String documentType = raw['documentType'] as String? ?? '';
      final String languageCode = raw['language'] as String? ?? '';
      final String sourceClass = raw['sourceClass'] as String? ?? 'unknown';
      resources.add(
        DesktopLibraryResource(
          id: (raw['id'] as String?)?.trim().isNotEmpty == true
              ? raw['id'] as String
              : 'remote:$remotePath',
          gameSlug: slug,
          gameTitle: gameTitle,
          remotePath: remotePath,
          title: _libraryResourceTitle(
            relativePath,
            documentType: documentType,
          ),
          language: _libraryResourceLanguage(
            relativePath,
            explicitCode: languageCode,
          ),
          type: _libraryResourceType(relativePath, documentType: documentType),
          format: _libraryResourceFormat(relativePath),
          isRemote: true,
          status: status,
          enabled: raw['enabled'] as bool? ?? true,
          sourceClass: sourceClass,
        ),
      );
    }
    return resources;
  }

  String _remoteManifestTitle(Map<String, dynamic> manifest, String slug) {
    final Map<String, dynamic>? game = manifest['game'] is Map<String, dynamic>
        ? manifest['game'] as Map<String, dynamic>
        : null;
    final Map<String, dynamic>? titles = game?['title'] is Map<String, dynamic>
        ? game!['title'] as Map<String, dynamic>
        : null;
    final String? localized =
        titles?['cn'] as String? ??
        titles?['zhHans'] as String? ??
        titles?['en'] as String?;
    return localized?.trim().isNotEmpty == true ? localized!.trim() : slug;
  }

  List<DesktopLibraryResource> _buildRemoteLibraryResources(
    List<RemoteAssetFile> files,
  ) {
    final Map<String, GameInfo> gamesBySlug = <String, GameInfo>{
      for (final GameInfo game in _games) game.slug: game,
    };
    final Map<String, DesktopLibraryResource> unique =
        <String, DesktopLibraryResource>{};

    for (final RemoteAssetFile file in files) {
      final String normalized = file.remotePath
          .replaceAll('\\', '/')
          .replaceFirst(RegExp(r'^/+'), '');
      final RegExpMatch? match = RegExp(
        r'^assets/games/([^/]+)/docs/(.+)$',
      ).firstMatch(normalized);
      if (match == null) {
        continue;
      }
      final String relative = match.group(2)!;
      final String lower = normalized.toLowerCase();
      final String relativeLower = relative.toLowerCase();
      if (lower.contains('/tmp/') ||
          relativeLower.startsWith('.') ||
          relativeLower.startsWith('others/')) {
        continue;
      }

      final String slug = match.group(1)!;
      final GameInfo? game = gamesBySlug[slug];
      final String gameTitle = game == null ? slug : game.title;
      final DesktopLibraryResource resource = DesktopLibraryResource(
        id: 'remote:$normalized',
        gameSlug: slug,
        gameTitle: gameTitle,
        remotePath: normalized,
        title: _libraryResourceTitle(relative),
        language: _libraryResourceLanguage(relative),
        type: _libraryResourceType(relative),
        format: _libraryResourceFormat(relative),
        isRemote: true,
      );
      unique[normalized] = resource;
    }

    final List<DesktopLibraryResource> resources = unique.values.toList();
    resources.sort(_compareLibraryResources);
    return List<DesktopLibraryResource>.unmodifiable(resources);
  }

  List<DesktopLibraryResource> _buildBundledLibraryResources() {
    final List<DesktopLibraryResource> resources = <DesktopLibraryResource>[];
    final Set<String> paths = <String>{};
    int fallbackIndex = 0;

    for (final GameInfo game in _games) {
      final List<String> candidates = <String>[
        game.rulebookAssetPath,
        game.faqAssetPath,
        ...game.knowledgeAssetPaths,
      ];
      for (final String path in candidates) {
        final String normalized = path.replaceAll('\\', '/').trim();
        if (normalized.isEmpty || !paths.add(normalized)) {
          continue;
        }
        final bool isRulebook = path == game.rulebookAssetPath;
        final bool isFaq = path == game.faqAssetPath;
        final String relative = normalized.contains('/docs/')
            ? normalized.split('/docs/').last
            : normalized.split('/').last;
        resources.add(
          DesktopLibraryResource(
            // Keep the first two compatibility ids stable for existing
            // desktop automation while remote entries use their full path.
            id: '$fallbackIndex',
            gameSlug: game.slug,
            gameTitle: game.title,
            remotePath: normalized,
            title: _libraryResourceTitle(
              relative,
              documentType: isRulebook
                  ? 'rulebook'
                  : isFaq
                  ? 'faq'
                  : null,
            ),
            language: _libraryResourceLanguage(relative),
            type: _libraryResourceType(
              relative,
              documentType: isRulebook
                  ? 'rulebook'
                  : isFaq
                  ? 'faq'
                  : null,
            ),
            format: _libraryResourceFormat(relative),
            isRemote: false,
          ),
        );
        fallbackIndex += 1;
      }
    }
    return List<DesktopLibraryResource>.unmodifiable(resources);
  }

  DesktopLibraryResourceType _libraryResourceType(
    String path, {
    String? documentType,
  }) {
    final String explicit = documentType?.trim().toLowerCase() ?? '';
    switch (explicit) {
      case 'rulebook':
      case 'how_to_play':
        return DesktopLibraryResourceType.rulebook;
      case 'faq':
      case 'ruling':
      case 'errata':
        return DesktopLibraryResourceType.faq;
      case 'asset_index':
      case 'rules_reference':
      case 'supplement':
      case 'variant':
      case 'campaign_guide':
      case 'scenario_book':
        return DesktopLibraryResourceType.other;
      case 'player_aid':
      case 'player-aid':
      case 'playeraid':
      case 'aid':
      case 'quick_reference':
        return DesktopLibraryResourceType.playerAid;
    }

    final String lower = path.toLowerCase();
    if (lower.contains('faq') ||
        lower.contains('answer') ||
        lower.contains('ruling') ||
        lower.contains('errata')) {
      return DesktopLibraryResourceType.faq;
    }
    if (lower.contains('player_aid') ||
        lower.contains('player-aid') ||
        lower.contains('quick_reference')) {
      return DesktopLibraryResourceType.playerAid;
    }
    if (lower.contains('reference')) {
      return DesktopLibraryResourceType.other;
    }
    if (lower.contains('rulebook') ||
        lower.contains('how_to_play') ||
        lower.contains('learn_to_play') ||
        lower.endsWith('rules_official_page.html') ||
        lower.endsWith('rules_official_page.htm')) {
      return DesktopLibraryResourceType.rulebook;
    }
    return DesktopLibraryResourceType.other;
  }

  DesktopLibraryResourceFormat _libraryResourceFormat(String path) {
    final String lower = path.toLowerCase();
    final int dot = lower.lastIndexOf('.');
    final String extension = dot < 0 ? '' : lower.substring(dot + 1);
    switch (extension) {
      case 'md':
      case 'markdown':
        return DesktopLibraryResourceFormat.markdown;
      case 'pdf':
        return DesktopLibraryResourceFormat.pdf;
      case 'html':
      case 'htm':
        return DesktopLibraryResourceFormat.html;
      case 'txt':
        return DesktopLibraryResourceFormat.text;
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'webp':
        return DesktopLibraryResourceFormat.image;
      default:
        return DesktopLibraryResourceFormat.other;
    }
  }

  String _libraryResourceLanguage(String path, {String? explicitCode}) {
    final String explicit = explicitCode?.trim().toLowerCase() ?? '';
    if (explicit == 'cn' ||
        explicit == 'zh' ||
        explicit == 'zh-cn' ||
        explicit == 'zh-hans' ||
        explicit == 'z_hans') {
      return '中文';
    }
    if (explicit == 'en' || explicit == 'en-us' || explicit == 'en-gb') {
      return '英文';
    }
    if (explicit == 'multi' || explicit == 'mixed') {
      return '多语言';
    }
    if (explicit == 'none' || explicit == 'unknown') {
      return '未标注';
    }

    final String lower = path.toLowerCase();
    if (RegExp(r'(^|[_\-.])(zh|cn|z[_-]?hans)([_\-.]|$)').hasMatch(lower) ||
        lower.contains('/zh/')) {
      return '中文';
    }
    if (RegExp(r'(^|[_\-.])en([_\-.]|$)').hasMatch(lower) ||
        lower.contains('/en/')) {
      return '英文';
    }
    return '未标注';
  }

  String _libraryResourceTitle(String path, {String? documentType}) {
    final String normalized = path.replaceAll('\\', '/');
    final String fileName = normalized.split('/').last;
    final int dot = fileName.lastIndexOf('.');
    final String stem = dot <= 0 ? fileName : fileName.substring(0, dot);
    final DesktopLibraryResourceType type = _libraryResourceType(
      path,
      documentType: documentType,
    );
    switch (type) {
      case DesktopLibraryResourceType.rulebook:
        return '规则书';
      case DesktopLibraryResourceType.faq:
        return 'FAQ';
      case DesktopLibraryResourceType.assetIndex:
        return '资料索引';
      case DesktopLibraryResourceType.reference:
        return '规则参考';
      case DesktopLibraryResourceType.playerAid:
        return '玩家辅助';
      case DesktopLibraryResourceType.supplement:
        return '补充资料';
      case DesktopLibraryResourceType.other:
        return stem.replaceAll(RegExp(r'[_-]+'), ' ').trim();
    }
  }

  bool _isDisplayableManifestStatus(String status) {
    switch (status.trim().toLowerCase()) {
      case 'available':
      case 'unverified':
      case 'needs_review':
      case 'unknown':
        return true;
      case 'missing':
      case 'superseded':
      case 'blocked':
        return false;
      default:
        // Newer manifest versions may add a non-terminal status. Keep it
        // visible rather than silently hiding a resource the server can list.
        return true;
    }
  }

  int _compareLibraryResources(
    DesktopLibraryResource left,
    DesktopLibraryResource right,
  ) {
    final int game = left.gameTitle.compareTo(right.gameTitle);
    if (game != 0) return game;
    final int type = left.type.index.compareTo(right.type.index);
    if (type != 0) return type;
    return left.remotePath.compareTo(right.remotePath);
  }

  Future<ResolvedDocument?> resolveLibraryResource(
    DesktopLibraryResource resource,
  ) async {
    if (!resource.canOpen) {
      return null;
    }
    if (!resource.isRemote) {
      final GameInfo? game = _games
          .where((GameInfo item) => item.slug == resource.gameSlug)
          .cast<GameInfo?>()
          .firstWhere((GameInfo? item) => item != null, orElse: () => null);
      if (game != null &&
          resource.type == DesktopLibraryResourceType.rulebook) {
        return resolveRulebookDocument(game);
      }
      if (game != null && resource.type == DesktopLibraryResourceType.faq) {
        return resolveFaqDocument(game);
      }
      return ResolvedDocument(
        remotePath: resource.remotePath,
        renderType: _documentRenderTypeForFormat(resource.format),
        label: resource.title,
      );
    }

    final String? localPath = await cacheDocument(resource.remotePath);
    if (localPath == null) {
      return null;
    }
    return ResolvedDocument(
      remotePath: resource.remotePath,
      renderType: _documentRenderTypeForFormat(resource.format),
      label: resource.title,
    );
  }

  DocumentRenderType _documentRenderTypeForFormat(
    DesktopLibraryResourceFormat format,
  ) {
    switch (format) {
      case DesktopLibraryResourceFormat.pdf:
        return DocumentRenderType.pdf;
      case DesktopLibraryResourceFormat.html:
        return DocumentRenderType.html;
      case DesktopLibraryResourceFormat.text:
        return DocumentRenderType.text;
      case DesktopLibraryResourceFormat.image:
        return DocumentRenderType.image;
      case DesktopLibraryResourceFormat.markdown:
        return DocumentRenderType.markdown;
      case DesktopLibraryResourceFormat.other:
        return DocumentRenderType.text;
    }
  }

  Future<String?> downloadLibraryResource({
    required DesktopLibraryResource resource,
    required String directoryPath,
  }) async {
    if (kIsWeb || directoryPath.trim().isEmpty) {
      return null;
    }
    final CachedAsset? cached = await _remoteAssetService.ensureCached(
      sources: _assetSourceConfigs,
      remotePath: resource.remotePath,
      forceRefresh: true,
      allowCachedFallback: false,
    );
    if (cached == null || !cached.exists) {
      return null;
    }
    final File source = File(cached.localPath);
    if (!await source.exists()) {
      return null;
    }

    final Directory directory = Directory(directoryPath.trim());
    await directory.create(recursive: true);
    final String fileName = _downloadFileName(resource);
    if (fileName.isEmpty) {
      return null;
    }
    final File destination = File(
      '${directory.path}${Platform.pathSeparator}$fileName',
    );
    if (source.absolute.path.toLowerCase() ==
        destination.absolute.path.toLowerCase()) {
      return destination.path;
    }
    await source.copy(destination.path);
    return destination.path;
  }

  String _safeDownloadFileName(String fileName) {
    final String sanitized = fileName
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceFirst(RegExp(r'[ .]+$'), '')
        .trim();
    return sanitized.isEmpty ? 'library-resource' : sanitized;
  }

  /// Builds the user-facing download name from the same localized metadata
  /// shown in the desktop library card instead of exposing the WebDAV stem.
  ///
  /// The resource list may have been loaded before the user switched language,
  /// so the current [GameInfo] is resolved by slug at download time. This
  /// keeps the file name in sync with the language currently displayed by the
  /// app without requiring another remote index request.
  String _downloadFileName(DesktopLibraryResource resource) {
    final GameInfo? game = _games
        .where((GameInfo item) => item.slug == resource.gameSlug)
        .cast<GameInfo?>()
        .firstWhere((GameInfo? item) => item != null, orElse: () => null);
    final String gameTitle =
        (game?.title.trim().isNotEmpty == true
                ? game!.title
                : resource.gameTitle)
            .trim();
    final String resourceTitle = _localizedLibraryResourceTitle(resource);
    final String extension = _fileExtension(resource.fileName);
    final String stem = gameTitle.isEmpty
        ? resourceTitle
        : '$gameTitle · $resourceTitle';
    return _safeDownloadFileName('$stem$extension');
  }

  String _localizedLibraryResourceTitle(DesktopLibraryResource resource) {
    final bool isChinese = _language == AppLanguage.zhHans;
    switch (resource.type) {
      case DesktopLibraryResourceType.rulebook:
        return isChinese ? '规则书' : 'Rulebook';
      case DesktopLibraryResourceType.faq:
        return 'FAQ';
      case DesktopLibraryResourceType.assetIndex:
        return isChinese ? '资料索引' : 'Asset index';
      case DesktopLibraryResourceType.reference:
        return isChinese ? '规则参考' : 'Rules reference';
      case DesktopLibraryResourceType.playerAid:
        return isChinese ? '玩家辅助' : 'Player aid';
      case DesktopLibraryResourceType.supplement:
        return isChinese ? '补充资料' : 'Supplement';
      case DesktopLibraryResourceType.other:
        final String fallback = resource.title.trim();
        return fallback.isEmpty ? (isChinese ? '资料' : 'Resource') : fallback;
    }
  }

  String _fileExtension(String fileName) {
    final String normalized = fileName.trim();
    final int dot = normalized.lastIndexOf('.');
    if (dot <= 0 || dot == normalized.length - 1) {
      return '';
    }
    return normalized.substring(dot);
  }

  Future<void> _initializeRemoteLibrary() async {
    try {
      await refreshLibraryResources();
      // Warm the image cache first so the update probe has a stable baseline
      // and cannot race with the version manifest writes performed by
      // ensureCached().
      await prefetchHomeImages();
      await refreshAssetAccessStatus();
      await checkForLibraryUpdates();
    } catch (error, stackTrace) {
      debugPrint('[updates] initial remote library warm-up failed: $error');
      debugPrint('$stackTrace');
    } finally {
      _startAssetStatusPolling();
    }
  }

  Future<void> checkForLibraryUpdates({bool forcePromptReset = false}) async {
    if (_checkingLibraryUpdate) {
      return;
    }

    _checkingLibraryUpdate = true;
    if (forcePromptReset) {
      _libraryUpdatePromptSeen = false;
    }
    notifyListeners();

    try {
      debugPrint('[updates] checkForLibraryUpdates started');
      final List<String> changedPaths = <String>[];
      final Set<String> changedGameTitles = <String>{};
      const String catalogPath = 'assets/catalog.json';
      final List<AssetSourceConfig> sourcesForCheck = _preferredUpdateSources();
      debugPrint(
        '[updates] sourcesForCheck: ${sourcesForCheck.map((s) => s.id).join(', ')}',
      );
      final String? remoteCatalogSource = await _remoteAssetService
          .fetchRemoteText(sources: sourcesForCheck, remotePath: catalogPath);
      final String localCatalogSource = await _gameManifestService
          .loadCatalogSource(remoteAssetService: _remoteAssetService);
      debugPrint(
        '[updates] remote catalog fetched: ${remoteCatalogSource != null} len=${remoteCatalogSource?.length ?? 0}',
      );
      debugPrint('[updates] local catalog len=${localCatalogSource.length}');
      if (remoteCatalogSource != null &&
          _normalizeSource(remoteCatalogSource) !=
              _normalizeSource(localCatalogSource)) {
        changedPaths.add(catalogPath);
        changedGameTitles.addAll(
          await _diffCatalogGameTitles(remoteCatalogSource),
        );
        debugPrint('[updates] catalog changed');
        final List<String> titles = changedGameTitles.toList()..sort();
        _setPendingLibraryUpdate(
          RemoteLibraryUpdate(
            changedPaths: changedPaths,
            changedGameTitles: titles,
          ),
        );
        debugPrint('[updates] pending update titles: ${titles.join(', ')}');
        return;
      } else {
        debugPrint('[updates] catalog unchanged');
      }

      final Iterable<String> assetPaths = _trackedRemotePaths().toSet();
      for (final String remotePath in assetPaths) {
        if (remotePath == catalogPath) {
          continue;
        }
        final bool changed = await _remoteAssetService.hasRemoteChanged(
          sources: sourcesForCheck,
          remotePath: remotePath,
        );
        if (changed) {
          changedPaths.add(remotePath);
          final String? title = _gameTitleForRemotePath(remotePath);
          if (title != null) {
            changedGameTitles.add(title);
          }
          debugPrint('[updates] changed path: $remotePath');
        }
      }

      if (changedPaths.isNotEmpty) {
        final List<String> titles = changedGameTitles.toList()..sort();
        _setPendingLibraryUpdate(
          RemoteLibraryUpdate(
            changedPaths: changedPaths,
            changedGameTitles: titles,
          ),
        );
        debugPrint('[updates] pending update titles: ${titles.join(', ')}');
      } else {
        debugPrint('[updates] no remote library updates detected');
      }
    } catch (error, stackTrace) {
      debugPrint('[updates] checkForLibraryUpdates failed: $error');
      debugPrint('$stackTrace');
    } finally {
      _checkingLibraryUpdate = false;
      notifyListeners();
    }
  }

  Future<void> applyPendingLibraryUpdate() async {
    final RemoteLibraryUpdate? pending = _pendingLibraryUpdate;
    if (pending == null || _applyingLibraryUpdate) {
      return;
    }

    _applyingLibraryUpdate = true;
    notifyListeners();

    try {
      for (final String remotePath in pending.changedPaths) {
        debugPrint('[updates] applying update for: $remotePath');
        await _remoteAssetService.ensureCached(
          sources: _assetSourceConfigs,
          remotePath: remotePath,
          forceRefresh: true,
          allowCachedFallback: false,
        );
      }

      _resolvedAssetPaths.clear();
      _games = await _loadGamesForLanguage(_language);
      _selectedGameId = _resolveSelectedGameId(_selectedGameId);
      _pendingLibraryUpdate = null;
      _libraryUpdatePromptSeen = false;
      await prefetchHomeImages();
      debugPrint('[updates] apply complete');
    } finally {
      _applyingLibraryUpdate = false;
      notifyListeners();
    }
  }

  void dismissPendingLibraryUpdatePrompt() {
    _libraryUpdatePromptSeen = true;
    notifyListeners();
  }

  bool shouldShowLibraryUpdatePrompt() {
    return _pendingLibraryUpdate != null && !_libraryUpdatePromptSeen;
  }

  Future<List<String>> _diffCatalogGameTitles(
    String remoteCatalogSource,
  ) async {
    try {
      final remoteCatalog = GameCatalogManifest.fromJson(
        jsonDecode(remoteCatalogSource) as Map<String, dynamic>,
      );
      final GameCatalogManifest localCatalog = await _gameManifestService
          .loadBundledCatalogManifest();

      final Map<String, GameCatalogEntry> localEntries =
          <String, GameCatalogEntry>{
            for (final entry in localCatalog.games) entry.slug: entry,
          };
      final Map<String, GameCatalogEntry> remoteEntries =
          <String, GameCatalogEntry>{
            for (final entry in remoteCatalog.games) entry.slug: entry,
          };

      final Set<String> changedSlugs = <String>{};
      for (final String slug in remoteEntries.keys) {
        final local = localEntries[slug];
        final remote = remoteEntries[slug];
        if (remote == null) {
          continue;
        }
        if (local == null) {
          changedSlugs.add(slug);
          continue;
        }
        if (local.enabled != remote.enabled || local.order != remote.order) {
          changedSlugs.add(slug);
        }
      }
      debugPrint(
        '[updates] changed slugs from catalog diff: ${changedSlugs.join(', ')}',
      );

      final List<String> titles = <String>[];
      for (final String slug in changedSlugs) {
        final String? title = await _titleForSlug(slug);
        if (title != null) {
          titles.add(title);
        }
      }
      return titles;
    } catch (_) {
      return <String>[];
    }
  }

  Future<String?> _titleForSlug(String slug) async {
    final GameInfo? local = _games
        .where((game) => game.slug == slug)
        .cast<GameInfo?>()
        .firstWhere((game) => game != null, orElse: () => null);
    if (local != null) {
      return _composeDisplayTitle(local.title, local.subtitle);
    }

    try {
      final String source = await _gameManifestService.loadManifestSource(
        remotePath: 'assets/games/$slug/game.json',
        remoteAssetService: _remoteAssetService,
        sources: _assetSourceConfigs,
      );
      final GameManifest manifest = GameManifest.fromJson(
        jsonDecode(source) as Map<String, dynamic>,
      );
      final GameInfo info = manifest.toGameInfo(_language);
      return _composeDisplayTitle(info.title, info.subtitle);
    } catch (_) {
      return slug;
    }
  }

  String? _gameTitleForRemotePath(String remotePath) {
    final RegExpMatch? match = RegExp(
      r'assets/games/([^/]+)/',
    ).firstMatch(remotePath);
    if (match == null) {
      return null;
    }
    final String slug = match.group(1)!;
    final GameInfo? game = _games
        .where((item) => item.slug == slug)
        .cast<GameInfo?>()
        .firstWhere((item) => item != null, orElse: () => null);
    if (game == null) {
      return slug;
    }
    return _composeDisplayTitle(game.title, game.subtitle);
  }

  String _composeDisplayTitle(String title, String subtitle) {
    final String normalizedTitle = title.trim();
    final String normalizedSubtitle = subtitle.trim();
    if (normalizedTitle.isEmpty) {
      return normalizedSubtitle;
    }
    if (normalizedSubtitle.isEmpty ||
        normalizedSubtitle.toLowerCase() == normalizedTitle.toLowerCase()) {
      return normalizedTitle;
    }
    return '$normalizedTitle / $normalizedSubtitle';
  }

  String _normalizeSource(String source) {
    return source.replaceAll('\r\n', '\n').trim();
  }

  Future<String?> cacheDocument(String remotePath) async {
    if (remotePath.trim().isEmpty || isOtherStoragePath(remotePath)) {
      return null;
    }

    CachedAsset? cached;
    try {
      cached = await _remoteAssetService.ensureCached(
        sources: _assetSourceConfigs,
        remotePath: remotePath,
      );
    } catch (_) {
      cached = null;
    }
    if (cached == null) {
      _assetConnectivityStatus = ConnectivityStatus(
        state: ConnectivityState.failure,
        message: '文档暂时不可用',
        checkedAt: DateTime.now(),
      );
      notifyListeners();
      return null;
    }
    _resolvedAssetPaths[remotePath] = cached.localPath;
    _assetConnectivityStatus = ConnectivityStatus(
      state: ConnectivityState.success,
      message: '文档已缓存',
      checkedAt: DateTime.now(),
    );
    notifyListeners();
    return cached.localPath;
  }

  Future<String?> loadMarkdownDocument(String remotePath) async {
    return loadLibraryResourceText(remotePath);
  }

  Future<String?> loadLibraryResourceText(String remotePath) async {
    final String? localPath = await cacheDocument(remotePath);
    if (localPath == null) {
      if (remotePath.startsWith('assets/')) {
        try {
          return await rootBundle.loadString(remotePath);
        } catch (_) {
          return null;
        }
      }
      return null;
    }
    try {
      return await File(localPath).readAsString();
    } catch (_) {
      return null;
    }
  }

  Future<ResolvedDocument?> resolveRulebookDocument(GameInfo game) {
    return _resolveDocument(
      game: game,
      baseName: 'rulebook',
      fallbackRemotePath: game.rulebookAssetPath,
      fallbackLabel: copy.rulesBook,
    );
  }

  void _startRunPresentation(_ChatGenerationState generation) {
    final DateTime startedAt = DateTime.now();
    final String runId = 'client-${startedAt.microsecondsSinceEpoch}';
    generation
      ..runEvents.clear()
      ..runId = runId
      ..runStartedAt = startedAt
      ..runCompletedAt = null
      ..runStatus = null
      ..runSequence = 0
      ..runResult = null
      ..syntheticRun = true;
    _runExpandedByContext[generation.contextKey ?? ''] = true;
    _appendRunEvent(
      generation,
      AiRunEvent(
        runId: runId,
        sequence: generation.runSequence++,
        type: AiRunEventType.runStarted,
        timestamp: startedAt,
        contextKey: _conversationIdForContext(
          useGlobalMode: generation.useGlobalMode,
        ),
        model: _aiApiConfig.model,
      ),
    );
  }

  void _recordRunEvent(_ChatGenerationState generation, AiRunEvent event) {
    if (generation.syntheticRun && event.type == AiRunEventType.runStarted) {
      generation
        ..runEvents.clear()
        ..syntheticRun = false;
    }
    _appendRunEvent(generation, event);
    if (event.runResult != null) {
      generation.runResult = event.runResult;
    }
  }

  void _appendRunEvent(_ChatGenerationState generation, AiRunEvent event) {
    final bool duplicate = generation.runEvents.any(
      (AiRunEvent item) =>
          item.runId == event.runId &&
          item.sequence == event.sequence &&
          item.type == event.type,
    );
    if (duplicate) return;
    generation.runEvents.add(event);
    generation.runId = event.runId;
    if (event.type == AiRunEventType.runStarted) {
      generation.runStartedAt = event.timestamp;
    }
    final AiRunStatus? terminalStatus = _runStatusFromEvent(event);
    if (terminalStatus != null) {
      generation.runStatus = terminalStatus;
      generation.runCompletedAt = event.timestamp;
    }
  }

  void _recordSyntheticProgress(
    _ChatGenerationState generation,
    BoardGameAiStreamEvent event,
  ) {
    if (!generation.syntheticRun) return;
    if (event.status == 'routing') {
      _appendSyntheticStage(generation, 'routing');
    }
    if (event.delta.isNotEmpty || event.answer != null) {
      _appendSyntheticStage(generation, 'answering');
    }
  }

  void _appendSyntheticStage(_ChatGenerationState generation, String stageId) {
    final bool exists = generation.runEvents.any(
      (AiRunEvent event) =>
          event.stageId == stageId &&
          (event.type == AiRunEventType.stageStarted ||
              event.type == AiRunEventType.toolStarted),
    );
    if (exists) return;
    final DateTime timestamp = DateTime.now();
    _appendRunEvent(
      generation,
      AiRunEvent(
        runId: generation.runId!,
        sequence: generation.runSequence++,
        type: AiRunEventType.stageStarted,
        timestamp: timestamp,
        stageId: stageId,
        contextKey: generation.contextKey,
        model: _aiApiConfig.model,
      ),
    );
  }

  void _completeSyntheticAnswerStage(_ChatGenerationState generation) {
    if (!generation.syntheticRun) return;
    _appendSyntheticStage(generation, 'answering');
    final DateTime timestamp = DateTime.now();
    _appendRunEvent(
      generation,
      AiRunEvent(
        runId: generation.runId!,
        sequence: generation.runSequence++,
        type: AiRunEventType.stageCompleted,
        timestamp: timestamp,
        stageId: 'answering',
        contextKey: generation.contextKey,
        model: _aiApiConfig.model,
        stageResult: AiStageResult(
          stageId: 'answering',
          scope: const AiKnowledgeScope.general(),
          status: AiStageStatus.answered,
          model: _aiApiConfig.model,
          startedAt: generation.runStartedAt,
          completedAt: timestamp,
        ),
      ),
    );
  }

  void _finishRunPresentation(
    _ChatGenerationState generation,
    AiRunStatus status,
  ) {
    if (generation.runStatus != null && generation.runCompletedAt != null) {
      _persistRunCheckpoint(generation, generation.runStatus!);
      return;
    }
    if (generation.syntheticRun && status == AiRunStatus.completed) {
      _completeSyntheticAnswerStage(generation);
    }
    final DateTime completedAt = DateTime.now();
    generation
      ..runStatus = status
      ..runCompletedAt = completedAt;
    if (generation.contextKey != null) {
      _runExpandedByContext[generation.contextKey!] =
          status != AiRunStatus.completed;
    }
    if (!_hasTerminalRunEvent(generation)) {
      final AiRunEventType type = switch (status) {
        AiRunStatus.completed => AiRunEventType.completed,
        AiRunStatus.cancelled => AiRunEventType.cancelled,
        AiRunStatus.incomplete => AiRunEventType.incomplete,
        AiRunStatus.failed => AiRunEventType.failed,
      };
      _appendRunEvent(
        generation,
        AiRunEvent(
          runId:
              generation.runId ??
              'client-${completedAt.microsecondsSinceEpoch}',
          sequence: generation.runSequence++,
          type: type,
          timestamp: completedAt,
          contextKey: generation.contextKey,
          model: _aiApiConfig.model,
        ),
      );
    }
    _persistRunCheckpoint(generation, status);
  }

  void _persistRunCheckpoint(
    _ChatGenerationState generation,
    AiRunStatus status,
  ) {
    final String? conversationId = generation.contextKey;
    if (conversationId == null || conversationId.isEmpty) return;
    final AiConversation? conversation = _conversations[conversationId];
    if (conversation == null || generation.runEvents.isEmpty) return;
    final AiRunEvent terminal = generation.runEvents.lastWhere(
      (AiRunEvent event) =>
          event.type == AiRunEventType.completed ||
          event.type == AiRunEventType.failed ||
          event.type == AiRunEventType.incomplete ||
          event.type == AiRunEventType.cancelled,
      orElse: () => generation.runEvents.last,
    );
    final AiRunEvent first = generation.runEvents.first;
    final List<AiRunEvent> checkpointEvents = generation.runEvents
        .where((AiRunEvent event) => event.type != AiRunEventType.textDelta)
        .toList(growable: false);
    final List<AiRunEvent> boundedEvents = checkpointEvents.length <= 240
        ? checkpointEvents
        : checkpointEvents.sublist(checkpointEvents.length - 240);
    final AiRunCheckpoint checkpoint = AiRunCheckpoint(
      runId: generation.runId ?? first.runId,
      status: status,
      events: List<AiRunEvent>.unmodifiable(boundedEvents),
      responseId: terminal.responseId,
      sessionId: terminal.sessionId,
      contextKey: terminal.contextKey ?? conversationId,
      model: terminal.model ?? _aiApiConfig.model,
      startedAt: generation.runStartedAt ?? first.timestamp,
      completedAt: generation.runCompletedAt ?? terminal.timestamp,
      errorCode: terminal.errorCode,
      errorMessage: terminal.errorMessage,
    );
    conversation.lastRun = checkpoint;
    _queueConversationSave(conversationId: conversationId);
  }

  bool _hasTerminalRunEvent(_ChatGenerationState generation) {
    return generation.runEvents.any(
      (AiRunEvent event) =>
          event.type == AiRunEventType.completed ||
          event.type == AiRunEventType.failed ||
          event.type == AiRunEventType.incomplete ||
          event.type == AiRunEventType.cancelled,
    );
  }

  AiRunStatus? _runStatusFromEvent(AiRunEvent? event) {
    return switch (event?.type) {
      AiRunEventType.completed => AiRunStatus.completed,
      AiRunEventType.cancelled => AiRunStatus.cancelled,
      AiRunEventType.incomplete => AiRunStatus.incomplete,
      AiRunEventType.failed => AiRunStatus.failed,
      _ => null,
    };
  }

  Future<ResolvedDocument?> resolveFaqDocument(GameInfo game) {
    return _resolveDocument(
      game: game,
      baseName: 'faq',
      fallbackRemotePath: game.faqAssetPath,
      fallbackLabel: copy.faq,
    );
  }

  Future<String?> resolveImagePath(String remotePath) async {
    if (remotePath.trim().isEmpty || isOtherStoragePath(remotePath)) {
      return null;
    }
    try {
      return await _cacheImage(remotePath);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _cacheImage(String remotePath) async {
    if (remotePath.trim().isEmpty || isOtherStoragePath(remotePath)) {
      return null;
    }
    if (_resolvedAssetPaths.containsKey(remotePath)) {
      return _resolvedAssetPaths[remotePath];
    }
    final CachedAsset? cached = await _remoteAssetService.ensureCached(
      sources: _assetSourceConfigs,
      remotePath: remotePath,
    );
    if (cached == null) {
      return null;
    }
    _resolvedAssetPaths[remotePath] = cached.localPath;
    return cached.localPath;
  }

  Future<ResolvedDocument?> _resolveDocument({
    required GameInfo game,
    required String baseName,
    required String fallbackRemotePath,
    required String fallbackLabel,
  }) async {
    final String fallback = fallbackRemotePath.trim();
    final List<String> candidates = _documentCandidates(
      game: game,
      baseName: baseName,
    );
    if (candidates.isEmpty) {
      _assetConnectivityStatus = ConnectivityStatus(
        state: ConnectivityState.failure,
        message: '文档暂时不可用',
        checkedAt: DateTime.now(),
      );
      notifyListeners();
      return null;
    }

    for (final candidate in candidates) {
      CachedAsset? cached;
      try {
        cached = await _remoteAssetService.ensureCached(
          sources: _assetSourceConfigs,
          remotePath: candidate,
        );
      } catch (_) {
        cached = null;
      }
      if (cached != null) {
        _resolvedAssetPaths[candidate] = cached.localPath;
        _assetConnectivityStatus = ConnectivityStatus(
          state: ConnectivityState.success,
          message: '文档已缓存',
          checkedAt: DateTime.now(),
        );
        notifyListeners();
        return ResolvedDocument(
          remotePath: candidate,
          renderType: _documentRenderTypeForPath(candidate),
          label: fallbackLabel,
        );
      }
    }

    _assetConnectivityStatus = ConnectivityStatus(
      state: ConnectivityState.failure,
      message: '文档暂时不可用',
      checkedAt: DateTime.now(),
    );
    notifyListeners();
    if (fallback.isNotEmpty && !isOtherStoragePath(fallback)) {
      return ResolvedDocument(
        remotePath: fallback,
        renderType: _documentRenderTypeForPath(fallback),
        label: fallbackLabel,
      );
    }
    return null;
  }

  DocumentRenderType _documentRenderTypeForPath(String path) {
    final String normalized = path.toLowerCase();
    if (normalized.endsWith('.pdf')) return DocumentRenderType.pdf;
    if (normalized.endsWith('.html') || normalized.endsWith('.htm')) {
      return DocumentRenderType.html;
    }
    if (normalized.endsWith('.txt')) return DocumentRenderType.text;
    if (RegExp(r'\.(png|jpe?g|webp|gif|bmp)$').hasMatch(normalized)) {
      return DocumentRenderType.image;
    }
    return DocumentRenderType.markdown;
  }

  List<String> _documentCandidates({
    required GameInfo game,
    required String baseName,
  }) {
    final Set<String> documentTypes = baseName == 'rulebook'
        ? <String>{'rulebook', 'how_to_play'}
        : <String>{'faq'};
    final List<GameResource> resources = game.resources
        .where(
          (resource) =>
              documentTypes.contains(resource.documentType) &&
              resource.isAvailable &&
              resource.enabled &&
              !resource.isInOthersDirectory &&
              resource.isRenderableDocument &&
              resource.path.trim().isNotEmpty,
        )
        .toList();
    resources.sort((a, b) {
      if (baseName == 'rulebook') {
        final int documentFormat = _documentFormatRank(
          a,
        ).compareTo(_documentFormatRank(b));
        if (documentFormat != 0) return documentFormat;
      }
      final int language = _documentLanguageRank(
        a.language,
      ).compareTo(_documentLanguageRank(b.language));
      if (language != 0) return language;
      final int priority = a.priority.compareTo(b.priority);
      if (priority != 0) return priority;
      return a.id.compareTo(b.id);
    });

    final List<String> candidates = resources
        .map((resource) => resource.assetPathFor(game.slug))
        .toList();
    final String fallback = baseName == 'rulebook'
        ? game.rulebookAssetPath
        : game.faqAssetPath;
    if (fallback.trim().isNotEmpty &&
        !isOtherStoragePath(fallback) &&
        !candidates.contains(fallback)) {
      candidates.add(fallback);
    }
    return candidates;
  }

  int _documentFormatRank(GameResource resource) {
    if (resource.format == 'pdf' && resource.sourceClass == 'official') {
      return 0;
    }
    if (resource.format == 'pdf') {
      return 1;
    }
    return 2;
  }

  int _documentLanguageRank(String resourceLanguage) {
    final String normalized = resourceLanguage.toLowerCase();
    if (language == AppLanguage.zhHans) {
      if (normalized == 'cn' || normalized == 'zh' || normalized == 'zhhans') {
        return 0;
      }
      if (normalized == 'multi') return 1;
      if (normalized == 'en') return 2;
      return 3;
    }
    if (normalized == 'en') return 0;
    if (normalized == 'multi') return 1;
    if (normalized == 'cn' || normalized == 'zh' || normalized == 'zhhans') {
      return 2;
    }
    return 3;
  }

  Iterable<String> _trackedRemotePaths() sync* {
    final Set<String> paths = <String>{};
    void addPath(String path) {
      if (path.trim().isNotEmpty && !isOtherStoragePath(path)) {
        paths.add(path);
      }
    }

    for (final GameInfo game in _games) {
      addPath(game.coverAssetPath);
      addPath(game.bannerAssetPath);
      for (final String path in game.galleryAssetPaths) {
        addPath(path);
      }
      addPath(game.rulebookAssetPath);
      addPath(game.faqAssetPath);
      for (final GameResource resource in game.resources) {
        if (!resource.isInOthersDirectory) {
          addPath(resource.assetPathFor(game.slug));
        }
      }
      addPath('assets/games/${game.slug}/game.json');
      addPath('assets/games/${game.slug}/manifest.json');
    }
    yield* paths;
  }

  List<AssetSourceConfig> _preferredUpdateSources() {
    final List<AssetSourceConfig> successful = _assetSourceConfigs
        .where(
          (source) =>
              _assetSourceStatuses[source.id]?.state ==
              ConnectivityState.success,
        )
        .toList();
    if (successful.isNotEmpty) {
      return successful;
    }
    // At startup every source may still be unknown, and the first source is
    // not necessarily reachable. Try the full configured list so a healthy
    // fallback source can establish the update baseline.
    return List<AssetSourceConfig>.from(_assetSourceConfigs);
  }

  Future<List<GameInfo>> _loadGamesForLanguage(AppLanguage language) async {
    final manifests = await _gameManifestService.loadEnabledGames(
      remoteAssetService: _remoteAssetService,
      sources: _assetSourceConfigs,
      preferRemote: false,
    );
    return manifests.map((manifest) => manifest.toGameInfo(language)).toList();
  }

  String _resolveSelectedGameId(String preferredId) {
    if (_games.any((game) => game.id == preferredId)) {
      return preferredId;
    }
    if (_games.isNotEmpty) {
      return _games.first.id;
    }
    return preferredId;
  }

  void _startAssetStatusPolling() {
    _assetStatusTimer?.cancel();
    _assetStatusTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(refreshAssetAccessStatus());
    });
  }

  AiConversation _ensureConversationForContext({
    required bool useGlobalMode,
    String? gameId,
    String? greeting,
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
    final String title = useGlobalMode ? copy.globalAiTitle : '${game.title}助手';
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
    final String defaultGreeting = useGlobalMode
        ? copy.allKnowledgeGreeting
        : copy.assistantGreetingFor(
            game.title,
            game.assistantIntro.isNotEmpty ? game.assistantIntro : game.summary,
          );
    final AiConversation created = AiConversation(
      id: id,
      title: title,
      scope: useGlobalMode
          ? AiConversationScope.global
          : AiConversationScope.game,
      gameId: useGlobalMode ? null : game.id,
      createdAt: now,
      updatedAt: now,
      messages: <ChatMessage>[
        ChatMessage(
          id: '${now.microsecondsSinceEpoch}-${useGlobalMode ? 'global' : game.id}',
          role: ChatRole.assistant,
          text: greeting ?? defaultGreeting,
          timestamp: now,
        ),
      ],
    );
    _conversations[id] = created;
    _queueConversationSave(conversationId: id);
    return created;
  }

  void _refreshConversationMetadata() {
    for (final MapEntry<String, AiConversation> entry
        in _conversations.entries.toList()) {
      final AiConversation conversation = entry.value;
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
      final String title = '${game.title}助手';
      if (conversation.title != title) {
        _conversations[entry.key] = conversation.copyWith(title: title);
      }
    }
  }

  void _handleListeningStopped() {
    if (_isListening || _speechLevel != 0) {
      _isListening = false;
      _speechLevel = 0;
      notifyListeners();
    }
  }

  void _handleSpeechLevel(double level) {
    final double normalized = ((level + 2) / 12).clamp(0.05, 1.0).toDouble();
    if ((normalized - _speechLevel).abs() < 0.02) {
      return;
    }
    _speechLevel = normalized;
    notifyListeners();
  }

  static const String _globalConversationKey = 'global';
  static const int _conversationStoreVersion = 3;
  static const int _maxMessagesPerConversation = 100;

  String _conversationKeyForContext({required bool useGlobalMode}) {
    return useGlobalMode
        ? _globalConversationKey
        : _conversationKeyForGameId(selectedGame.id);
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
      final File file = await _conversationStoreFile();
      if (!await file.exists()) {
        return;
      }
      final Map<String, dynamic> json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final Map<String, dynamic> conversations =
          json['conversations'] as Map<String, dynamic>? ?? <String, dynamic>{};

      _conversations.clear();
      for (final MapEntry<String, dynamic> entry in conversations.entries) {
        final AiConversation? restored = _conversationFromStoredEntry(
          entry.key,
          entry.value,
        );
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
    } catch (error, stackTrace) {
      debugPrint('[chat] restore conversations failed: $error');
      debugPrint('$stackTrace');
    }
  }

  Future<void> _persistConversations() async {
    try {
      final File file = await _conversationStoreFile();
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
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(payload), flush: true);
    } catch (error, stackTrace) {
      debugPrint('[chat] persist conversations failed: $error');
      debugPrint('$stackTrace');
    }
  }

  Future<File> _conversationStoreFile() async {
    final Directory support = await getApplicationSupportDirectory();
    return File(
      '${support.path}${Platform.pathSeparator}chat_conversations.json',
    );
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
          : '${game.title}助手',
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
