import 'dart:io';

import 'package:app_ai_client/app_ai_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:board_game_agent/models/ai_api_config.dart';
import 'package:board_game_agent/models/ai_answer_mode.dart';
import 'package:board_game_agent/models/asset_source_config.dart';
import 'package:board_game_agent/models/app_language.dart';
import 'package:board_game_agent/models/board_game_ai_answer.dart';
import 'package:board_game_agent/models/chat_message.dart';
import 'package:board_game_agent/models/cached_asset.dart';
import 'package:board_game_agent/models/game_info.dart';
import 'package:board_game_agent/models/answer_source.dart';
import 'package:board_game_agent/services/ai_service.dart';
import 'package:board_game_agent/services/game_manifest_service.dart';
import 'package:board_game_agent/services/preferences_service.dart';
import 'package:board_game_agent/services/remote_asset_service.dart';
import 'package:board_game_agent/services/speech_service.dart';
import 'package:board_game_agent/services/tts_service.dart';
import 'package:board_game_agent/state/app_controller.dart';
import 'package:board_game_agent/theme/app_theme.dart';
import 'package:board_game_agent/theme/palette_registry.dart';
import 'package:board_game_agent/ui/screens/desktop_game_detail_pane.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('detail hero remains visible at desktop widths', (
    WidgetTester tester,
  ) async {
    final AppController controller = await _createController();

    for (final double width in <double>[900, 1280, 3840]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.buildTheme(PaletteRegistry.classic),
          home: SizedBox(
            width: width,
            height: 900,
            child: DesktopGameDetailPane(
              controller: controller,
              game: controller.games.firstWhere(
                (GameInfo game) => game.id == 'startups',
              ),
              onBack: () {},
              onAskAi: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'width=$width');
      expect(find.text('初创公司'), findsWidgets, reason: 'width=$width');
      expect(find.text('评分'), findsOneWidget, reason: 'width=$width');
      expect(find.text('询问 AI'), findsOneWidget, reason: 'width=$width');
      expect(find.text('游戏简介'), findsOneWidget, reason: 'width=$width');
      final Size contentSize = tester.getSize(
        find.byKey(const ValueKey<String>('desktop-detail-content')),
      );
      expect(
        contentSize.width,
        lessThanOrEqualTo(1600),
        reason: 'width=$width',
      );
      final Finder hero = find.byKey(
        const ValueKey<String>('desktop-detail-hero'),
      );
      expect(hero, findsOneWidget, reason: 'width=$width');
      expect(
        tester.getSize(hero).width,
        greaterThan(0),
        reason: 'width=$width',
      );
    }
  });
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
  // Loading the bundled manifests is enough for this page test. Avoid the
  // controller's startup speech/TTS and remote polling tasks so the test is
  // deterministic and cannot be held open by a platform channel or timer.
  await controller.reloadGames();
  return controller;
}

class _NoNetworkAssetService extends RemoteAssetService {
  _NoNetworkAssetService() : super(client: _NoopHttpClient());

  @override
  Future<File?> cachedFileFor(String remotePath) async {
    return null;
  }

  @override
  Future<CachedAsset?> ensureCached({
    required List<AssetSourceConfig> sources,
    required String remotePath,
    bool forceRefresh = false,
    bool allowCachedFallback = true,
  }) async {
    return null;
  }

  @override
  Future<String?> fetchRemoteText({
    required List<AssetSourceConfig> sources,
    required String remotePath,
  }) async {
    return null;
  }

  @override
  Future<bool> hasRemoteChanged({
    required List<AssetSourceConfig> sources,
    required String remotePath,
  }) async {
    return false;
  }
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
