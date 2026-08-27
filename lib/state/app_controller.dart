import 'dart:collection';
import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:app_ai_client/app_ai_client.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:path_provider/path_provider.dart';

import '../models/ai_api_config.dart';
import '../models/ai_answer_mode.dart';
import '../models/answer_source.dart';
import '../models/assistant_mode.dart';
import '../models/asset_source_config.dart';
import '../models/app_language.dart';
import '../models/board_game_ai_answer.dart';
import '../models/chat_message.dart';
import '../models/ai_conversation.dart';
import '../models/cached_asset.dart';
import '../models/connectivity_status.dart';
import '../models/color_scheme_option.dart';
import '../models/game_info.dart';
import '../models/game_catalog_manifest.dart';
import '../models/remote_library_update.dart';
import '../models/resolved_document.dart';
import '../models/evidence_chunk.dart';
import '../services/ai_service.dart';
import '../services/preferences_service.dart';
import '../services/game_manifest_service.dart';
import '../services/remote_asset_service.dart';
import '../services/speech_service.dart';
import '../services/tts_service.dart';
import '../services/realtime_voice_service.dart';
import '../theme/app_palette.dart';
import '../theme/palette_registry.dart';
import '../ui/app_copy.dart';

enum AiModelLoadState { idle, loading, success, empty, failure }

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
  bool _isSending = false;
  String _selectedGameId = 'puerto-rico';
  AiAnswerMode _gameAnswerMode = AiAnswerMode.knowledgeOnly;
  AiAnswerMode _globalAnswerMode = AiAnswerMode.knowledgeThenDirect;
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
  final Map<String, AiConversation> _conversations = <String, AiConversation>{};
  String? _selectedConversationId;
  Completer<void>? _generationAbort;
  bool _generationWasStopped = false;
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
  bool get isSending => _isSending;
  bool get hasSelectedAiModel => _aiApiConfig.model.trim().isNotEmpty;
  AiAnswerMode get gameAnswerMode => _gameAnswerMode;
  AiAnswerMode get globalAnswerMode => _globalAnswerMode;
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
  bool get isRefreshingServiceStatuses => _serviceStatusRefreshFuture != null;
  String? get selectedConversationId => _selectedConversationId;
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
    _customAiPresets = await _preferencesService.loadAiCustomPresets();
    _aiApiConfig = await _preferencesService.loadAiApiConfig();
    _selectedConversationId = await _preferencesService
        .loadSelectedConversationId();
    if (_isSaveableCustomPreset(_aiApiConfig)) {
      _customAiPresets = _upsertCustomPreset(_customAiPresets, _aiApiConfig);
      await _preferencesService.saveAiCustomPresets(_customAiPresets);
    }
    _assetSourceConfigs = await _preferencesService.loadAssetSourceConfigs();
    _games = await _loadGamesForLanguage(_language);
    _selectedGameId = _resolveSelectedGameId(_selectedGameId);
    await _restoreConversations();
    _ensureGreeting();
    _selectedConversationId = _resolveSelectedConversationId(
      _selectedConversationId,
    );
    await _preferencesService.saveSelectedConversationId(
      _selectedConversationId!,
    );
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
    unawaited(prefetchHomeImages());
    _startAssetStatusPolling();
    unawaited(checkForLibraryUpdates());
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
    _selectedGameId = _resolveSelectedGameId(_selectedGameId);
    _ensureGreeting();
    _selectedConversationId = _resolveSelectedConversationId(
      _selectedConversationId,
    );
    await _preferencesService.saveSelectedConversationId(
      _selectedConversationId!,
    );
    await _preferencesService.saveLanguage(next);
    await _ttsService.setLanguage(next);
    notifyListeners();
  }

  Future<void> reloadGames() async {
    _games = await _loadGamesForLanguage(_language);
    _selectedGameId = _resolveSelectedGameId(_selectedGameId);
    _ensureGreeting();
    _selectedConversationId = _resolveSelectedConversationId(
      _selectedConversationId,
    );
    await _preferencesService.saveSelectedConversationId(
      _selectedConversationId!,
    );
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

  Future<void> saveAiApiConfig(AiApiConfig next) async {
    _aiApiConfig = next;
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
    notifyListeners();
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
          _aiModelLoadError = error.toString();
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

    final String message = '连接失败: ${result.message}';
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
    _selectedGameId = gameId;
    _selectConversationInternal(_conversationKeyForGameId(gameId));
    if (gameChanged || previousConversationId != _selectedConversationId) {
      notifyListeners();
    }
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

  Future<void> stopGenerating() async {
    if (!_isSending) {
      return;
    }
    _generationWasStopped = true;
    final Completer<void>? abort = _generationAbort;
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
    await _ttsService.stop();
    _trimConversationMessages(messages);
    _queueConversationSave(conversationId: conversationId);
    notifyListeners();
  }

  Future<void> sendPrompt(String prompt, {bool useGlobalMode = false}) async {
    final trimmed = prompt.trim();
    if (trimmed.isEmpty || _isSending) {
      return;
    }
    if (_aiApiConfig.model.trim().isEmpty) {
      _aiConnectivityStatus = ConnectivityStatus(
        state: ConnectivityState.failure,
        message: copy.aiApiModelRequired,
        checkedAt: DateTime.now(),
      );
      notifyListeners();
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
    _isSending = true;
    _generationWasStopped = false;
    final Completer<void> generationAbort = Completer<void>();
    _generationAbort = generationAbort;
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

    final GameInfo game = featuredGame;
    final AiAnswerMode answerMode = chatAnswerMode(
      useGlobalMode: useGlobalMode,
    );
    debugPrint(
      '[chat] send prompt game=${game.slug} global=$useGlobalMode mode=${answerMode.code}',
    );

    try {
      BoardGameAiAnswer? finalAnswer;
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
        abortTrigger: generationAbort.future,
      )) {
        if (_generationWasStopped) {
          break;
        }
        if (event.delta.isNotEmpty) {
          _replaceMessage(
            messages,
            draftMessage.copyWith(
              text:
                  '${_messageById(messages, draftId)?.text ?? ''}${event.delta}',
            ),
          );
          notifyListeners();
        }
        if (event.answer != null) {
          finalAnswer = event.answer;
        }
      }

      final ChatMessage? currentDraft = _messageById(messages, draftId);
      if (_generationWasStopped) {
        if (currentDraft != null && currentDraft.text.trim().isNotEmpty) {
          _replaceMessage(
            messages,
            currentDraft.copyWith(
              state: ChatMessageState.complete,
              source: finalAnswer?.source ?? AnswerSource.generalAdvice,
              evidence: finalAnswer?.evidence ?? const <EvidenceChunk>[],
            ),
          );
        } else {
          messages.removeWhere((ChatMessage item) => item.id == draftId);
        }
        _trimConversationMessages(messages);
        _queueConversationSave(conversationId: conversationId);
      } else if (finalAnswer != null) {
        final BoardGameAiAnswer answer = finalAnswer;
        final ChatMessage nextMessage = (currentDraft ?? draftMessage).copyWith(
          text: answer.text,
          source: answer.source,
          evidence: answer.evidence,
          state: ChatMessageState.complete,
          canRetry: false,
          retryPrompt: null,
        );
        _replaceMessage(messages, nextMessage);
        _trimConversationMessages(messages);
        _queueConversationSave(conversationId: conversationId);
        if (_voiceReplyEnabled) {
          await speakMessage(answer.text);
        }
      } else {
        throw StateError('The AI stream ended without an answer.');
      }
    } catch (error, stackTrace) {
      debugPrint('[chat] sendPrompt failed: $error');
      debugPrint('$stackTrace');
      if (_generationWasStopped) {
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
        _replaceMessage(
          messages,
          ChatMessage(
            id: draftId,
            role: ChatRole.assistant,
            text: copy.aiReplyFailed,
            timestamp: DateTime.now(),
            state: ChatMessageState.failed,
            canRetry: true,
            retryPrompt: trimmed,
          ),
        );
      }
      _trimConversationMessages(messages);
      _queueConversationSave(conversationId: conversationId);
    } finally {
      _generationAbort = null;
      _isSending = false;
      notifyListeners();
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
        _isSending) {
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
    _generationWasStopped = true;
    final Completer<void>? generationAbort = _generationAbort;
    if (generationAbort != null && !generationAbort.isCompleted) {
      generationAbort.complete();
    }
    await _conversationSaveQueue;
    await _selectedConversationSaveQueue;
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

    await Future.wait<void>(<Future<void>>[
      _refreshAiServiceStatus(),
      refreshAssetAccessStatus(),
    ]);
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
              : '聊天接口失败: ${health.message}',
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
    final String message = error.toString().trim();
    if (message.isEmpty) return '未知错误';
    final String apiKey = _aiApiConfig.apiKey.trim();
    if (apiKey.isEmpty) return message;
    return message.replaceAll(apiKey, '<redacted>');
  }

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
        _pendingLibraryUpdate = RemoteLibraryUpdate(
          changedPaths: changedPaths,
          changedGameTitles: titles,
        );
        _libraryUpdatePromptSeen = false;
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
        _pendingLibraryUpdate = RemoteLibraryUpdate(
          changedPaths: changedPaths,
          changedGameTitles: titles,
        );
        _libraryUpdatePromptSeen = false;
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
    final CachedAsset? cached = await _remoteAssetService.ensureCached(
      sources: _assetSourceConfigs,
      remotePath: remotePath,
    );
    if (cached == null) {
      _assetConnectivityStatus = ConnectivityStatus(
        state: ConnectivityState.failure,
        message: '文档下载失败',
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
    final String? localPath = await cacheDocument(remotePath);
    if (localPath == null) {
      return null;
    }
    return File(localPath).readAsString();
  }

  Future<ResolvedDocument?> resolveRulebookDocument(GameInfo game) {
    return _resolveDocument(
      game: game,
      baseName: 'rulebook',
      fallbackRemotePath: game.rulebookAssetPath,
      fallbackLabel: copy.rulesBook,
    );
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
    return _cacheImage(remotePath);
  }

  Future<String?> _cacheImage(String remotePath) async {
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
    final List<String> candidates = _documentCandidates(
      game: game,
      baseName: baseName,
    );
    for (final candidate in candidates) {
      final CachedAsset? cached = await _remoteAssetService.ensureCached(
        sources: _assetSourceConfigs,
        remotePath: candidate,
      );
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
          renderType: candidate.endsWith('.pdf')
              ? DocumentRenderType.pdf
              : DocumentRenderType.markdown,
          label: fallbackLabel,
        );
      }
    }

    _assetConnectivityStatus = ConnectivityStatus(
      state: ConnectivityState.failure,
      message: '文档下载失败',
      checkedAt: DateTime.now(),
    );
    notifyListeners();
    return ResolvedDocument(
      remotePath: fallbackRemotePath,
      renderType: fallbackRemotePath.endsWith('.pdf')
          ? DocumentRenderType.pdf
          : DocumentRenderType.markdown,
      label: fallbackLabel,
    );
  }

  List<String> _documentCandidates({
    required GameInfo game,
    required String baseName,
  }) {
    final String docsRoot = 'assets/games/${game.slug}/docs';
    final bool isChinese = language == AppLanguage.zhHans;
    final List<String> localized = isChinese
        ? <String>[
            '$docsRoot/${baseName}_official_zh.pdf',
            '$docsRoot/${baseName}_official_en.pdf',
            '$docsRoot/${baseName}_zh.md',
            '$docsRoot/${baseName}_en.md',
          ]
        : <String>[
            '$docsRoot/${baseName}_official_en.pdf',
            '$docsRoot/${baseName}_official_zh.pdf',
            '$docsRoot/${baseName}_en.md',
            '$docsRoot/${baseName}_zh.md',
          ];

    // Keep compatibility with already uploaded irregular names.
    if (baseName == 'faq') {
      localized.insert(0, '$docsRoot/faq_official_v25_en.pdf');
    }
    return localized;
  }

  Iterable<String> _trackedRemotePaths() sync* {
    for (final GameInfo game in _games) {
      yield game.coverAssetPath;
      yield game.bannerAssetPath;
      for (final String path in game.galleryAssetPaths) {
        yield path;
      }
      yield game.rulebookAssetPath;
      yield game.faqAssetPath;
      for (final String path in game.knowledgeAssetPaths) {
        yield path;
      }
      for (final String path in _documentCandidates(
        game: game,
        baseName: 'rulebook',
      )) {
        yield path;
      }
      for (final String path in _documentCandidates(
        game: game,
        baseName: 'faq',
      )) {
        yield path;
      }
      yield 'assets/games/${game.slug}/game.json';
    }
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
    if (_assetSourceConfigs.isNotEmpty) {
      return <AssetSourceConfig>[_assetSourceConfigs.first];
    }
    return <AssetSourceConfig>[];
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
    unawaited(refreshAssetAccessStatus());
    _assetStatusTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(refreshAssetAccessStatus());
    });
  }

  void _ensureGreeting() {
    final DateTime now = DateTime.now();
    for (final GameInfo game in _games) {
      final String id = _conversationKeyForGameId(game.id);
      final AiConversation? existing = _conversations[id];
      final String title = '${game.title}助手';
      if (existing == null) {
        _conversations[id] = AiConversation(
          id: id,
          title: title,
          scope: AiConversationScope.game,
          gameId: game.id,
          createdAt: now,
          updatedAt: now,
          messages: <ChatMessage>[
            ChatMessage(
              id: '${now.microsecondsSinceEpoch}-${game.id}',
              role: ChatRole.assistant,
              text: copy.assistantGreetingFor(
                game.title,
                game.assistantIntro.isNotEmpty
                    ? game.assistantIntro
                    : game.summary,
              ),
              timestamp: now,
            ),
          ],
        );
      } else if (existing.title != title || existing.gameId != game.id) {
        _conversations[id] = existing.copyWith(
          title: title,
          scope: AiConversationScope.game,
          gameId: game.id,
        );
      }
    }
    final AiConversation? existingGlobal =
        _conversations[_globalConversationKey];
    if (existingGlobal == null) {
      _conversations[_globalConversationKey] = AiConversation(
        id: _globalConversationKey,
        title: copy.globalAiTitle,
        scope: AiConversationScope.global,
        createdAt: now,
        updatedAt: now,
        messages: <ChatMessage>[
          ChatMessage(
            id: '${now.microsecondsSinceEpoch}-global',
            role: ChatRole.assistant,
            text: copy.allKnowledgeGreeting,
            timestamp: now,
          ),
        ],
      );
    } else if (existingGlobal.title != copy.globalAiTitle) {
      _conversations[_globalConversationKey] = existingGlobal.copyWith(
        title: copy.globalAiTitle,
        scope: AiConversationScope.global,
        gameId: null,
      );
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
  static const int _conversationStoreVersion = 2;
  static const int _maxMessagesPerConversation = 100;

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
    _ensureGreeting();
    final AiConversation? ensured = _conversations[key];
    if (ensured != null) {
      return ensured.messages;
    }
    final DateTime now = DateTime.now();
    final AiConversation fallback = AiConversation(
      id: key,
      title: useGlobalMode ? copy.globalAiTitle : '${selectedGame.title}助手',
      scope: useGlobalMode
          ? AiConversationScope.global
          : AiConversationScope.game,
      gameId: useGlobalMode ? null : selectedGame.id,
      createdAt: now,
      updatedAt: now,
    );
    _conversations[key] = fallback;
    return fallback.messages;
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
        if (restored != null) {
          _conversations[entry.key] = restored;
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
    // The v1 store represented conversations as bare message lists. Keep an
    // empty (but structurally valid) list during migration as well: the
    // greeting/session bootstrap runs after restore and can populate it, while
    // dropping the entry here would lose its stable session identity and
    // selected-session preference.
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
      messages: messages,
    );
  }

  String _resolveSelectedConversationId(String? preferredId) {
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
    final String gameConversationId = _conversationKeyForGameId(
      _selectedGameId,
    );
    if (_conversations.containsKey(gameConversationId)) {
      return gameConversationId;
    }
    if (_conversations.containsKey(_globalConversationKey)) {
      return _globalConversationKey;
    }
    return gameConversationId;
  }
}
