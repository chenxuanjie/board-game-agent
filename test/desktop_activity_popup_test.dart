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
import 'package:board_game_agent/ui/desktop/theme.dart';
import 'package:board_game_agent/ui/desktop/workspace.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('activity popup keeps empty state and adapts to window width', (
    WidgetTester tester,
  ) async {
    final AppController controller = await _createController();
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final MapEntry<Size, double> testCase in <MapEntry<Size, double>>[
      const MapEntry<Size, double>(Size(1440, 900), 340),
      const MapEntry<Size, double>(Size(823, 900), 300),
      const MapEntry<Size, double>(Size(640, 480), 300),
    ]) {
      final Size size = testCase.key;
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(_buildApp(controller));
      await tester.pumpAndSettle();

      expect(find.byTooltip('通知'), findsOneWidget, reason: 'size=$size');
      await tester.tap(find.byTooltip('通知'));
      await tester.pumpAndSettle();

      final Finder panel = find.byKey(
        const ValueKey<String>('desktop-activity-popup'),
      );
      expect(panel, findsOneWidget, reason: 'size=$size');
      expect(
        find.descendant(of: panel, matching: find.text('暂无消息')),
        findsOneWidget,
        reason: 'size=$size',
      );
      expect(
        find.descendant(of: panel, matching: find.text('刷新服务状态')),
        findsNothing,
        reason: 'size=$size',
      );
      final Size panelSize = tester.getSize(panel);
      expect(panelSize.width, greaterThan(0), reason: 'size=$size');
      expect(
        panelSize.width,
        lessThanOrEqualTo(testCase.value),
        reason: 'size=$size',
      );
      expect(
        panelSize.height,
        lessThanOrEqualTo(size.height - 24),
        reason: 'size=$size',
      );
      expect(tester.takeException(), isNull, reason: 'size=$size');

      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
    }
  });
}

Widget _buildApp(AppController controller) {
  return MaterialApp(
    theme: buildDesktopTheme(),
    home: DesktopWorkspace(controller: controller, onOpenAbout: () {}),
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
