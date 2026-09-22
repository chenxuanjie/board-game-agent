import 'dart:async';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/foundation.dart';

import 'package:app_ai_client/app_ai_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webdav_settings/webdav_settings.dart';

import 'package:board_game_agent/models/ai_answer_mode.dart';
import 'package:board_game_agent/models/ai_api_config.dart';
import 'package:board_game_agent/models/answer_source.dart';
import 'package:board_game_agent/models/app_activity.dart';
import 'package:board_game_agent/models/asset_source_config.dart';
import 'package:board_game_agent/models/app_language.dart';
import 'package:board_game_agent/models/board_game_ai_answer.dart';
import 'package:board_game_agent/models/cached_asset.dart';
import 'package:board_game_agent/models/chat_message.dart';
import 'package:board_game_agent/models/color_scheme_option.dart';
import 'package:board_game_agent/models/connectivity_status.dart';
import 'package:board_game_agent/models/desktop_library_resource.dart';
import 'package:board_game_agent/models/favorite_game_record.dart';
import 'package:board_game_agent/models/game_info.dart';
import 'package:board_game_agent/models/remote_asset_file.dart';
import 'package:board_game_agent/models/recent_game_record.dart';
import 'package:board_game_agent/models/search_history_record.dart';
import 'package:board_game_agent/services/ai_service.dart';
import 'package:board_game_agent/services/desktop_ai_settings_service.dart';
import 'package:board_game_agent/services/game_manifest_service.dart';
import 'package:board_game_agent/services/preferences_service.dart';
import 'package:board_game_agent/services/remote_asset_service.dart';
import 'package:board_game_agent/services/speech_service.dart';
import 'package:board_game_agent/services/tts_service.dart';
import 'package:board_game_agent/state/app_controller.dart';
import 'package:board_game_agent/theme/app_palette.dart';
import 'package:board_game_agent/ui/desktop/business_panes.dart';
import 'package:board_game_agent/ui/desktop/workspace.dart';
import 'package:board_game_agent/ui/desktop/theme.dart';
import 'package:board_game_agent/ui/desktop/sidebar.dart';
import 'package:board_game_agent/ui/desktop/home_pane.dart';
import 'package:board_game_agent/ui/desktop/games_pane.dart';
import 'package:board_game_agent/ui/desktop/favorites_pane.dart';
import 'package:board_game_agent/ui/desktop/game_detail_pane.dart';
import 'package:board_game_agent/ui/desktop/settings_pane.dart';
import 'package:board_game_agent/ui/desktop/desktop_responsive.dart';

part 'desktop/desktop_settings_test_cases.dart';
part 'desktop/desktop_shell_test_cases.dart';
part 'desktop/desktop_library_test_cases.dart';
part 'desktop/desktop_home_test_cases.dart';

class _DesktopWorkspaceTestContext {
  const _DesktopWorkspaceTestContext({
    required AppController Function() controller,
    required _InMemoryPreferencesService Function() preferences,
  }) : _controller = controller,
       _preferences = preferences;

  final AppController Function() _controller;
  final _InMemoryPreferencesService Function() _preferences;

  AppController get controller => _controller();
  _InMemoryPreferencesService get preferences => _preferences();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppController controller;
  late _InMemoryPreferencesService preferences;
  final _DesktopWorkspaceTestContext workspaceContext =
      _DesktopWorkspaceTestContext(
        controller: () => controller,
        preferences: () => preferences,
      );

  setUp(() async {
    preferences = _InMemoryPreferencesService();
    controller = await _createController(
      preferencesService: preferences,
      ttsService: _UnavailableTtsService(),
    );
    controller.selectGame('puerto-rico');
  });
  tearDown(() {
    controller.dispose();
  });

  _registerDesktopShellTests(workspaceContext);

  _registerDesktopLibraryTests(workspaceContext);

  _registerDesktopHomeTests(workspaceContext);

