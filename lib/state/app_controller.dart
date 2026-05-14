import 'dart:collection';
import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../models/ai_api_config.dart';
import '../models/ai_answer_mode.dart';
import '../models/asset_source_config.dart';
import '../models/app_language.dart';
import '../models/chat_message.dart';
import '../models/cached_asset.dart';
import '../models/connectivity_status.dart';
import '../models/color_scheme_option.dart';
import '../models/game_info.dart';
import '../models/game_catalog_manifest.dart';
import '../models/remote_library_update.dart';
import '../models/resolved_document.dart';
import '../services/ai_service.dart';
import '../services/preferences_service.dart';
import '../services/game_manifest_service.dart';
import '../services/remote_asset_service.dart';
import '../services/speech_service.dart';
import '../services/tts_service.dart';
import '../theme/app_palette.dart';
import '../theme/palette_registry.dart';
import '../ui/app_copy.dart';

class AppController extends ChangeNotifier {
  AppController({
    required PreferencesService preferencesService,
    required AiService aiService,
    required GameManifestService gameManifestService,
    required RemoteAssetService remoteAssetService,
    required SpeechService speechService,
    required TtsService ttsService,
  }) : _preferencesService = preferencesService,
       _aiService = aiService,
       _gameManifestService = gameManifestService,
       _remoteAssetService = remoteAssetService,
       _speechService = speechService,
       _ttsService = ttsService;

  final PreferencesService _preferencesService;
  final AiService _aiService;
  final GameManifestService _gameManifestService;
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
  AiAnswerMode _gameAnswerMode = AiAnswerMode.knowledgeOnly;
  AiAnswerMode _globalAnswerMode = AiAnswerMode.knowledgeThenDirect;
  AiApiConfig _aiApiConfig = AiApiConfig.defaultMimo;
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
  AiAnswerMode get gameAnswerMode => _gameAnswerMode;
  AiAnswerMode get globalAnswerMode => _globalAnswerMode;
  AiApiConfig get aiApiConfig => _aiApiConfig;
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
      UnmodifiableListView<ChatMessage>(_messages);

  AiAnswerMode chatAnswerMode({required bool useGlobalMode}) =>
      useGlobalMode ? _globalAnswerMode : _gameAnswerMode;

  bool allowSmartSupplement({required bool useGlobalMode}) =>
      chatAnswerMode(useGlobalMode: useGlobalMode) ==
      AiAnswerMode.knowledgeThenDirect;

  Future<void> initialize() async {
    _language = await _preferencesService.loadLanguage();
    _colorScheme = await _preferencesService.loadColorScheme();
    _voiceReplyEnabled = await _preferencesService.loadVoiceReplyEnabled();
    _gameAnswerMode = await _preferencesService.loadGameAnswerMode();
    _globalAnswerMode = await _preferencesService.loadGlobalAnswerMode();
    _aiApiConfig = await _preferencesService.loadAiApiConfig();
    _assetSourceConfigs = await _preferencesService.loadAssetSourceConfigs();
    _games = await _loadGamesForLanguage(_language);
    _selectedGameId = _resolveSelectedGameId(_selectedGameId);
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
    _ensureGreeting();
    unawaited(prefetchHomeImages());
    _startAssetStatusPolling();
    unawaited(checkForLibraryUpdates());
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

  Future<void> sendPrompt(String prompt, {bool useGlobalMode = false}) async {
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

    final GameInfo game = featuredGame;
    final AiAnswerMode answerMode = chatAnswerMode(
      useGlobalMode: useGlobalMode,
    );
    debugPrint(
      '[chat] send prompt game=${game.slug} global=$useGlobalMode mode=${answerMode.code}',
    );

    try {
      final reply = await _aiService.generateReply(
        prompt: trimmed,
        language: _language,
        game: game,
        answerMode: answerMode,
        useGlobalMode: useGlobalMode,
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
      if (_voiceReplyEnabled) {
        await speakMessage(reply);
      }
    } catch (error, stackTrace) {
      debugPrint('[chat] sendPrompt failed: $error');
      debugPrint('$stackTrace');
      _messages.add(
        ChatMessage(
          id: '${DateTime.now().microsecondsSinceEpoch}-assistant-error',
          role: ChatRole.assistant,
          text: copy.aiReplyFailed,
          timestamp: DateTime.now(),
        ),
      );
    } finally {
      _isSending = false;
      notifyListeners();
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
    final List<String> imagePaths = [
      for (final game in games) ...[
        game.coverAssetPath,
        game.bannerAssetPath,
        ...game.galleryAssetPaths,
      ],
    ].toSet().toList();

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
