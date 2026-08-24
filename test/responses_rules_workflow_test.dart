import 'dart:convert';

import 'package:app_ai_client/app_ai_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:board_game_agent/models/ai_answer_mode.dart';
import 'package:board_game_agent/models/ai_api_config.dart';
import 'package:board_game_agent/models/app_language.dart';
import 'package:board_game_agent/models/asset_source_config.dart';
import 'package:board_game_agent/models/chat_message.dart';
import 'package:board_game_agent/models/game_info.dart';
import 'package:board_game_agent/services/remote_asset_service.dart';
import 'package:board_game_agent/services/responses_rules_workflow.dart';

void main() {
  test(
    'falls back from insufficient official material to community material',
    () async {
      final _FakeResponsesClient client = _FakeResponsesClient(
        responses: <ResponsesResponse>[
          _response('{"status":"insufficient","answer":"","sourceIds":[]}'),
          _response(
            '{"status":"answered","answer":"社区资料回答","sourceIds":["community-faq"]}',
          ),
        ],
      );
      final ResponsesRulesWorkflow workflow = ResponsesRulesWorkflow(
        responsesClient: client,
      );

      final answer = await workflow.generateReply(
        prompt: '社区问题',
        language: AppLanguage.zhHans,
        game: _game(),
        answerMode: AiAnswerMode.knowledgeThenDirect,
        useGlobalMode: false,
        config: _config(),
        assetSourceConfigs: const <AssetSourceConfig>[],
        remoteAssetService: _FakeRemoteAssetService(),
        conversationHistory: const <ChatMessage>[],
      );

      expect(answer.text, '社区资料回答');
      expect(answer.source.name, 'community');
      expect(answer.citations.single.sourceId, 'community-faq');
      expect(client.completeRequests, 2);
      expect(client.requests[0].tools, isEmpty);
      expect(client.requests[1].tools, isEmpty);
    },
  );

  test('knowledgeOnly stops before web search and model knowledge', () async {
    final _FakeResponsesClient client = _FakeResponsesClient(
      responses: <ResponsesResponse>[
        _response('{"status":"insufficient","answer":"","sourceIds":[]}'),
        _response('{"status":"insufficient","answer":"","sourceIds":[]}'),
      ],
    );
    final ResponsesRulesWorkflow workflow = ResponsesRulesWorkflow(
      responsesClient: client,
    );

    final answer = await workflow.generateReply(
      prompt: '没有资料的问题',
      language: AppLanguage.zhHans,
      game: _game(),
      answerMode: AiAnswerMode.knowledgeOnly,
      useGlobalMode: false,
      config: _config(),
      assetSourceConfigs: const <AssetSourceConfig>[],
      remoteAssetService: _FakeRemoteAssetService(),
      conversationHistory: const <ChatMessage>[],
    );

    expect(answer.source.name, 'insufficient');
    expect(client.completeRequests, 2);
    expect(
      client.requests.every((ResponsesRequest item) => item.tools.isEmpty),
      isTrue,
    );
  });

  test('uses web citations before the model-knowledge fallback', () async {
    final _FakeResponsesClient client = _FakeResponsesClient(
      responses: <ResponsesResponse>[
        _response('{"status":"insufficient","answer":"","sourceIds":[]}'),
        _response('{"status":"insufficient","answer":"","sourceIds":[]}'),
        ResponsesResponse(
          text: '联网资料回答',
          model: 'test-model',
          webSearchCitations: const <ResponsesWebSearchCitation>[
            ResponsesWebSearchCitation(
              url: 'https://example.test/rules',
              title: '可信规则页面',
            ),
          ],
        ),
      ],
    );
    final ResponsesRulesWorkflow workflow = ResponsesRulesWorkflow(
      responsesClient: client,
    );

    final answer = await workflow.generateReply(
      prompt: '网页问题',
      language: AppLanguage.zhHans,
      game: _game(),
      answerMode: AiAnswerMode.knowledgeThenDirect,
      useGlobalMode: false,
      config: _config(),
      assetSourceConfigs: const <AssetSourceConfig>[],
      remoteAssetService: _FakeRemoteAssetService(),
      conversationHistory: const <ChatMessage>[],
    );

    expect(answer.source.name, 'web');
    expect(answer.citations.single.url, 'https://example.test/rules');
    expect(client.completeRequests, 3);
    expect(client.requests[2].tools.single.kind, ResponsesToolKind.webSearch);
  });

  test(
    'falls back to model knowledge when web search has no citations',
    () async {
      final _FakeResponsesClient client = _FakeResponsesClient(
        responses: <ResponsesResponse>[
          _response('{"status":"insufficient","answer":"","sourceIds":[]}'),
          _response('{"status":"insufficient","answer":"","sourceIds":[]}'),
          _response('没有可靠联网依据'),
          _response('根据通用知识谨慎回答'),
        ],
      );
      final ResponsesRulesWorkflow workflow = ResponsesRulesWorkflow(
        responsesClient: client,
      );

      final answer = await workflow.generateReply(
        prompt: '兜底问题',
        language: AppLanguage.zhHans,
        game: _game(),
        answerMode: AiAnswerMode.knowledgeThenDirect,
        useGlobalMode: false,
        config: _config(),
        assetSourceConfigs: const <AssetSourceConfig>[],
        remoteAssetService: _FakeRemoteAssetService(),
        conversationHistory: const <ChatMessage>[],
      );

      expect(answer.text, '根据通用知识谨慎回答');
      expect(answer.source.name, 'modelKnowledge');
      expect(client.completeRequests, 4);
      expect(client.requests[2].tools.single.kind, ResponsesToolKind.webSearch);
      expect(client.requests[3].tools, isEmpty);
    },
  );

  test('normalizes file and web citations without inventing locations', () {
    const ResponsesFileInput file = ResponsesFileInput.data(
      'AQI=',
      mediaType: 'application/pdf',
      filename: 'rules.pdf',
    );
    expect(file.toJson()['content'], isA<List<dynamic>>());
    final Map<String, dynamic> content =
        (file.toJson()['content'] as List<dynamic>).single
            as Map<String, dynamic>;
    expect(content['type'], 'input_file');
    expect(content['filename'], 'rules.pdf');
    expect(content['file_data'], startsWith('data:application/pdf;base64,'));
  });
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
  knowledgeAssetPaths: const <String>[],
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

ResponsesResponse _response(String text) =>
    ResponsesResponse(text: text, model: 'test-model');

class _FakeRemoteAssetService extends RemoteAssetService {
  _FakeRemoteAssetService();

  static const String _catalog = '''
{
  "version": 1,
  "games": {
    "puerto_rico": {
      "official": [{"id":"official-rulebook","title":"Official","path":"official.md","format":"md","language":"en"}],
      "community": [{"id":"community-faq","title":"Community FAQ","path":"community.md","format":"md","language":"en"}],
      "terms": {"市长阶段": ["Mayor phase"]}
    }
  }
}
''';

  @override
  Future<String?> loadText({
    required List<AssetSourceConfig> sources,
    required String remotePath,
  }) async {
    return remotePath == 'rule_sources.json' ? _catalog : null;
  }

  @override
  Future<String?> fetchRemoteText({
    required List<AssetSourceConfig> sources,
    required String remotePath,
  }) async => null;

  @override
  Future<List<int>?> loadBytes({
    required List<AssetSourceConfig> sources,
    required String remotePath,
  }) async => utf8.encode(remotePath);
}

class _FakeResponsesClient implements ResponsesAiClient {
  _FakeResponsesClient({required this.responses});

  final List<ResponsesResponse> responses;
  final List<ResponsesRequest> requests = <ResponsesRequest>[];

  int get completeRequests => requests.length;

  @override
  Future<ResponsesResponse> complete(
    ResponsesRequest request, {
    Future<void>? abortTrigger,
  }) async {
    requests.add(request);
    return responses.removeAt(0);
  }

  @override
  Stream<ResponsesStreamEvent> stream(
    ResponsesRequest request, {
    Future<void>? abortTrigger,
  }) async* {
    requests.add(request);
    yield ResponsesStreamEvent.completed(responses.removeAt(0));
  }

  @override
  void close() {}
}
