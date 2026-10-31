import 'support/catalog_fixture.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:board_game_agent/app/state/app_controller.dart';
import 'package:board_game_agent/core/localization/app_language.dart';
import 'package:board_game_agent/core/theme/app_theme.dart';
import 'package:board_game_agent/core/theme/color_scheme_option.dart';
import 'package:board_game_agent/features/assistant/services/ai_service.dart';
import 'package:board_game_agent/features/assistant/models/ai_conversation.dart';
import 'package:board_game_agent/features/assistant/models/ai_answer_mode.dart';
import 'package:board_game_agent/features/assistant/models/ai_api_config.dart';
import 'package:board_game_agent/features/assistant/models/answer_source.dart';
import 'package:board_game_agent/features/assistant/models/board_game_ai_answer.dart';
import 'package:board_game_agent/features/assistant/models/chat_message.dart';
import 'package:board_game_agent/features/games/models/game_info.dart';
import 'package:board_game_agent/features/assistant/services/conversation_store.dart';
import 'package:board_game_agent/features/assistant/services/speech_service.dart';
import 'package:board_game_agent/features/assistant/services/tts_service.dart';
import 'package:board_game_agent/features/games/models/game_catalog_manifest.dart';
import 'package:board_game_agent/features/games/services/game_manifest_service.dart';
import 'package:board_game_agent/features/library/models/asset_source_config.dart';
import 'package:board_game_agent/features/library/services/remote_asset_service.dart';

