import 'dart:convert';

import 'package:app_ai_client/app_ai_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:board_game_agent/models/ai_answer_mode.dart';
import 'package:board_game_agent/models/ai_api_config.dart';
import 'package:board_game_agent/models/ai_run.dart';
import 'package:board_game_agent/models/answer_source.dart';
import 'package:board_game_agent/models/app_language.dart';
import 'package:board_game_agent/models/asset_source_config.dart';
import 'package:board_game_agent/models/board_game_ai_answer.dart';
import 'package:board_game_agent/models/chat_message.dart';
import 'package:board_game_agent/models/game_info.dart';
import 'package:board_game_agent/models/game_resource.dart';
import 'package:board_game_agent/services/ai_service.dart';
import 'package:board_game_agent/services/remote_asset_service.dart';
import 'package:board_game_agent/services/responses_compaction_store.dart';
import 'package:board_game_agent/services/responses_rules_workflow.dart';
import 'package:board_game_agent/services/ai_run_telemetry.dart';

part 'responses_workflow/knowledge_test_cases.dart';
part 'responses_workflow/streaming_test_cases.dart';
part 'responses_workflow/context_test_cases.dart';
part 'responses_workflow/telemetry_test_cases.dart';

void main() {
  _registerKnowledgeWorkflowTests();
  _registerStreamingWorkflowTests();
  _registerContextWorkflowTests();
  _registerTelemetryWorkflowTests();
}

AiApiConfig _config() => const AiApiConfig(
  name: 'OpenAI',
  baseUrl: 'https://example.test/v1',
  apiKey: 'test-key',
  model: 'test-model',
  apiKeyHeader: 'Authorization',
);

GameInfo _game() => GameInfo(
  id: 'puerto-rico',
  slug: 'puerto_rico',
  title: '波多黎各',
  subtitle: 'Puerto Rico',
  coverAssetPath: 'assets/games/puerto_rico/images/cover.jpg',
  bannerAssetPath: 'assets/games/puerto_rico/images/background.jpg',
  cardAccent: 0,
  score: '8.3',
  scoreCountLabel: '0',
  releaseYear: '2020',
  categoryLine: '竞争',
  learningDifficulty: '中等',
  perPlayerTime: '35 分钟',
  setupTime: '10 分钟',
  languageRequirement: '适中',
  supportedPlayers: const <int>[2, 3, 4, 5],
  recommendedPlayer: 4,
  rankBadges: const <String>[],
  rulebookAssetPath: 'assets/games/puerto_rico/docs/rulebook_zh.md',
  faqAssetPath: 'assets/games/puerto_rico/docs/faq_zh.md',
  knowledgeAssetPaths: const <String>[
    'assets/games/puerto_rico/docs/rulebook_zh.md',
    'assets/games/puerto_rico/docs/faq_zh.md',
  ],
  heroTagline: '',
  assistantIntro: '',
  summary: '',
  mentorPitch: '',
  playTime: '90 分钟',
  playerCount: '2-5',
  complexity: '中等',
  roundFlow: const <String>[],
  assistantSkills: const <String>[],
  quickPrompts: const <String>[],
);

GameInfo _gameWithSources() => GameInfo(
  id: 'demo',
  slug: 'demo',
  title: 'Demo',
  subtitle: 'Demo',
  coverAssetPath: '',
  bannerAssetPath: '',
  cardAccent: 0,
  score: '',
  scoreCountLabel: '',
  releaseYear: '',
  categoryLine: '',
  learningDifficulty: '',
  perPlayerTime: '',
  setupTime: '',
  languageRequirement: '',
  supportedPlayers: const <int>[2],
  recommendedPlayer: 2,
  rankBadges: const <String>[],
  rulebookAssetPath: 'assets/games/demo/docs/local/knowledge/rulebook_en.md',
  faqAssetPath: '',
  knowledgeAssetPaths: const <String>[
    'assets/games/demo/docs/local/knowledge/rulebook_en.md',
    'assets/games/demo/docs/community/answers/ruling_cn.md',
  ],
  resources: <GameResource>[
    _testResource(
      id: 'official-rulebook',
      path: 'docs/local/knowledge/rulebook_en.md',
      sourceClass: 'official_extracted',
    ),
    _testResource(
      id: 'community-ruling',
      path: 'docs/community/answers/ruling_cn.md',
      sourceClass: 'community',
    ),
  ],
  heroTagline: '',
  assistantIntro: '',
  summary: '',
  mentorPitch: '',
  playTime: '',
  playerCount: '',
  complexity: '',
  roundFlow: const <String>[],
  assistantSkills: const <String>[],
  quickPrompts: const <String>[],
);