  testWidgets('AI hero banner opens a visible assistant on a wide desktop', (
    tester,
  ) async {
    await _mount(tester, controller, const Size(1995, 1248));
    await tester.tap(find.byKey(const ValueKey<String>('home-hero-dot-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('home-hero-page-2')));
    await tester.pumpAndSettle();

    expect(find.byType(DesktopAssistantPane), findsOneWidget);
    final composer = find.byKey(const ValueKey<String>('desktop-composer-box'));
    expect(composer, findsOneWidget);
    expect(composer.hitTestable(), findsOneWidget);
    expect(tester.getSize(composer).width, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('assistant runs inside the Warmwood Study Desktop shell', (
    tester,
  ) async {
    await _mount(tester, controller, const Size(1280, 800));
    await _navigate(tester, 'AI助手');
    expect(find.byType(DesktopAssistantPane), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('desktop-composer-box')),
      findsOneWidget,
    );
    final context = tester.element(
      find.byKey(const ValueKey<String>('desktop-composer-box')),
    );
    expect(AppPalette.of(context).scheme, ColorSchemeOption.warmwoodStudy);
    expect(tester.takeException(), isNull);
  });

  _registerDesktopSettingsTests(
    _DesktopSettingsTestContext(
      controller: () => controller,
      preferences: () => preferences,
    ),
  );
}

Future<void> _mount(
  WidgetTester tester,
  AppController controller,
  Size size, {
  VoidCallback? onOpenAbout,
  bool settle = true,
  WebDavSettingsController? webDavSettingsController,
}) async {
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.binding.setSurfaceSize(size);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildDesktopTheme(),
      home: DesktopWorkspace(
        controller: controller,
        webDavSettingsController: webDavSettingsController,
        onOpenAbout: onOpenAbout ?? () {},
        enableNativeWindowControls: false,
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 500));
  }
}

class _MemoryWebDavSettingsStore implements WebDavSettingsStore {
  _MemoryWebDavSettingsStore(this.value);

  WebDavSettings? value;

  @override
  Future<WebDavSettings?> load() async => value;

  @override
  Future<void> save(WebDavSettings settings) async {
    value = settings;
  }
}

class _SuccessfulWebDavConnectionTester implements WebDavConnectionTester {
  const _SuccessfulWebDavConnectionTester();

  @override
  Future<WebDavConnectionTestResult> test(WebDavSettings settings) async =>
      const WebDavConnectionTestResult.success();
}

Future<void> _navigate(WidgetTester tester, String label) async {
  if (find.byType(DesktopSidebar).evaluate().isEmpty) {
    await tester.tap(
      find.byKey(const ValueKey<String>('desktop-open-navigation')),
    );
    await tester.pumpAndSettle();
  }
  final textItem = find.descendant(
    of: find.byType(DesktopSidebar),
    matching: find.text(label),
  );
  if (textItem.evaluate().isNotEmpty) {
    await tester.tap(textItem);
  } else {
    await tester.tap(find.byTooltip(label));
  }
  await tester.pumpAndSettle();
}

Future<AppController> _createController({
  PreferencesService? preferencesService,
  TtsService? ttsService,
}) async {
  if (preferencesService == null) {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  }
  final AppController controller = AppController(
    preferencesService: preferencesService ?? PreferencesService(),
    aiService: _FakeAiService(),
    gameManifestService: GameManifestService(),
    remoteAssetService: _NoNetworkAssetService(),
    speechService: SpeechService(),
    ttsService: ttsService ?? TtsService(),
  );
  await controller.reloadGames();
  return controller;
}

class _UnavailableTtsService extends TtsService {
  @override
  bool get isAvailable => false;
}

class _InMemoryPreferencesService extends PreferencesService {
  AiApiConfig? _aiApiConfig;
  List<AiApiConfig> _aiCustomPresets = <AiApiConfig>[];
  ColorSchemeOption? _colorScheme;
  bool? _checkForUpdates;
  Map<String, DateTime> _favoriteGames = <String, DateTime>{};
  List<DesktopLibraryResource> _desktopLibraryResources =
      <DesktopLibraryResource>[];
  List<SearchHistoryRecord> _searchHistory = <SearchHistoryRecord>[];
  List<RecentGameRecord> _recentGames = <RecentGameRecord>[];

  @override
  Future<void> clearSelectedConversationId() async {}

  @override
  Future<void> saveAiApiConfig(AiApiConfig config) async {
    _aiApiConfig = config;
  }

  @override
  Future<void> saveAiCustomPresets(Iterable<AiApiConfig> configs) async {
    _aiCustomPresets = List<AiApiConfig>.from(configs);
  }

  @override
  Future<List<AiApiConfig>> loadAiCustomPresets() async =>
      List<AiApiConfig>.unmodifiable(_aiCustomPresets);

  @override
  Future<void> saveColorScheme(ColorSchemeOption scheme) async {
    _colorScheme = scheme;
  }

  @override
  Future<void> saveCheckForUpdates(bool enabled) async {
    _checkForUpdates = enabled;
  }

  @override
  Future<void> saveSelectedConversationId(String conversationId) async {}

  @override
  Future<List<FavoriteGameRecord>> loadFavoriteGames() async => _favoriteGames
      .entries
      .map(
        (entry) =>
            FavoriteGameRecord(gameSlug: entry.key, createdAt: entry.value),
      )
      .toList(growable: false);

  @override
  Future<void> saveFavoriteGames(Iterable<FavoriteGameRecord> records) async {
    _favoriteGames = <String, DateTime>{
      for (final record in records) record.gameSlug: record.createdAt,
    };
  }

  @override
  Future<List<DesktopLibraryResource>> loadDesktopLibraryResources() async =>
      List<DesktopLibraryResource>.unmodifiable(_desktopLibraryResources);

  @override
  Future<void> saveDesktopLibraryResources(
    Iterable<DesktopLibraryResource> resources,
  ) async {
    _desktopLibraryResources = List<DesktopLibraryResource>.from(resources);
  }

  @override
  Future<List<RecentGameRecord>> loadRecentGames() async =>
      List<RecentGameRecord>.unmodifiable(_recentGames);

  @override
  Future<void> saveRecentGames(Iterable<RecentGameRecord> records) {
    _recentGames = List<RecentGameRecord>.from(records);
    return Future<void>.value();
  }

  @override
  Future<List<SearchHistoryRecord>> loadSearchHistory() async =>
      const <SearchHistoryRecord>[];

  @override
  Future<void> saveSearchHistory(Iterable<SearchHistoryRecord> records) async {
    _searchHistory = List<SearchHistoryRecord>.from(records);
  }

  @override
  Future<List<String>> loadRecentSearches() async =>
      _searchHistory.map((record) => record.query).toList(growable: false);

  @override
  Future<void> saveRecentSearches(Iterable<String> queries) async {
    final now = DateTime.now().toUtc();
    _searchHistory = queries
        .map((query) => SearchHistoryRecord(query: query, searchedAt: now))
        .toList(growable: false);
  }
}

class _NoNetworkAssetService extends RemoteAssetService {
  _NoNetworkAssetService() : super(client: _NoopHttpClient());

  @override
  Future<File?> cachedFileFor(String remotePath) async => null;

  @override
  Future<CachedAsset?> ensureCached({
    required List<AssetSourceConfig> sources,
    required String remotePath,
    bool forceRefresh = false,
    bool allowCachedFallback = true,
  }) async => null;

  @override
  Future<String?> fetchRemoteText({
    required List<AssetSourceConfig> sources,
    required String remotePath,
  }) async => null;

  @override
  Future<List<RemoteAssetFile>> listFilesRecursively({
    required List<AssetSourceConfig> sources,
    required String remotePath,
    int maxDepth = 6,
    int maxEntries = 1000,
  }) async => const <RemoteAssetFile>[];

  @override
  Future<bool> hasRemoteChanged({
    required List<AssetSourceConfig> sources,
    required String remotePath,
  }) async => false;
}

class _NoopHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return Future<http.StreamedResponse>.error(
      StateError('network disabled for widget test'),
    );
  }
}

class _FakeAiService implements AiService {
  @override
  Future<List<AiModel>> listModels(AiApiConfig config) async {
    return const <AiModel>[AiModel(id: 'desktop-model')];
  }

