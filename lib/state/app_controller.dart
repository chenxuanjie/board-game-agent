import 'dart:collection';
import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../models/ai_api_config.dart';
import '../models/asset_source_config.dart';
import '../models/app_language.dart';
import '../models/chat_message.dart';
import '../models/cached_asset.dart';
import '../models/connectivity_status.dart';
import '../models/color_scheme_option.dart';
import '../models/game_info.dart';
import '../services/ai_service.dart';
import '../services/preferences_service.dart';
import '../services/remote_asset_service.dart';
import '../services/speech_service.dart';
import '../services/tts_service.dart';
import '../theme/app_palette.dart';
import '../theme/palette_registry.dart';
import '../ui/app_copy.dart';
import '../ui/game_catalog.dart';

class AppController extends ChangeNotifier {
  AppController({
    required PreferencesService preferencesService,
    required AiService aiService,
    required RemoteAssetService remoteAssetService,
    required SpeechService speechService,
    required TtsService ttsService,
  }) : _preferencesService = preferencesService,
       _aiService = aiService,
       _remoteAssetService = remoteAssetService,
       _speechService = speechService,
       _ttsService = ttsService;

  final PreferencesService _preferencesService;
  final AiService _aiService;
  final RemoteAssetService _remoteAssetService;
  final SpeechService _speechService;
  final TtsService _ttsService;

  AppLanguage _language = AppLanguage.zhHans;
  ColorSchemeOption _colorScheme = ColorSchemeOption.classic;
  bool _voiceReplyEnabled = true;
  bool _speechAvailable = false;
  bool _isListening = false;
  bool _isSending = false;
  String _selectedGameId = 'puerto-rico';
  AiApiConfig _aiApiConfig = AiApiConfig.defaultMimo;
  List<AssetSourceConfig> _assetSourceConfigs = AssetSourceConfig.defaults;
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
  final List<ChatMessage> _messages = <ChatMessage>[];
  late final http.Client _assetTestClient = IOClient(
    HttpClient()
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true,
  );

  AppLanguage get language => _language;
  ColorSchemeOption get colorScheme => _colorScheme;
  AppPalette get palette => PaletteRegistry.of(_colorScheme);
  bool get voiceReplyEnabled => _voiceReplyEnabled;
  bool get speechAvailable => _speechAvailable;
  bool get isListening => _isListening;
  bool get isSending => _isSending;
  AiApiConfig get aiApiConfig => _aiApiConfig;
  List<AssetSourceConfig> get assetSourceConfigs =>
      List<AssetSourceConfig>.unmodifiable(_assetSourceConfigs);
  ConnectivityStatus get aiConnectivityStatus => _aiConnectivityStatus;
  ConnectivityStatus get assetConnectivityStatus => _assetConnectivityStatus;
  Map<String, ConnectivityStatus> get assetSourceStatuses =>
      Map<String, ConnectivityStatus>.unmodifiable(_assetSourceStatuses);
  String? resolvedAssetPath(String remotePath) => _resolvedAssetPaths[remotePath];
  AppCopy get copy => AppCopy(_language);
  List<GameInfo> get games => GameCatalog.allGames(_language);
  GameInfo get featuredGame => selectedGame;
  GameInfo get selectedGame => games.firstWhere(
    (game) => game.id == _selectedGameId,
    orElse: () => games.first,
  );
  UnmodifiableListView<ChatMessage> get messages =>
      UnmodifiableListView<ChatMessage>(_messages);

  Future<void> initialize() async {
    _language = await _preferencesService.loadLanguage();
    _colorScheme = await _preferencesService.loadColorScheme();
    _voiceReplyEnabled = await _preferencesService.loadVoiceReplyEnabled();
    _aiApiConfig = await _preferencesService.loadAiApiConfig();
    _assetSourceConfigs = await _preferencesService.loadAssetSourceConfigs();
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
    _ensureGreeting();
    unawaited(prefetchHomeImages());
    _startAssetStatusPolling();
    notifyListeners();
  }