import 'package:board_game_agent/features/settings/services/preferences_service.dart';
import 'package:board_game_agent/main.dart';
import 'package:board_game_agent/ui/shared/library_catalog_status.dart';
import 'package:board_game_agent/ui/shared/catalog_empty_state.dart';
import 'package:board_game_agent/ui/mobile/game_search_screen.dart';
import 'package:board_game_agent/ui/mobile/rule_materials_screen.dart';
import 'package:board_game_agent/ui/desktop/business_panes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webdav_settings/webdav_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameManifest game;
  setUpAll(() async {
    game = catalogGameFixture(
      jsonDecode(await File('assets/games/cabo/game.json').readAsString()),
    );
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets(
    'empty catalogue distinguishes loading, failure, retry, and successful empty',
    (tester) async {
      final manifests = _Manifests()..failure = true;
      final c = _controller(manifests);
      addTearDown(c.dispose);
      await c.retryGameCatalog();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: c,
              builder: (_, _) =>
                  CatalogEmptyState(controller: c, emptyMessage: '暂无推荐桌游'),
            ),
          ),
        ),
      );
      expect(find.text('暂时无法加载桌游资料'), findsOneWidget);
      expect(find.text('暂无推荐桌游'), findsNothing);
      final gate = Completer<void>();
      manifests
        ..failure = false
        ..gate = gate;
      await tester.tap(find.byKey(const ValueKey('catalog-empty-retry')));
      await tester.pump();
      expect(find.text('正在加载桌游资料…'), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('暂无推荐桌游'), findsOneWidget);
      expect(c.gameCatalogLoadState, LibraryLoadState.empty);
    },
  );

  testWidgets(
    'search and rule materials do not describe catalog failure as no results',
    (tester) async {
      final manifests = _Manifests()..failure = true;
      final c = _controller(manifests);
      addTearDown(c.dispose);
      await c.retryGameCatalog();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.buildTheme(c.palette),
          home: MobileGameSearchScreen(controller: c, onOpenGame: (_) {}),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('暂时无法加载桌游资料'), findsOneWidget);
      expect(find.text('没有找到桌游'), findsNothing);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.buildTheme(c.palette),
          home: MobileRuleMaterialsScreen(controller: c),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('暂时无法加载桌游资料'), findsOneWidget);
      expect(find.text('没有找到规则资料'), findsNothing);
    },
  );

  testWidgets('failed refresh keeps prior catalogue and labels it as saved', (
    tester,
  ) async {
    final manifests = _Manifests()..games = [game];
    final c = _controller(manifests);
    addTearDown(c.dispose);
    await c.retryGameCatalog();
    manifests.failure = true;
    await c.retryGameCatalog();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LibraryCatalogStatus(controller: c)),
      ),
    );
    expect(find.text('当前显示已有资料，更新未完成。'), findsOneWidget);
    expect(c.games.single.slug, 'cabo');
    expect(find.byKey(const ValueKey('catalog-retry')), findsOneWidget);
  });

  test(
    'native catalog failure is recoverable without rerunning initialization',
    () async {
      final manifests = _Manifests()..failure = true;
      final preferences = _Preferences();
      final c = _controller(manifests, preferences: preferences);
      addTearDown(c.dispose);
      await c.initialize();
      expect(c.gameCatalogFailed, isTrue);
      expect(c.hasGames, isFalse);
      c.openGlobalAssistant();
      expect(c.selectedConversation?.isGlobal, isTrue);
      manifests
        ..failure = false
        ..games = [game];
      await c.retryGameCatalog();
      expect(c.games.single.slug, 'cabo');
      expect(c.gameCatalogFailed, isFalse);
      expect(preferences.initializations, 1);
      expect(c.selectedConversation?.isGlobal, isTrue);
    },
  );

  test(
    'Web startup does not await the remote catalog; 404 never loads bundled games',
    () async {
      final gate = Completer<void>();
      var requests = 0;
      final remote = RemoteAssetService(
        serviceOrigin: () => Uri.parse('https://site.test'),
        browser: true,
        client: MockClient((request) async {
          requests++;
          await gate.future;
          return http.Response('', 404);
        }),
      );
      final c = _controller(GameManifestService(), remote: remote);
      addTearDown(c.dispose);
      await c.initialize().timeout(const Duration(seconds: 2));
      await Future<void>.delayed(Duration.zero);
      expect(requests, 1);
      expect(c.gameCatalogLoadState, LibraryLoadState.loading);
      c.openGlobalAssistant();
      expect(c.selectedConversation?.isGlobal, isTrue);
      gate.complete();
      await c.retryGameCatalog();
      expect(c.gameCatalogFailed, isTrue);
      expect(c.games, isEmpty);
    },
  );

  test(
    'retries coalesce, preserve the last good catalog and renew the dismissed notice',
    () async {
      final manifests = _Manifests()..games = [game];
      final c = _controller(manifests);
      addTearDown(c.dispose);
      await c.reloadGames();
      c.browseSession.library.query = 'saved query';
      final gate = Completer<void>();
      manifests
        ..gate = gate
        ..failure = true;
      final a = c.retryGameCatalog(), b = c.retryGameCatalog();
      await Future<void>.delayed(Duration.zero);
      expect(manifests.calls, 2);
      gate.complete();
      await Future.wait([a, b]);
      expect(c.games.single.slug, 'cabo');
      expect(c.gameCatalogFailureMessage, contains('刷新'));
      c.dismissGameCatalogNotice();
      await c.retryGameCatalog();
      expect(c.gameCatalogFailed, isTrue);
      expect(c.showGameCatalogNotice, isTrue);
      manifests.failure = false;
      await c.retryGameCatalog();
      expect(c.gameCatalogFailed, isFalse);
      manifests.failure = true;
      await c.retryGameCatalog();
      expect(c.showGameCatalogNotice, isTrue);
      expect(c.browseSession.library.query, 'saved query');
    },
  );

  test(
    'late catalog from the previous language cannot overwrite a newer load',
    () async {
      final manifests = _Manifests();
      final c = _controller(manifests);
      addTearDown(c.dispose);
      final gate = Completer<void>();
      manifests
        ..gate = gate
        ..games = [game];
      final old = c.retryGameCatalog();
      await Future<void>.delayed(Duration.zero);
      manifests
        ..gate = null
        ..games = [];
      await c.setLanguage(AppLanguage.en);
      gate.complete();
      await old;
      expect(c.games, isEmpty);
      expect(c.gameCatalogLoadState, LibraryLoadState.empty);
      expect(c.gameCatalogFailed, isFalse);
    },
  );

  test(
    'a local preference failure is not disguised as a catalog failure',
    () async {
      final c = _controller(_Manifests(), preferences: _BrokenPreferences());
      addTearDown(c.dispose);
      await expectLater(c.initialize(), throwsStateError);
      expect(c.gameCatalogFailed, isFalse);
    },
  );

  test(
    'catalog outage does not clear a restored game conversation selection',
    () async {
      final conversation = AiConversation(
        id: 'game:cabo',
        title: 'Saved chat',
        scope: AiConversationScope.game,
        gameId: 'cabo',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      await const ConversationStore(browserStorage: true).save(
        jsonEncode({
          'version': 4,
          'selectedConversationId': conversation.id,
          'conversations': {conversation.id: conversation.toMap()},
        }),
      );
      final c = _controller(_Manifests()..failure = true);
      addTearDown(c.dispose);
      await c.initialize();
      expect(c.selectedConversationId, conversation.id);
      expect(c.selectedConversation?.title, 'Saved chat');
      await c.retryGameCatalog();
      expect(c.selectedConversationId, conversation.id);
    },
  );

  test(
    'background check retries a failed catalog even when its revision is unchanged',
    () async {
      final remote = _WebRemote()..allowed = true;
      final manifests = _Manifests()..failure = true;
      final c = _controller(manifests, remote: remote);
      addTearDown(c.dispose);
      await c.retryGameCatalog();
      c.dismissGameCatalogNotice();
      manifests
        ..failure = false
        ..games = [game];
      await c.checkForLibraryUpdatesQuick();
      expect(manifests.calls, 2);
      expect(c.gameCatalogFailed, isFalse);
      expect(c.games.single.slug, 'cabo');
    },
  );

  testWidgets('Web catalog timeout and disposal ignore late results', (
    tester,
  ) async {
    final gate = Completer<void>();
    final manifests = _Manifests()
      ..gate = gate
      ..games = [game];
    final c = _controller(manifests, remote: _WebRemote());
    unawaited(c.retryGameCatalog());
    await tester.pump();
    expect(c.gameCatalogLoadState, LibraryLoadState.loading);
    await tester.pump(const Duration(seconds: 66));
    expect(c.gameCatalogFailed, isTrue);
    c.dispose();
    gate.complete();
    await tester.pump();
    expect(c.games, isEmpty);
  });

  test(
    'unavailable knowledge uses general mode without overwriting the saved preference',
    () async {
      final manifests = _Manifests()..failure = true;
      final c = _controller(manifests, preferences: _KnowledgePreferences());
      addTearDown(c.dispose);
      await c.initialize();
      expect(c.globalAnswerMode, AiAnswerMode.knowledgeOnly);
      expect(
        c.chatAnswerMode(useGlobalMode: true),
        AiAnswerMode.knowledgeThenDirect,
      );
      expect(c.globalUseCurrentGameKnowledge, isFalse);
      await expectLater(
        c.setAllowSmartSupplement(false, useGlobalMode: true),
        throwsStateError,
      );
      manifests
        ..failure = false
        ..games = [game];
      await c.retryGameCatalog();
      expect(c.chatAnswerMode(useGlobalMode: true), AiAnswerMode.knowledgeOnly);
      expect(c.globalUseCurrentGameKnowledge, isTrue);
    },
  );

  for (final width in [320.0, 1440.0]) {
    testWidgets(
      'general assistant sends without sources and disabled knowledge explains on hover at $width',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 850));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final ai = _ReplyAi();
        final manifests = _Manifests()..failure = true;
        final c = _controller(manifests, ai: ai);
        addTearDown(c.dispose);
        await tester.runAsync(c.initialize);
        await c.saveAiApiConfig(
          c.aiApiConfig.copyWith(
            apiKey: 'test-only',
            model: 'gpt-6-astra',
            baseUrl: 'https://test.example/v1',
          ),
        );
        c.openGlobalAssistant();
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.buildTheme(c.palette),
            home: Scaffold(body: DesktopAssistantPane(controller: c)),
          ),
        );
        expect(find.byKey(const ValueKey('assistant-draft')), findsOneWidget);
        expect(find.text('AI 助手暂不可用'), findsNothing);
        await tester.tap(
          find.byKey(const ValueKey('assistant-context-button')),
        );
        await tester.pumpAndSettle();
        final item = find.byKey(const ValueKey('assistant-context-knowledge'));
        expect(tester.widget<ListTile>(item).enabled, isFalse);
        expect(find.text(c.copy.assistantKnowledgeUnavailable), findsOneWidget);
        Navigator.of(tester.element(item)).pop();
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('assistant-draft')),
          '你好',
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('desktop-composer-send')));
        await tester.pumpAndSettle();
        expect(ai.requests, 1);
        expect(ai.answerMode, AiAnswerMode.knowledgeThenDirect);
        expect(ai.useKnowledge, isFalse);
        expect(find.text('模拟回复'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'home and library share dismissal and a fresh attempt can show a notice at $width dp',
      (tester) async {
        tester.view.physicalSize = Size(width, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final manifests = _Manifests()..games = [game];
        final c = _controller(manifests);
        addTearDown(c.dispose);
        await c.retryGameCatalog();
        manifests.failure = true;
        await c.retryGameCatalog();
        Widget page(bool home) => MaterialApp(
          theme: AppTheme.buildTheme(c.palette),
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 850),
              textScaler: const TextScaler.linear(1.5),
            ),
            child: Scaffold(
              body: SingleChildScrollView(
                child: LibraryCatalogStatus(controller: c, home: home),
              ),
            ),
          ),
        );
        await tester.pumpWidget(page(true));
        expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('catalog-dismiss')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('catalog-retry')), findsNothing);
        await tester.pumpWidget(page(false));
        expect(find.byKey(const ValueKey('catalog-retry')), findsNothing);
        await c.retryGameCatalog();
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('catalog-dismiss')), findsOneWidget);
        expect(find.byKey(const ValueKey('catalog-retry')), findsOneWidget);
        manifests.failure = false;
        await tester.tap(find.byKey(const ValueKey('catalog-retry')));
        await tester.pumpAndSettle();
        expect(c.gameCatalogFailed, isFalse);
        expect(find.byKey(const ValueKey('catalog-retry')), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final theme in ColorSchemeOption.values) {
    testWidgets(
      'real app shell remains usable after catalog failure in ${theme.name}',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1440, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final preferences = _Preferences(theme: theme);
        final c = _controller(
          _Manifests()..failure = true,
          preferences: preferences,
        );
        final settings = WebDavSettingsController(
          store: _Store(),
          connectionTester: _Tester(),
        );
        await tester.pumpWidget(
          BoardGameAgentApp(controller: c, updateSettingsController: settings),
        );
        for (var i = 0; i < 12; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 15)),
          );
          await tester.pump(const Duration(milliseconds: 15));
        }
        expect(find.text('启动失败'), findsNothing);
        expect(find.byKey(const ValueKey('app-startup-loading')), findsNothing);
        expect(find.byKey(const ValueKey('catalog-dismiss')), findsOneWidget);
        c.openGlobalAssistant();
        expect(c.selectedConversation?.isGlobal, isTrue);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}