  @override
  Future<BoardGameAiAnswer> generateReply({
    required String prompt,
    required AppLanguage language,
    required GameInfo game,
    required AiAnswerMode answerMode,
    required bool useGlobalMode,
    required AiApiConfig config,
    required List<AssetSourceConfig> assetSourceConfigs,
    required RemoteAssetService remoteAssetService,
    required List<ChatMessage> conversationHistory,
    bool useCurrentGameKnowledge = false,
  }) async {
    return BoardGameAiAnswer(text: 'test', source: AnswerSource.generalAdvice);
  }

  @override
  Stream<BoardGameAiStreamEvent> streamReply({
    required String prompt,
    required AppLanguage language,
    required GameInfo game,
    required AiAnswerMode answerMode,
    required bool useGlobalMode,
    required AiApiConfig config,
    required List<AssetSourceConfig> assetSourceConfigs,
    required RemoteAssetService remoteAssetService,
    required List<ChatMessage> conversationHistory,
    bool useCurrentGameKnowledge = false,
    Future<void>? abortTrigger,
  }) async* {}

  @override
  Future<AiHealthResult> checkConnection(AiApiConfig config) async {
    return const AiHealthResult(
      success: true,
      message: 'test',
      latency: Duration.zero,
      model: '',
    );
  }

  @override
  void dispose() {}
}