GameResource _testResource({
  required String id,
  required String path,
  required String sourceClass,
}) => GameResource(
  id: id,
  path: path,
  documentType: 'rulebook',
  sourceClass: sourceClass,
  origin: 'test',
  language: 'en',
  edition: 'test',
  status: 'available',
  enabled: true,
  aiEnabled: true,
  priority: 1,
  derivedFrom: const <String>[],
  sourceUrl: null,
  reviewStatus: 'checked',
  notes: null,
);

ResponsesResponse _response(String text) =>
    ResponsesResponse(text: text, model: 'test-model');

class _FakeRemoteAssetService extends RemoteAssetService {
  _FakeRemoteAssetService();

  @override
  Future<List<int>?> loadBytes({
    required List<AssetSourceConfig> sources,
    required String remotePath,
  }) async => utf8.encode(remotePath);
}

class _UnavailableRemoteAssetService extends RemoteAssetService {
  _UnavailableRemoteAssetService();

  @override
  Future<String?> loadText({
    required List<AssetSourceConfig> sources,
    required String remotePath,
  }) async => null;

  @override
  Future<List<int>?> loadBytes({
    required List<AssetSourceConfig> sources,
    required String remotePath,
  }) async => null;
}

class _FakeResponsesClient implements ResponsesAiClient {
  _FakeResponsesClient({
    required this.responses,
    this.streams = const [],
    this.onComplete,
  });

  final List<ResponsesResponse> responses;
  final List<List<ResponsesStreamEvent>> streams;
  final ResponsesResponse Function(
    ResponsesRequest request,
    List<ResponsesResponse> responses,
  )?
  onComplete;
  final List<ResponsesRequest> requests = <ResponsesRequest>[];

  int get completeRequests => requests.length;

  @override
  Future<ResponsesResponse> complete(
    ResponsesRequest request, {
    Future<void>? abortTrigger,
  }) async {
    requests.add(request);
    if (onComplete != null) return onComplete!(request, responses);
    return responses.removeAt(0);
  }

  @override
  Stream<ResponsesStreamEvent> stream(
    ResponsesRequest request, {
    Future<void>? abortTrigger,
  }) async* {
    requests.add(request);
    if (streams.isNotEmpty) {
      yield* Stream<ResponsesStreamEvent>.fromIterable(streams.removeAt(0));
      return;
    }
    yield ResponsesStreamEvent.completed(responses.removeAt(0));
  }

  @override
  void close() {}
}

class _TerminalThenErrorResponsesClient implements ResponsesAiClient {
  _TerminalThenErrorResponsesClient(this.payload);

  final String payload;
  int streamRequests = 0;

  @override
  Future<ResponsesResponse> complete(
    ResponsesRequest request, {
    Future<void>? abortTrigger,
  }) async {
    throw UnsupportedError('This test only exercises streaming.');
  }

  @override
  Stream<ResponsesStreamEvent> stream(
    ResponsesRequest request, {
    Future<void>? abortTrigger,
  }) async* {
    streamRequests += 1;
    yield ResponsesStreamEvent.text(payload);
    yield ResponsesStreamEvent.textDone(payload);
    yield ResponsesStreamEvent.completed(
      ResponsesResponse(text: payload, model: 'test-model'),
    );
    throw const AiTransportException('connection reset after completion');
  }

  @override
  void close() {}
}

class _FailingTelemetrySink implements AiRunTelemetrySink {
  @override
  Future<void> record(AiRunResult result) async {
    throw StateError('telemetry unavailable');
  }
}
