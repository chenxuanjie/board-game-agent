import 'dart:io';

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
import 'package:board_game_agent/theme/app_theme.dart';
import 'package:board_game_agent/theme/palette_registry.dart';
import 'package:board_game_agent/ui/screens/desktop_workspace_screen.dart';
import 'package:board_game_agent/ui/screens/markdown_document_screen.dart';
import 'package:board_game_agent/ui/screens/pdf_document_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppController controller;

  setUpAll(() async {
    controller = await _createController();
  });
  tearDownAll(() => controller.dispose());

  testWidgets('desktop search filters games and opens the selected detail', (
    WidgetTester tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    controller.selectGame('puerto-rico');
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    await tester.pumpWidget(_buildApp(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('desktop-search-dialog')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('desktop-search-field')),
      'Startups',
    );
    expect(
      find.byKey(const ValueKey<String>('desktop-search-result-startups')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('desktop-search-result-startups')),
    );
    await tester.pumpAndSettle();

    expect(find.text('桌游详情'), findsOneWidget);
    expect(find.text('初创公司'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('recent games view all opens the games destination', (
    WidgetTester tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    controller.selectGame('puerto-rico');
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    await tester.pumpWidget(_buildApp(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('查看全部'));
    await tester.pumpAndSettle();

    expect(find.byType(GridView), findsOneWidget);
    expect(find.text('我的游戏'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('library more opens the rulebook document viewer', (
    WidgetTester tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    controller.selectGame('puerto-rico');
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    await tester.pumpWidget(_buildApp(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('资料库').first);
    await tester.pumpAndSettle();
    final Finder more = find.byKey(const ValueKey<String>('library-more-0'));
    expect(more, findsOneWidget);
    await tester.tap(more);
    await tester.pumpAndSettle();
    expect(find.text('打开'), findsOneWidget);
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.byType(PdfDocumentScreen), findsOneWidget);
    expect(find.text('波多黎各 · 官方规则书'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('library more opens the FAQ document viewer', (
    WidgetTester tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    controller.selectGame('puerto-rico');
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    await tester.pumpWidget(_buildApp(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('资料库').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('library-more-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.byType(MarkdownDocumentScreen), findsOneWidget);
    expect(find.text('波多黎各 · 官方 FAQ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _buildApp(AppController controller) {
  return MaterialApp(
    theme: AppTheme.buildTheme(PaletteRegistry.classic),
    home: DesktopWorkspaceScreen(controller: controller, onOpenAbout: () {}),
  );
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
