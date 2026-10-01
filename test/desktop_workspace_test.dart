import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageByteFormat, PointerDeviceKind;
import 'package:flutter/foundation.dart';

import 'package:app_ai_client/app_ai_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webdav_settings/webdav_settings.dart';

import 'package:board_game_agent/features/assistant/models/ai_answer_mode.dart';
import 'package:board_game_agent/features/assistant/models/ai_api_config.dart';
import 'package:board_game_agent/features/assistant/models/answer_source.dart';
import 'package:board_game_agent/core/models/app_activity.dart';
import 'package:board_game_agent/features/library/models/asset_source_config.dart';
import 'package:board_game_agent/core/localization/app_language.dart';
import 'package:board_game_agent/features/assistant/models/board_game_ai_answer.dart';
import 'package:board_game_agent/features/library/models/cached_asset.dart';
import 'package:board_game_agent/features/assistant/models/chat_message.dart';
import 'package:board_game_agent/core/theme/color_scheme_option.dart';
import 'package:board_game_agent/core/models/connectivity_status.dart';
import 'package:board_game_agent/features/library/models/desktop_library_resource.dart';
import 'package:board_game_agent/features/games/models/favorite_game_record.dart';
import 'package:board_game_agent/features/games/models/game_info.dart';
import 'package:board_game_agent/features/games/models/game_metadata_text.dart';
import 'package:board_game_agent/features/library/models/remote_asset_file.dart';
import 'package:board_game_agent/features/games/models/recent_game_record.dart';
import 'package:board_game_agent/features/games/models/search_history_record.dart';
import 'package:board_game_agent/features/assistant/services/ai_service.dart';
import 'package:board_game_agent/features/assistant/services/conversation_store.dart';
import 'package:board_game_agent/features/settings/services/desktop_ai_settings_service.dart';
import 'package:board_game_agent/features/games/services/game_manifest_service.dart';
import 'package:board_game_agent/features/settings/services/preferences_service.dart';
import 'package:board_game_agent/features/library/services/remote_asset_service.dart';
import 'package:board_game_agent/features/assistant/services/speech_service.dart';
import 'package:board_game_agent/features/assistant/services/tts_service.dart';
import 'package:board_game_agent/app/state/app_controller.dart';
import 'package:board_game_agent/core/theme/app_palette.dart';
import 'package:board_game_agent/ui/desktop/business_panes.dart';
import 'package:board_game_agent/ui/desktop/workspace.dart';
import 'package:board_game_agent/ui/desktop/theme.dart';
import 'package:board_game_agent/ui/desktop/sidebar.dart';
import 'package:board_game_agent/ui/desktop/home_pane.dart';
import 'package:board_game_agent/ui/desktop/national_day_page.dart';
import 'package:board_game_agent/ui/desktop/games_pane.dart';
import 'package:board_game_agent/ui/desktop/favorites_pane.dart';
import 'package:board_game_agent/ui/desktop/game_detail_pane.dart';
import 'package:board_game_agent/ui/desktop/settings_pane.dart';
import 'package:board_game_agent/ui/desktop/desktop_responsive.dart';
import 'package:board_game_agent/ui/shared/game_cover_motion.dart';
import 'package:board_game_agent/ui/shared/favorite_feedback.dart';
import 'package:board_game_agent/ui/shared/assistant/answer_mode_selector.dart';

