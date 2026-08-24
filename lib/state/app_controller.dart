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
import '../models/cached_asset.dart';
import '../models/connectivity_status.dart';
import '../models/color_scheme_option.dart';
import '../models/game_info.dart';
import '../models/game_catalog_manifest.dart';
import '../models/remote_library_update.dart';
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
  String? _aiWorkflowStatus;
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
    state: ConnectivityState.success,
    message: '默认可用',
    checkedAt: DateTime.now(),
  );
  ConnectivityStatus _assetConnectivityStatus = ConnectivityStatus.unknown(
    '未检测',
  );
  final Map<String, ConnectivityStatus> _assetSourceStatuses =
      <String, ConnectivityStatus>{};
  final Map<String, String> _resolvedAssetPaths = <String, String>{};
  Timer? _assetStatusTimer;
  RemoteLibraryUpdate? _pendingLibraryUpdate;
  bool _checkingLibraryUpdate = false;
  bool _applyingLibraryUpdate = false;
  bool _libraryUpdatePromptSeen = false;
  bool _homeAssetsLoading = false;
  int _homeAssetsLoaded = 0;
  int _homeAssetsTotal = 0;
  Future<void> _conversationSaveQueue = Future<void>.value();
  final Map<String, List<ChatMessage>> _conversationMessages =
      <String, List<ChatMessage>>{};
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
  String? get aiWorkflowStatus => _aiWorkflowStatus;
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
  RemoteLibraryUpdate? get pendingLibraryUpdate => _pendingLibraryUpdate;
  bool get checkingLibraryUpdate => _checkingLibraryUpdate;
  bool get applyingLibraryUpdate => _applyingLibraryUpdate;
  bool get homeAssetsLoading => _homeAssetsLoading;
  int get homeAssetsLoaded => _homeAssetsLoaded;
  int get homeAssetsTotal => _homeAssetsTotal;
  String? resolvedAssetPath(String remotePath) =>
      _resolvedAssetPaths[remotePath];
  AppCopy get copy => AppCopy(_language);
  List<GameInfo> get games => List<GameInfo>.unmodifiable(_games);
  GameInfo get featuredGame => selectedGame;
  GameInfo get selectedGame => games.firstWhere(
    (game) => game.id == _selectedGameId,
    orElse: () => games.first,
  );
  UnmodifiableListView<ChatMessage> get messages =>
      UnmodifiableListView<ChatMessage>(_messagesForCurrentContext());
  UnmodifiableListView<ChatMessage> messagesForContext({
    required bool useGlobalMode,
  }) => UnmodifiableListView<ChatMessage>(
    _messagesForContext(useGlobalMode: useGlobalMode),
  );

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
    if (_isSaveableCustomPreset(_aiApiConfig)) {
      _customAiPresets = _upsertCustomPreset(_customAiPresets, _aiApiConfig);
      await _preferencesService.saveAiCustomPresets(_customAiPresets);
    }
    _assetSourceConfigs = await _preferencesService.loadAssetSourceConfigs();
    _games = await _loadGamesForLanguage(_language);
    _selectedGameId = _resolveSelectedGameId(_selectedGameId);
    await _restoreConversations();
    debugPrint(
      '[updates] initialize loaded games: ${_games.map((g) => '${g.slug}:${g.title}').join(', ')}',
    );
    _aiConnectivityStatus = ConnectivityStatus(
      state: ConnectivityState.success,
      message: copy.aiStatusDefaultReady,
      checkedAt: DateTime.now(),
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
    _ensureGreeting();
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
    await _preferencesService.saveLanguage(next);
    await _ttsService.setLanguage(next);
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
    if (_selectedGameId == gameId) {
      return;
    }
    _selectedGameId = gameId;
    notifyListeners();
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
    _queueConversationSave();
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

    final userMessage = ChatMessage(
      id: '${DateTime.now().microsecondsSinceEpoch}-user',
      role: ChatRole.user,
      text: trimmed,
      timestamp: DateTime.now(),
    );

    messages.add(userMessage);
    _trimConversationMessages(messages);
    _queueConversationSave();
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
        if (event.status != null) {
          _aiWorkflowStatus = event.status;
          notifyListeners();
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
              citations: finalAnswer?.citations ?? const <RuleCitation>[],
            ),
          );
        } else {
          messages.removeWhere((ChatMessage item) => item.id == draftId);
        }
        _trimConversationMessages(messages);
        _queueConversationSave();
      } else if (finalAnswer != null) {
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
        _queueConversationSave();
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
      _queueConversationSave();
    } finally {
      _generationAbort = null;
      _isSending = false;
      _aiWorkflowStatus = null;
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
      _queueConversationSave();
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
    await _speechService.cancelListening();
    await _ttsService.stop();
    _aiService.dispose();
    _assetTestClient.close();
  }

  Future<void> refreshAssetAccessStatus() async {
    ConnectivityStatus? bestStatus;
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
        if (bestStatus == null ||
            (status.state == ConnectivityState.success &&
                bestStatus.state != ConnectivityState.success)) {
          bestStatus = status;
        }
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
    _assetConnectivityStatus =
        bestStatus ??
        nextStatuses[_assetSourceConfigs.first.id] ??
        ConnectivityStatus.unknown('未检测');
    notifyListeners();
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

    bool anySuccess = false;
    for (final String path in imagePaths) {
      anySuccess = (await _cacheImage(path)) != null || anySuccess;
      _homeAssetsLoaded += 1;
      notifyListeners();
    }

    _homeAssetsLoading = false;
    _assetConnectivityStatus = ConnectivityStatus(
      state: anySuccess ? ConnectivityState.success : ConnectivityState.failure,
      message: anySuccess ? '首页资源已缓存' : '首页资源拉取失败',
      checkedAt: DateTime.now(),
    );
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
    if (_games.isEmpty) {
      return;
    }
    for (final GameInfo game in _games) {
      _conversationMessages.putIfAbsent(
        _conversationKeyForGameId(game.id),
        () => <ChatMessage>[
          ChatMessage(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            role: ChatRole.assistant,
            text: copy.assistantGreetingFor(
              game.title,
              game.assistantIntro.isNotEmpty
                  ? game.assistantIntro
                  : game.summary,
            ),
            timestamp: DateTime.now(),
          ),
        ],
      );
    }
    _conversationMessages.putIfAbsent(
      _globalConversationKey,
      () => <ChatMessage>[
        ChatMessage(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          role: ChatRole.assistant,
          text: copy.allKnowledgeGreeting,
          timestamp: DateTime.now(),
        ),
      ],
    );
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
  static const int _conversationStoreVersion = 1;
  static const int _maxMessagesPerConversation = 100;

  List<ChatMessage> _messagesForCurrentContext() {
    return _messagesForContext(useGlobalMode: false);
  }

  List<ChatMessage> _messagesForContext({required bool useGlobalMode}) {
    final String key = useGlobalMode
        ? _globalConversationKey
        : _conversationKeyForGameId(selectedGame.id);
    return _conversationMessages.putIfAbsent(key, () => <ChatMessage>[]);
  }

  String _conversationKeyForGameId(String gameId) => 'game:$gameId';

  void _trimConversationMessages(List<ChatMessage> messages) {
    if (messages.length <= _maxMessagesPerConversation) {
      return;
    }
    messages.removeRange(0, messages.length - _maxMessagesPerConversation);
  }

  void _queueConversationSave() {
    _conversationSaveQueue = _conversationSaveQueue
        .then((_) async {
          await _persistConversations();
        })
        .catchError((Object error, StackTrace stackTrace) {
          debugPrint('[chat] persist conversations failed: $error');
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

      _conversationMessages.clear();
      for (final MapEntry<String, dynamic> entry in conversations.entries) {
        final List<dynamic> rawMessages =
            entry.value as List<dynamic>? ?? const <dynamic>[];
        final List<ChatMessage> messages = rawMessages
            .whereType<Map<String, dynamic>>()
            .map(ChatMessage.fromMap)
            .toList();
        _trimConversationMessages(messages);
        if (messages.isNotEmpty) {
          _conversationMessages[entry.key] = messages;
        }
      }
      debugPrint(
        '[chat] restored conversations: ${_conversationMessages.keys.join(', ')}',
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
        'conversations': <String, dynamic>{
          for (final MapEntry<String, List<ChatMessage>> entry
              in _conversationMessages.entries)
            entry.key: entry.value.map((ChatMessage m) => m.toMap()).toList(),
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
}