AppController _controller(
  GameManifestService manifests, {
  _Preferences? preferences,
  RemoteAssetService? remote,
  AiService? ai,
}) => AppController(
  preferencesService: preferences ?? _Preferences(),
  aiService: ai ?? _Ai(),
  gameManifestService: manifests,
  remoteAssetService: remote ?? RemoteAssetService(),
  speechService: _Speech(),
  ttsService: _Tts(),
  conversationStore: const ConversationStore(browserStorage: true),
);

class _Manifests extends GameManifestService {
  bool failure = false;
  int calls = 0;
  List<GameManifest> games = [];
  Completer<void>? gate;
  @override
  Future<List<GameManifest>> loadEnabledGames({
    required RemoteAssetService remoteAssetService,
    List<AssetSourceConfig> sources = const [],
    bool preferRemote = false,
  }) async {
    calls++;
    final result = games, fail = failure;
    await gate?.future;
    if (fail) throw StateError('injected catalog failure');
    return result;
  }
}

class _WebRemote extends RemoteAssetService {
  _WebRemote() : super();
  bool allowed = false;
  @override
  bool get accessAllowed => allowed;
  @override
  bool get usesPublishedLibrary => true;
  @override
  Future<bool> refreshCatalog({int? knownRevision}) async => false;
}