part 'desktop/desktop_settings_test_cases.dart';
part 'desktop/desktop_shell_test_cases.dart';
part 'desktop/desktop_library_test_cases.dart';
part 'desktop/desktop_home_test_cases.dart';
part 'desktop/desktop_typography_test_cases.dart';
part 'desktop/desktop_assistant_design_test_cases.dart';
part 'desktop/desktop_national_day_test_cases.dart';

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
  // Exercise Chinese/Latin glyph metrics and real variable weights, rather
  // than Ahem's fixed boxes, in every desktop layout and menu regression.
  setUpAll(() async {
    final font = FontLoader('Noto Sans SC')
      ..addFont(rootBundle.load('assets/fonts/NotoSansSC-Variable.ttf'));
    await font.load();
    await (FontLoader(
      'National Day Display',
    )..addFont(rootBundle.load('assets/fonts/NationalDayDisplay.ttf'))).load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
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
  _registerDesktopTypographyTests(workspaceContext);
  _registerAssistantDesignTests(workspaceContext);
  _registerDesktopNationalDayTests(workspaceContext);

  test('opening a new assistant does not create a fake reply', () {
    controller.openGlobalAssistant();
    expect(controller.selectedConversation?.messages, isEmpty);
    expect(controller.messagesForContext(useGlobalMode: true), isEmpty);
  });

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

  for (final Size size in const <Size>[Size(720, 700), Size(1280, 800)]) {
    testWidgets('model picker stays compact and updates effort at $size', (
      tester,
    ) async {
      await controller.saveAiApiConfig(
        controller.aiApiConfig.copyWith(
          apiKey: 'test-key',
          model: 'gpt-6-astra',
          reasoningEffort: AiReasoningEffort.max,
        ),
      );
      await controller.refreshAiModels();
      await _mount(tester, controller, size);
      await _navigate(tester, 'AI助手');
      await tester.tap(
        find.byKey(const ValueKey<String>('desktop-model-selector')),
      );
      await tester.pumpAndSettle();

      final Finder panel = find.byKey(
        const ValueKey<String>('desktop-model-picker-panel'),
      );
      expect(panel, findsOneWidget);
      final Rect rect = tester.getRect(panel);
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(size.height));
      expect(rect.height, lessThanOrEqualTo(430));
      expect(
        find.byKey(const ValueKey<String>('desktop-model-option-gpt-5.5')),
        findsNothing,
      );

      expect(
        find.byKey(const ValueKey<String>('desktop-reasoning-option-none')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('desktop-reasoning-option-max')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('desktop-model-option-gpt-5.6-sol')),
      );
      await tester.pumpAndSettle();
      expect(controller.aiApiConfig.model, 'gpt-5.6-sol');
      expect(
        find.byKey(const ValueKey<String>('desktop-reasoning-option-none')),
        findsNothing,
      );
      expect(
        find.byKey(
          const ValueKey<String>('desktop-reasoning-option-automatic'),
        ),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('desktop-reasoning-option-high')),
      );
      await tester.pumpAndSettle();
      expect(controller.aiApiConfig.reasoningEffort, AiReasoningEffort.high);
      expect(panel, findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('assistant-service-tier-fast')),
      );
      await tester.pumpAndSettle();
      expect(controller.aiApiConfig.responseSpeed, AiResponseSpeed.fast);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(panel, findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('model picker explains an unconfigured service', (tester) async {
    await _mount(tester, controller, const Size(720, 700));
    await _navigate(tester, 'AI助手');
    await tester.tap(
      find.byKey(const ValueKey<String>('desktop-model-selector')),
    );
    await tester.pumpAndSettle();

    expect(find.text('请先在设置中配置 AI 服务'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('desktop-model-picker-retry')),
      findsNothing,
    );
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
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.binding.setSurfaceSize(size);
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey<String>('desktop-test-capture'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildDesktopTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
        home: DesktopWorkspace(
          controller: controller,
          webDavSettingsController: webDavSettingsController,
          onOpenAbout: onOpenAbout ?? () {},
          enableNativeWindowControls: false,
        ),
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
  AiService? aiService,
}) async {
  if (preferencesService == null) {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  }
  final AppController controller = AppController(
    preferencesService: preferencesService ?? PreferencesService(),
    aiService: aiService ?? _FakeAiService(),
    conversationStore: _WorkspaceConversationStore(),
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
  String? gameVoteCache;

  @override
  Future<String?> loadGameVoteCache() async => gameVoteCache;

  @override
  Future<void> saveGameVoteCache(String value) async => gameVoteCache = value;

  List<String>? nationalDayGameSlugs;
  bool failNationalDaySave = false;

  @override
  Future<List<String>?> loadNationalDayGameSlugs() async =>
      nationalDayGameSlugs;

  @override
  Future<void> saveNationalDayGameSlugs(Iterable<String> slugs) async {
    if (failNationalDaySave) throw StateError('test save failure');
    nationalDayGameSlugs = slugs.toList();
  }

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
    return const <AiModel>[
      AiModel(id: 'gpt-5.5'),
      AiModel(id: 'gpt-5.6-sol'),
      AiModel(id: 'text-embedding-3-large'),
    ];
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
    String? conversationId,
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
    String? conversationId,
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

class _WorkspaceConversationStore extends ConversationStore {
  String? _payload;

  @override
  Future<String?> load() async => _payload;

  @override
  Future<void> save(String payload) async {
    _payload = payload;
  }
}
