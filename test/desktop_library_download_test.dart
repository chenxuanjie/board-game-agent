import 'dart:io';

import 'package:app_ai_client/app_ai_client.dart';
import 'package:board_game_agent/features/assistant/models/ai_answer_mode.dart';
import 'package:board_game_agent/features/assistant/models/ai_api_config.dart';
import 'package:board_game_agent/core/localization/app_language.dart';
import 'package:board_game_agent/features/assistant/models/answer_source.dart';
import 'package:board_game_agent/features/library/models/asset_source_config.dart';
import 'package:board_game_agent/features/assistant/models/board_game_ai_answer.dart';
import 'package:board_game_agent/features/library/models/cached_asset.dart';
import 'package:board_game_agent/features/assistant/models/chat_message.dart';
import 'package:board_game_agent/features/library/models/desktop_library_resource.dart';
import 'package:board_game_agent/features/games/models/game_info.dart';
import 'package:board_game_agent/features/assistant/services/ai_service.dart';
import 'package:board_game_agent/features/games/services/game_manifest_service.dart';
import 'package:board_game_agent/features/settings/services/preferences_service.dart';
import 'package:board_game_agent/features/library/services/remote_asset_service.dart';
import 'package:board_game_agent/features/assistant/services/speech_service.dart';
import 'package:board_game_agent/features/assistant/services/tts_service.dart';
import 'package:board_game_agent/app/state/app_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('download name follows the current language', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final Directory tempDirectory = await Directory.systemTemp.createTemp(
      'board-game-library-download-',
    );
    final File source = File('${tempDirectory.path}/rulebook_en.pdf');
    await source.writeAsBytes(<int>[1, 2, 3], flush: true);
    final _DownloadAssetService remote = _DownloadAssetService(source);
    final AppController controller = AppController(
      preferencesService: PreferencesService(),
      aiService: _FakeAiService(),
      gameManifestService: GameManifestService(),
      remoteAssetService: remote,
      speechService: SpeechService(),
      ttsService: TtsService(),
    );
    addTearDown(() async {
      controller.dispose();
      await tempDirectory.delete(recursive: true);
    });

    await controller.reloadGames();
    final DesktopLibraryResource resource = DesktopLibraryResource(
      id: 'seven-wonders-rulebook',
      gameSlug: 'seven_wonders_duel',
      gameTitle: '旧名称',
      remotePath: 'assets/games/seven_wonders_duel/docs/rulebook_en.pdf',
      title: '规则书',
      language: '英文',
      type: DesktopLibraryResourceType.rulebook,
      format: DesktopLibraryResourceFormat.pdf,
      isRemote: true,
    );

    final String? chinesePath = await controller.downloadLibraryResource(
      resource: resource,
      directoryPath: tempDirectory.path,
    );
    expect(chinesePath, endsWith('七大奇迹 对决 · 规则书.pdf'));

    await controller.setLanguage(AppLanguage.en);
    final String? englishPath = await controller.downloadLibraryResource(
      resource: resource,
      directoryPath: tempDirectory.path,
    );
    expect(englishPath, endsWith('7 Wonders Duel · Rulebook.pdf'));
  });
}

class _DownloadAssetService extends RemoteAssetService {
  _DownloadAssetService(this.source) : super(client: _NoopHttpClient());

  final File source;

  @override
  Future<File?> cachedFileFor(String remotePath) async => null;

  @override
  Future<CachedAsset?> ensureCached({
    required List<AssetSourceConfig> sources,
    required String remotePath,
    bool forceRefresh = false,
    bool allowCachedFallback = true,
  }) async {
    return CachedAsset(
      remotePath: remotePath,
      localPath: source.path,
      exists: await source.exists(),
      fromRemote: true,
      sourceId: 'test',
    );
  }
}

class _NoopHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return Future<http.StreamedResponse>.error(
      StateError('network disabled for unit test'),
    );
  }
}

class _FakeAiService implements AiService {
  @override
  Future<List<AiModel>> listModels(AiApiConfig config) async => const [];

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
  }) async =>
      BoardGameAiAnswer(text: 'test', source: AnswerSource.generalAdvice);

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
