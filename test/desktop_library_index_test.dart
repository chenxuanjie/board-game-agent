import 'dart:io';

import 'package:app_ai_client/app_ai_client.dart';
import 'package:board_game_agent/models/ai_answer_mode.dart';
import 'package:board_game_agent/models/ai_api_config.dart';
import 'package:board_game_agent/models/app_language.dart';
import 'package:board_game_agent/models/answer_source.dart';
import 'package:board_game_agent/models/app_activity.dart';
import 'package:board_game_agent/models/asset_source_config.dart';
import 'package:board_game_agent/models/board_game_ai_answer.dart';
import 'package:board_game_agent/models/cached_asset.dart';
import 'package:board_game_agent/models/chat_message.dart';
import 'package:board_game_agent/models/desktop_library_resource.dart';
import 'package:board_game_agent/models/game_info.dart';
import 'package:board_game_agent/models/remote_asset_file.dart';
import 'package:board_game_agent/services/ai_service.dart';
import 'package:board_game_agent/services/game_manifest_service.dart';
import 'package:board_game_agent/services/preferences_service.dart';
import 'package:board_game_agent/services/remote_asset_service.dart';
import 'package:board_game_agent/services/speech_service.dart';
import 'package:board_game_agent/services/tts_service.dart';
import 'package:board_game_agent/state/app_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('desktop library reads manifests without downloading documents', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final _ManifestAssetService remote = _ManifestAssetService(<String, String>{
      'assets/catalog.json':
          '{"version":1,"games":[{"slug":"puerto_rico","order":10,"enabled":true}]}',
      'assets/games/puerto_rico/manifest.json': '''
{
  "schemaVersion": 3,
  "game": {"slug": "puerto_rico", "title": {"cn": "波多黎各"}},
  "resources": [
    {"id":"rulebook-cn","path":"docs/local/knowledge/rulebook_cn.md","documentType":"rulebook","language":"cn","status":"available","enabled":true},
    {"id":"reference-en","path":"docs/official/rules/rules_reference_en.pdf","documentType":"rules_reference","language":"en","status":"available","enabled":true},
    {"id":"page-en","path":"docs/official/other/page_en.html","documentType":"official_page","language":"en","status":"available","enabled":true},
    {"id":"raw","path":"docs/others/raw/private.md","documentType":"other","language":"cn","status":"available","enabled":true},
    {"id":"disabled","path":"docs/local/knowledge/disabled.md","documentType":"other","language":"cn","status":"available","enabled":false},
    {"id":"missing","path":"docs/local/knowledge/missing.md","documentType":"other","language":"cn","status":"missing","enabled":true}
  ]
}
''',
    });
    final AppController controller = AppController(
      preferencesService: PreferencesService(),
      aiService: _FakeAiService(),
      gameManifestService: GameManifestService(),
      remoteAssetService: remote,
      speechService: SpeechService(),
      ttsService: TtsService(),
    );
    addTearDown(controller.dispose);

    await controller.reloadGames();
    await controller.refreshLibraryResources();

    expect(controller.libraryLoadState, LibraryLoadState.success);
    expect(controller.libraryResources, hasLength(3));
    expect(
      controller.libraryResources.map((resource) => resource.remotePath),
      isNot(contains('docs/others/raw/private.md')),
    );
    final DesktopLibraryResource reference = controller.libraryResources
        .singleWhere((resource) => resource.id == 'reference-en');
    expect(reference.type, DesktopLibraryResourceType.other);
    expect(reference.typeLabel, '其他');
    expect(reference.language, '英文');
    expect(reference.canOpen, isTrue);
    expect(remote.cachedPaths, isEmpty);
    expect(remote.listCalled, isFalse);
  });

  test(
    'desktop library keeps the persisted index when remote refresh fails',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final Map<String, String> manifestResponses = <String, String>{
        'assets/catalog.json':
            '{"version":1,"games":[{"slug":"puerto_rico","order":10,"enabled":true}]}',
        'assets/games/puerto_rico/manifest.json': '''
{
  "schemaVersion": 3,
  "game": {"slug": "puerto_rico", "title": {"cn": "波多黎各"}},
  "resources": [
    {"id":"rulebook-cn","path":"docs/local/knowledge/rulebook_cn.md","documentType":"rulebook","language":"cn","status":"available","enabled":true},
    {"id":"faq-cn","path":"docs/local/knowledge/faq_cn.md","documentType":"faq","language":"cn","status":"available","enabled":true}
  ]
}
''',
      };
      final AppController first = _createController(
        _ManifestAssetService(manifestResponses),
      );
      await first.reloadGames();
      await first.refreshLibraryResources();
      expect(first.libraryResources, hasLength(2));
      first.dispose();

      final _ManifestAssetService offline = _ManifestAssetService(
        <String, String>{},
      );
      final AppController second = _createController(offline);
      addTearDown(second.dispose);
      await second.reloadGames();
      await second.refreshLibraryResources();

      expect(second.libraryLoadState, LibraryLoadState.failure);
      expect(second.libraryResources, hasLength(2));
      expect(offline.cachedPaths, isEmpty);
      expect(
        second.activities.where(
          (activity) => activity.kind == AppActivityKind.libraryLoadFailed,
        ),
        hasLength(1),
      );
      final AppActivity firstFailure = second.activities.singleWhere(
        (activity) => activity.kind == AppActivityKind.libraryLoadFailed,
      );
      await second.markActivitiesRead();
      await Future<void>.delayed(const Duration(milliseconds: 2));

      await second.refreshLibraryResources(force: true);
      final List<AppActivity> failures = second.activities
          .where(
            (activity) => activity.kind == AppActivityKind.libraryLoadFailed,
          )
          .toList(growable: false);
      expect(failures, hasLength(1));
      expect(
        failures.single.id,
        firstFailure.id,
        reason: 'the notification row keeps its stable identity',
      );
      expect(
        failures.single.createdAt.isAfter(firstFailure.createdAt),
        isTrue,
        reason: 'a repeated failure updates the visible occurrence time',
      );
      expect(failures.single.isRead, isFalse);
    },
  );
}

AppController _createController(RemoteAssetService remote) {
  return AppController(
    preferencesService: PreferencesService(),
    aiService: _FakeAiService(),
    gameManifestService: GameManifestService(),
    remoteAssetService: remote,
    speechService: SpeechService(),
    ttsService: TtsService(),
  );
}

class _ManifestAssetService extends RemoteAssetService {
  _ManifestAssetService(this.responses) : super(client: _NoopHttpClient());

  final Map<String, String> responses;
  final List<String> fetchedPaths = <String>[];
  final List<String> cachedPaths = <String>[];
  bool listCalled = false;

  @override
  Future<File?> cachedFileFor(String remotePath) async => null;

  @override
  Future<CachedAsset?> ensureCached({
    required List<AssetSourceConfig> sources,
    required String remotePath,
    bool forceRefresh = false,
    bool allowCachedFallback = true,
  }) async {
    cachedPaths.add(remotePath);
    return null;
  }

  @override
  Future<String?> fetchRemoteText({
    required List<AssetSourceConfig> sources,
    required String remotePath,
  }) async {
    fetchedPaths.add(remotePath);
    return responses[remotePath];
  }

  @override
  Future<List<RemoteAssetFile>> listFilesRecursively({
    required List<AssetSourceConfig> sources,
    required String remotePath,
    int maxDepth = 6,
    int maxEntries = 1000,
  }) async {
    listCalled = true;
    return const <RemoteAssetFile>[];
  }

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
