import 'dart:io';
import 'package:flutter/foundation.dart';

import 'package:app_ai_client/app_ai_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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
import 'package:board_game_agent/models/game_info.dart';
import 'package:board_game_agent/models/remote_asset_file.dart';
import 'package:board_game_agent/services/ai_service.dart';
import 'package:board_game_agent/services/game_manifest_service.dart';
import 'package:board_game_agent/services/preferences_service.dart';
import 'package:board_game_agent/services/remote_asset_service.dart';
import 'package:board_game_agent/services/speech_service.dart';
import 'package:board_game_agent/services/tts_service.dart';
import 'package:board_game_agent/state/app_controller.dart';
import 'package:board_game_agent/theme/app_palette.dart';
import 'package:board_game_agent/ui/screens/desktop_workspace_screen.dart';

import 'package:board_game_agent/ui/v4/v4_workspace.dart';
import 'package:board_game_agent/ui/v4/v4_theme.dart';
import 'package:board_game_agent/ui/v4/v4_sidebar.dart';
import 'package:board_game_agent/ui/v4/v4_home.dart';
import 'package:board_game_agent/ui/v4/v4_games.dart';
import 'package:board_game_agent/ui/v4/v4_game_detail.dart';
import 'package:board_game_agent/ui/v4/v4_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppController controller;

  setUp(() async {
    controller = await _createController();
    controller.selectGame('puerto-rico');
  });
  tearDown(() {
    controller.dispose();
  });

  test('V4 theme keeps the host platform and supports legacy content', () {
    final theme = buildV4Theme();
    expect(theme.platform, defaultTargetPlatform);
    expect(theme.brightness, Brightness.light);
    expect(theme.useMaterial3, isTrue);
    expect(theme.scaffoldBackgroundColor, V4Colors.background);
    expect(theme.extensions, isNotEmpty);
  });

  for (final size in const [
    Size(1280, 800),
    Size(1100, 700),
    Size(720, 700),
    Size(1920, 1080),
  ]) {
    testWidgets('home, games and settings navigate without overflow at $size', (
      tester,
    ) async {
      await _mount(tester, controller, size);
      expect(find.byType(V4HomePane), findsOneWidget);
      final home = find.byType(V4HomePane);
      expect(controller.games, isNotEmpty);
      for (final game in controller.games.take(5)) {
        expect(
          find.descendant(of: home, matching: find.text(game.title)),
          findsWidgets,
        );
      }
      expect(tester.takeException(), isNull);
      await _navigate(tester, '游戏库');
      expect(find.byType(V4GamesPane), findsOneWidget);
      expect(find.byType(V4HomePane), findsNothing);
      for (final game in controller.games) {
        expect(
          find.descendant(
            of: find.byType(V4GamesPane),
            matching: find.text(game.title),
          ),
          findsWidgets,
        );
      }
      // These titles occur in the reference mock data, not the bundled manifest.
      for (final title in ['卡坦岛', '璀璨王国']) {
        expect(controller.games.where((game) => game.title == title), isEmpty);
        expect(find.text(title), findsNothing);
      }
      expect(tester.takeException(), isNull);
      await _navigate(tester, '设置');
      expect(find.byType(V4SettingsPane), findsOneWidget);
      expect(find.text('语言设置'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('完整设置'));
      await tester.pumpAndSettle();
      expect(find.text('完整设置').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _navigate(tester, '首页');
      expect(find.byType(V4HomePane), findsOneWidget);
      expect(find.byType(V4SettingsPane), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('unsupported sidebar routes display their own unavailable body', (
    tester,
  ) async {
    await _mount(tester, controller, const Size(1280, 800));
    for (final label in ['排行榜', '我的收藏', '社区']) {
      await _navigate(tester, label);
      expect(find.byType(V4HomePane), findsNothing);
      final title = find.text(label).evaluate().where((element) {
        return element.findAncestorWidgetOfExactType<V4Sidebar>() == null;
      });
      expect(title, hasLength(1));
      final body = find
          .ancestor(of: find.text(label).last, matching: find.byType(Column))
          .first;
      expect(
        find.descendant(of: body, matching: find.text('未开放')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'responsive shell switches between full sidebar, rail and drawer',
    (tester) async {
      await _mount(tester, controller, const Size(1280, 800));
      expect(
        find.byKey(const ValueKey<String>('v4-sidebar-full')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('v4-sidebar-rail')),
        findsNothing,
      );

      await tester.binding.setSurfaceSize(const Size(1100, 700));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('v4-sidebar-rail')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await tester.binding.setSurfaceSize(const Size(720, 700));
      await tester.pumpAndSettle();
      expect(find.byType(V4Sidebar), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('v4-open-navigation')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('v4-open-navigation')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('v4-sidebar-full')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('compact library opens a card directly and hides preview', (
    tester,
  ) async {
    await _mount(tester, controller, const Size(1100, 700));
    await _navigate(tester, '游戏库');
    final game = controller.games.length > 1
        ? controller.games[1]
        : controller.games.first;
    final title = find.descendant(
      of: find.byType(V4GamesPane),
      matching: find.text(game.title),
    );
    expect(title, findsOneWidget);
    await tester.tap(title);
    await tester.pumpAndSettle();
    expect(find.byType(V4GameDetailPane), findsOneWidget);
    expect(controller.selectedGame.id, game.id);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow drawer reaches every migrated workspace', (tester) async {
    await _mount(tester, controller, const Size(720, 700));
    await _navigate(tester, '游戏库');
    expect(find.byType(V4GamesPane), findsOneWidget);
    await _navigate(tester, 'AI助手');
    expect(find.byType(DesktopWorkspaceScreen), findsOneWidget);
    expect(
      tester
          .state<DesktopWorkspaceScreenState>(
            find.byType(DesktopWorkspaceScreen),
          )
          .destinationName,
      'assistant',
    );
    await _navigate(tester, '设置');
    expect(find.byType(V4SettingsPane), findsOneWidget);
    await tester.ensureVisible(find.text('完整设置'));
    await tester.tap(find.text('完整设置'));
    await tester.pumpAndSettle();
    expect(
      tester
          .state<DesktopWorkspaceScreenState>(
            find.byType(DesktopWorkspaceScreen),
          )
          .destinationName,
      'settings',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('home rules query shortcut navigates to the game library', (
    tester,
  ) async {
    await _mount(tester, controller, const Size(1280, 800));
    await tester.tap(
      find.byKey(const ValueKey<String>('home-quick-entry-rules')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(V4GamesPane), findsOneWidget);
    expect(find.byType(V4HomePane), findsNothing);
    expect(controller.games, isNotEmpty);
    expect(
      find.descendant(
        of: find.byType(V4GamesPane),
        matching: find.text(controller.games.first.title),
      ),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'home library load failures are shown in notifications, not inline',
    (tester) async {
      await controller.refreshLibraryResources();
      expect(controller.libraryLoadError, isNotNull);
      expect(
        controller.activities.any(
          (activity) => activity.kind == AppActivityKind.libraryLoadFailed,
        ),
        isTrue,
      );

      await _mount(tester, controller, const Size(1995, 1248));
      expect(find.text('资料加载失败，请在资料库重试。'), findsNothing);
      expect(find.text('打开资料库'), findsNothing);

      await tester.tap(find.byTooltip('通知').hitTestable());
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('desktop-activity-popup')),
        findsOneWidget,
      );
      expect(find.text('资料加载失败'), findsOneWidget);
      expect(find.textContaining('打开资料库可重试'), findsOneWidget);

      await tester.tap(find.text('资料加载失败'));
      await tester.pumpAndSettle();
      expect(
        tester
            .state<DesktopWorkspaceScreenState>(
              find.byType(DesktopWorkspaceScreen),
            )
            .destinationName,
        'library',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('empty game filters do not insert an empty-state panel', (
    tester,
  ) async {
    await _mount(tester, controller, const Size(1280, 800));
    await _navigate(tester, '游戏库');
    expect(
      controller.games.where(
        (game) =>
            '${game.categoryLine} ${game.keywords.join(' ')}'.contains('合作') &&
            game.supportedPlayers.any((players) => players >= 5),
      ),
      isEmpty,
    );

    await tester.tap(
      find.descendant(of: find.byType(V4GamesPane), matching: find.text('合作')),
    );
    await tester.tap(find.text('筛选'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('5+')),
    );
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();

    expect(find.text('暂无符合条件的游戏'), findsNothing);
    expect(find.text('请选择游戏'), findsNothing);
    expect(find.text('暂无游戏，请在资料库检查资源。'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home hero exposes three manually selectable carousel pages', (
    tester,
  ) async {
    await _mount(tester, controller, const Size(1280, 800));
    expect(
      find.byKey(const ValueKey<String>('home-hero-carousel')),
      findsOneWidget,
    );
    for (var index = 0; index < 3; index++) {
      expect(
        find.byKey(ValueKey<String>('home-hero-dot-$index')),
        findsOneWidget,
      );
    }
    await tester.tap(find.byKey(const ValueKey<String>('home-hero-dot-1')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('home-hero-page-1')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey<String>('home-hero-dot-2')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('home-hero-page-2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('v4-home-library-flame')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('v4-sidebar-logo')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('v4-sidebar-art')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  for (final size in const [
    Size(1280, 800),
    Size(1100, 700),
    Size(720, 700),
    Size(600, 700),
  ]) {
    testWidgets('V5 game detail opens with real data at $size', (tester) async {
      await _mount(tester, controller, size);
      await _navigate(tester, '游戏库');
      final game = controller.games.first;
      final titleInLibrary = find.descendant(
        of: find.byType(V4GamesPane),
        matching: find.text(game.title),
      );
      await tester.tap(titleInLibrary.first);
      await tester.pumpAndSettle();
      expect(find.byType(V4GameDetailPane), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('v4-game-detail')),
        findsOneWidget,
      );
      expect(find.text(game.title), findsWidgets);
      expect(find.text(game.subtitle), findsWidgets);
      expect(find.text('询问 AI'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('detail-tab-2')),
      );
      await tester.tap(find.byKey(const ValueKey<String>('detail-tab-2')));
      await tester.pumpAndSettle();
      expect(find.text('玩家评价'), findsWidgets);
      expect(find.text('未开放'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.byTooltip('返回游戏库'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('返回游戏库'));
      await tester.pumpAndSettle();
      expect(find.byType(V4GamesPane), findsOneWidget);
      expect(find.byType(V4GameDetailPane), findsNothing);
    });
  }

  testWidgets('AI hero banner opens a visible assistant on a wide desktop', (
    tester,
  ) async {
    await _mount(tester, controller, const Size(1995, 1248));
    await tester.tap(find.byKey(const ValueKey<String>('home-hero-dot-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('home-hero-page-2')));
    await tester.pumpAndSettle();

    expect(
      tester
          .state<DesktopWorkspaceScreenState>(
            find.byType(DesktopWorkspaceScreen),
          )
          .destinationName,
      'assistant',
    );
    final composer = find.byKey(const ValueKey<String>('desktop-composer-box'));
    expect(composer.hitTestable(), findsOneWidget);
    expect(tester.getSize(composer).width, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('V3 assistant runs inside the Warmwood Study V4 shell', (
    tester,
  ) async {
    await _mount(tester, controller, const Size(1280, 800));
    await _navigate(tester, 'AI助手');
    final state = tester.state<DesktopWorkspaceScreenState>(
      find.byType(DesktopWorkspaceScreen),
    );
    expect(state.destinationName, 'assistant');
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

  testWidgets(
    'settings opens existing advanced configuration and invokes About',
    (tester) async {
      var aboutCalls = 0;
      await _mount(
        tester,
        controller,
        const Size(1280, 800),
        onOpenAbout: () => aboutCalls++,
      );
      await _navigate(tester, '设置');
      await tester.ensureVisible(find.text('关于'));
      await tester.tap(find.text('关于'));
      await tester.pumpAndSettle();
      expect(aboutCalls, 1);
      await tester.ensureVisible(find.text('完整设置'));
      await tester.tap(find.text('完整设置'));
      await tester.pumpAndSettle();
      expect(find.byType(V4SettingsPane), findsNothing);
      expect(find.byType(DesktopWorkspaceScreen), findsOneWidget);
      final state = tester.state<DesktopWorkspaceScreenState>(
        find.byType(DesktopWorkspaceScreen),
      );
      expect(state.destinationName, 'settings');
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _mount(
  WidgetTester tester,
  AppController controller,
  Size size, {
  VoidCallback? onOpenAbout,
}) async {
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.binding.setSurfaceSize(size);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildV4Theme(),
      home: V4Workspace(
        controller: controller,
        onOpenAbout: onOpenAbout ?? () {},
        enableNativeWindowControls: false,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _navigate(WidgetTester tester, String label) async {
  if (find.byType(V4Sidebar).evaluate().isEmpty) {
    await tester.tap(find.byKey(const ValueKey<String>('v4-open-navigation')));
    await tester.pumpAndSettle();
  }
  final textItem = find.descendant(
    of: find.byType(V4Sidebar),
    matching: find.text(label),
  );
  if (textItem.evaluate().isNotEmpty) {
    await tester.tap(textItem);
  } else {
    await tester.tap(find.byTooltip(label));
  }
  await tester.pumpAndSettle();
}

Future<AppController> _createController() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final AppController controller = AppController(
    preferencesService: PreferencesService(),
    aiService: _FakeAiService(),
    gameManifestService: GameManifestService(),
    remoteAssetService: _NoNetworkAssetService(),
    speechService: SpeechService(),
    ttsService: TtsService(),
  );
  await controller.reloadGames();
  return controller;
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
    return const <AiModel>[];
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