class _Preferences extends PreferencesService {
  _Preferences({this.theme = ColorSchemeOption.warmwoodStudy});
  final ColorSchemeOption theme;
  int initializations = 0;
  @override
  Future<AppLanguage> loadLanguage() async {
    initializations++;
    return AppLanguage.zhHans;
  }

  @override
  Future<ColorSchemeOption> loadColorScheme() async => theme;
}

class _BrokenPreferences extends _Preferences {
  @override
  Future<AppLanguage> loadLanguage() async =>
      throw StateError('local storage failed');
}

class _KnowledgePreferences extends _Preferences {
  @override
  Future<AiAnswerMode> loadGlobalAnswerMode() async =>
      AiAnswerMode.knowledgeOnly;
  @override
  Future<bool> loadGlobalUseCurrentGameKnowledge() async => true;
}

class _Ai extends Fake implements AiService {
  @override
  void dispose() {}
}

class _ReplyAi extends _Ai {
  int requests = 0;
  AiAnswerMode? answerMode;
  bool? useKnowledge;
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
  }) async* {
    requests++;
    this.answerMode = answerMode;
    useKnowledge = useCurrentGameKnowledge;
    yield BoardGameAiStreamEvent(
      isDone: true,
      answer: BoardGameAiAnswer(
        text: '模拟回复',
        source: AnswerSource.generalAdvice,
      ),
    );
  }
}

class _Speech extends SpeechService {
  @override
  Future<bool> initialize({VoidCallback? onListeningStopped}) async => false;
  @override
  Future<void> cancelListening() async {}
}

class _Tts extends TtsService {
  @override
  bool get isAvailable => false;
  @override
  Future<void> initialize(AppLanguage language) async {}
  @override
  Future<void> setLanguage(AppLanguage language) async {}
  @override
  Future<void> stop() async {}
}

class _Store implements WebDavSettingsStore {
  @override
  Future<WebDavSettings?> load() async => null;
  @override
  Future<void> save(WebDavSettings settings) async {}
}

class _Tester implements WebDavConnectionTester {
  @override
  Future<WebDavConnectionTestResult> test(WebDavSettings settings) async =>
      const WebDavConnectionTestResult.success();
}