  Future<void> setLanguage(AppLanguage next) async {
    if (_language == next) {
      return;
    }

    _language = next;
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

  Future<void> saveAiApiConfig(AiApiConfig next) async {
    _aiApiConfig = next;
    await _preferencesService.saveAiApiConfig(next);
    notifyListeners();
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
    final String normalizedBaseUrl = config.baseUrl.endsWith('/')
        ? config.baseUrl.substring(0, config.baseUrl.length - 1)
        : config.baseUrl;
    final String normalizedChatPath = config.chatPath.startsWith('/')
        ? config.chatPath
        : '/${config.chatPath}';
    final Uri uri = Uri.parse('$normalizedBaseUrl$normalizedChatPath');
    try {
      final response = await http
          .post(
            uri,
            headers: <String, String>{
              config.apiKeyHeader: config.apiKey,
              'Content-Type': 'application/json',
            },
            body: jsonEncode(<String, dynamic>{
              'model': config.model,
              'messages': const <Map<String, String>>[
                <String, String>{'role': 'user', 'content': 'ping'},
              ],
              'max_completion_tokens': 8,
              'stream': false,
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        _aiConnectivityStatus = ConnectivityStatus(
          state: ConnectivityState.success,
          message: copy.aiApiTestSuccess,
          checkedAt: DateTime.now(),
        );
        debugPrint('[ai] ${_aiConnectivityStatus.message}');
        notifyListeners();
        return copy.aiApiTestSuccess;
      }

      final message = 'HTTP ${response.statusCode}: ${response.body}';
      _aiConnectivityStatus = ConnectivityStatus(
        state: ConnectivityState.failure,
        message: message,
        checkedAt: DateTime.now(),
      );
      debugPrint('[ai] $message');
      notifyListeners();
      return message;
    } catch (error) {
      final message = '连接失败: $error';
      _aiConnectivityStatus = ConnectivityStatus(
        state: ConnectivityState.failure,
        message: message,
        checkedAt: DateTime.now(),
      );
      debugPrint('[ai] $message');
      notifyListeners();
      return message;
    }
  }

  void selectGame(String gameId) {
    if (_selectedGameId == gameId) {
      return;
    }
    _selectedGameId = gameId;
    notifyListeners();
  }

  Future<void> setVoiceReplyEnabled(bool enabled) async {
    _voiceReplyEnabled = enabled;
    await _preferencesService.saveVoiceReplyEnabled(enabled);
    if (!enabled) {
      await _ttsService.stop();
    }
    notifyListeners();
  }

  Future<void> speakMessage(String text) async {
    await _ttsService.setLanguage(_language);
    await _ttsService.speak(text);
  }

  Future<void> stopSpeaking() async {
    await _ttsService.stop();
  }

  Future<void> startListening({
    required ValueChanged<String> onRecognizedText,
  }) async {
    if (!_speechAvailable || _isListening) {
      return;
    }

    _isListening = true;
    notifyListeners();

    await _speechService.startListening(
      language: _language,
      onResult: onRecognizedText,
      onListeningStopped: _handleListeningStopped,
    );
  }

  Future<void> stopListening() async {
    await _speechService.stopListening();
    _handleListeningStopped();
  }

  Future<void> clearConversation() async {
    await resetConversation();
  }

  Future<void> resetConversation({String? greeting}) async {
    _messages
      ..clear()
      ..add(
        ChatMessage(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          role: ChatRole.assistant,
          text: greeting ?? copy.assistantGreetingFor(selectedGame.title),
          timestamp: DateTime.now(),
        ),
      );
    await _ttsService.stop();
    notifyListeners();
  }

  Future<void> sendPrompt(String prompt) async {
    final trimmed = prompt.trim();
    if (trimmed.isEmpty || _isSending) {
      return;
    }

    final userMessage = ChatMessage(
      id: '${DateTime.now().microsecondsSinceEpoch}-user',
      role: ChatRole.user,
      text: trimmed,
      timestamp: DateTime.now(),
    );

    _messages.add(userMessage);
    _isSending = true;
    notifyListeners();

    final reply = await _aiService.generateReply(
      prompt: trimmed,
      language: _language,
      game: featuredGame,
      config: _aiApiConfig,
      assetSourceConfigs: _assetSourceConfigs,
      remoteAssetService: _remoteAssetService,
    );

    final assistantMessage = ChatMessage(
      id: '${DateTime.now().microsecondsSinceEpoch}-assistant',
      role: ChatRole.assistant,
      text: reply,
      timestamp: DateTime.now(),
    );

    _messages.add(assistantMessage);
    _isSending = false;
    notifyListeners();

    if (_voiceReplyEnabled) {
      await speakMessage(reply);
    }
  }

  Future<void> disposeServices() async {
    _assetStatusTimer?.cancel();
    await _speechService.cancelListening();
    await _ttsService.stop();
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
    bool anySuccess = false;
    for (final game in games) {
      anySuccess = (await _cacheImage(game.coverAssetPath)) != null || anySuccess;
      anySuccess =
          (await _cacheImage(game.bannerAssetPath)) != null || anySuccess;
      for (final path in game.galleryAssetPaths) {
        anySuccess = (await _cacheImage(path)) != null || anySuccess;
      }
    }
    _assetConnectivityStatus = ConnectivityStatus(
      state: anySuccess ? ConnectivityState.success : ConnectivityState.failure,
      message: anySuccess ? '首页资源已缓存' : '首页资源拉取失败',
      checkedAt: DateTime.now(),
    );
    notifyListeners();
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

  void _startAssetStatusPolling() {
    _assetStatusTimer?.cancel();
    unawaited(refreshAssetAccessStatus());
    _assetStatusTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(refreshAssetAccessStatus());
    });
  }

  void _ensureGreeting() {
    if (_messages.isEmpty) {
      _messages.add(
        ChatMessage(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          role: ChatRole.assistant,
          text: copy.assistantGreetingFor(selectedGame.title),
          timestamp: DateTime.now(),
        ),
      );
    }
  }

  void _handleListeningStopped() {
    if (_isListening) {
      _isListening = false;
      notifyListeners();
    }
  }
}
