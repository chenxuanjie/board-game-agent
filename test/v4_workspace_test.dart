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
import 'package:board_game_agent/models/asset_source_config.dart';
import 'package:board_game_agent/models/app_language.dart';
import 'package:board_game_agent/models/board_game_ai_answer.dart';
import 'package:board_game_agent/models/cached_asset.dart';
import 'package:board_game_agent/models/chat_message.dart';
import 'package:board_game_agent/models/game_info.dart';
import 'package:board_game_agent/models/remote_asset_file.dart';
import 'package:board_game_agent/services/ai_service.dart';
import 'package:board_game_agent/services/game_manifest_service.dart';
import 'package:board_game_agent/services/preferences_service.dart';
import 'package:board_game_agent/services/remote_asset_service.dart';
import 'package:board_game_agent/services/speech_service.dart';
import 'package:board_game_agent/services/tts_service.dart';
import 'package:board_game_agent/state/app_controller.dart';
import 'package:board_game_agent/ui/screens/desktop_workspace_screen.dart';

import 'package:board_game_agent/ui/v4/v4_workspace.dart';
import 'package:board_game_agent/ui/v4/v4_theme.dart';
import 'package:board_game_agent/ui/v4/v4_sidebar.dart';
import 'package:board_game_agent/ui/v4/v4_home.dart';
import 'package:board_game_agent/ui/v4/v4_games.dart';
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

  testWidgets('rules library remains reachable and shows real rule resources', (
    tester,
  ) async {
    await _mount(tester, controller, const Size(1280, 800));
    await tester.tap(find.text('规则查询'));
    await tester.pumpAndSettle();
    expect(find.byType(DesktopWorkspaceScreen), findsOneWidget);
    final state = tester.state<DesktopWorkspaceScreenState>(
      find.byType(DesktopWorkspaceScreen),
    );
    expect(state.destinationName, 'library');
    expect(controller.games, isNotEmpty);
    expect(find.byType(V4HomePane), findsNothing);
    expect(tester.takeException(), isNull);
    await _navigate(tester, '首页');
    expect(find.byType(V4HomePane), findsOneWidget);
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
  await tester.tap(
    find.descendant(of: find.byType(V4Sidebar), matching: find.text(label)),
  );
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
