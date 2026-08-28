import 'dart:convert';

import 'package:app_ai_client/app_ai_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:board_game_agent/models/ai_answer_mode.dart';
import 'package:board_game_agent/models/ai_api_config.dart';
import 'package:board_game_agent/models/answer_source.dart';
import 'package:board_game_agent/models/app_language.dart';
import 'package:board_game_agent/models/asset_source_config.dart';
import 'package:board_game_agent/models/board_game_ai_answer.dart';
import 'package:board_game_agent/models/chat_message.dart';
import 'package:board_game_agent/models/game_info.dart';
import 'package:board_game_agent/services/ai_service.dart';
import 'package:board_game_agent/services/remote_asset_service.dart';
import 'package:board_game_agent/services/responses_compaction_store.dart';
import 'package:board_game_agent/services/responses_rules_workflow.dart';

void main() {
  test('uses the selected game knowledge paths as official documents', () async {
    final _FakeResponsesClient client = _FakeResponsesClient(
      responses: <ResponsesResponse>[
        _response(
          '{"status":"answered","answer":"本地规则回答","sourceIds":["puerto_rico-knowledge-0"]}',
        ),
      ],
    );
    final ResponsesRulesWorkflow workflow = ResponsesRulesWorkflow(
      responsesClient: client,
    );

    final answer = await workflow.generateReply(
      prompt: '本地资料问题',
      language: AppLanguage.zhHans,
      game: _game(),
      answerMode: AiAnswerMode.knowledgeThenDirect,
      useGlobalMode: false,
      config: _config(),
      assetSourceConfigs: const <AssetSourceConfig>[],
      remoteAssetService: _FakeRemoteAssetService(),
      conversationHistory: const <ChatMessage>[],
    );

    expect(answer.text, '本地规则回答');
    expect(answer.source.name, 'official');
    expect(answer.citations.single.sourceId, 'puerto_rico-knowledge-0');
    expect(client.completeRequests, 1);
    expect(
      client.requests.single.input.whereType<ResponsesFileInput>(),
      hasLength(2),
    );
  });

  test('knowledgeOnly stops before web search and model knowledge', () async {
    final _FakeResponsesClient client = _FakeResponsesClient(
      responses: <ResponsesResponse>[
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
    expect(client.completeRequests, 1);
    expect(
      client.requests.every((ResponsesRequest item) => item.tools.isEmpty),
      isTrue,
    );
  });

  test(
    'smart supplement answers ordinary questions without documents or web search',
    () async {
      final _FakeResponsesClient client = _FakeResponsesClient(
        responses: <ResponsesResponse>[_response('你好，我可以帮你解答问题。')],
      );
      final ResponsesRulesWorkflow workflow = ResponsesRulesWorkflow(
        responsesClient: client,
      );

      final BoardGameAiAnswer answer = await workflow.generateReply(
        prompt: '你好，你能做什么？',
        language: AppLanguage.zhHans,
        game: _game(),
        answerMode: AiAnswerMode.knowledgeThenDirect,
        useGlobalMode: true,
        config: _config(),
        assetSourceConfigs: const <AssetSourceConfig>[],
        remoteAssetService: _UnavailableRemoteAssetService(),
        conversationHistory: const <ChatMessage>[],
      );

      expect(answer.text, '你好，我可以帮你解答问题。');
      expect(answer.source, AnswerSource.generalAdvice);
      expect(client.completeRequests, 1);
      expect(client.requests.single.tools, isEmpty);
      expect(
        client.requests.single.input.whereType<ResponsesFileInput>(),
        isEmpty,
      );
    },
  );

  test(
    'classifies an ambiguous global prompt before choosing general chat',
    () async {
      final _FakeResponsesClient client = _FakeResponsesClient(
        responses: <ResponsesResponse>[
          _response('{"route":"general","confidence":"high"}'),
          _response('分类后普通回答'),
        ],
      );
      final ResponsesRulesWorkflow workflow = ResponsesRulesWorkflow(
        responsesClient: client,
      );

      final BoardGameAiAnswer answer = await workflow.generateReply(
        prompt: '你最近怎么样？',
        language: AppLanguage.zhHans,
        game: _game(),
        answerMode: AiAnswerMode.knowledgeThenDirect,
        useGlobalMode: true,
        config: _config(),
        assetSourceConfigs: const <AssetSourceConfig>[],
        remoteAssetService: _UnavailableRemoteAssetService(),
        conversationHistory: const <ChatMessage>[],
      );

      expect(answer.text, '分类后普通回答');
      expect(answer.source, AnswerSource.generalAdvice);
      expect(client.completeRequests, 2);
      expect(client.requests.first.structuredOutput, isNotNull);
      expect(client.requests.first.input, hasLength(1));
      expect(client.requests[1].tools, isEmpty);
      expect(client.requests[1].input.whereType<ResponsesFileInput>(), isEmpty);
    },
  );

  test(
    'emits a routing status while classifying an ambiguous stream prompt',
    () async {
      final _FakeResponsesClient client = _FakeResponsesClient(
        responses: <ResponsesResponse>[
          _response('{"route":"general","confidence":"high"}'),
          _response('流式分类后的回答'),
        ],
      );
      final ResponsesRulesWorkflow workflow = ResponsesRulesWorkflow(
        responsesClient: client,
      );

      final List<BoardGameAiStreamEvent> events = await workflow
          .streamReply(
            prompt: '你最近怎么样？',
            language: AppLanguage.zhHans,
            game: _game(),
            answerMode: AiAnswerMode.knowledgeThenDirect,
            useGlobalMode: true,
            config: _config(),
            assetSourceConfigs: const <AssetSourceConfig>[],
            remoteAssetService: _UnavailableRemoteAssetService(),
            conversationHistory: const <ChatMessage>[],
          )
          .toList();

      expect(events.map((event) => event.status), contains('routing'));
      expect(events.map((event) => event.status), contains('answering'));
      expect(events.map((event) => event.delta).join(), '流式分类后的回答');
      expect(events.last.answer?.source, AnswerSource.generalAdvice);
      expect(client.requests, hasLength(2));
      expect(client.requests.first.structuredOutput, isNotNull);
      expect(client.requests.last.tools, isEmpty);
    },
  );

  test('uses web citations before the model-knowledge fallback', () async {
    final _FakeResponsesClient client = _FakeResponsesClient(
      responses: <ResponsesResponse>[
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
    expect(client.completeRequests, 2);
    expect(client.requests[1].tools.single.kind, ResponsesToolKind.webSearch);
  });

  test(
    'falls back to model knowledge when web search has no citations',
    () async {
      final _FakeResponsesClient client = _FakeResponsesClient(
        responses: <ResponsesResponse>[
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
      expect(client.completeRequests, 3);
      expect(client.requests[1].tools.single.kind, ResponsesToolKind.webSearch);
      expect(client.requests[2].tools, isEmpty);
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

  test('sends the most recent twelve conversation messages', () async {
    final _FakeResponsesClient client = _FakeResponsesClient(
      responses: <ResponsesResponse>[
        ResponsesResponse(
          text: '联网资料回答',
          model: 'test-model',
          webSearchCitations: const <ResponsesWebSearchCitation>[
            ResponsesWebSearchCitation(
              url: 'https://example.test/recent-context',
              title: '最近上下文',
            ),
          ],
        ),
      ],
    );
    final ResponsesRulesWorkflow workflow = ResponsesRulesWorkflow(
      responsesClient: client,
    );
    final List<ChatMessage> history = List<ChatMessage>.generate(
      15,
      (int index) => ChatMessage(
        id: 'history-$index',
        role: index.isEven ? ChatRole.user : ChatRole.assistant,
        text: 'history-$index',
        timestamp: DateTime(2026, 1, 1).add(Duration(minutes: index)),
      ),
    );

    await workflow.generateReply(
      prompt: 'current-prompt',
      language: AppLanguage.zhHans,
      game: _game(),
      answerMode: AiAnswerMode.knowledgeThenDirect,
      useGlobalMode: false,
      config: _config(),
      assetSourceConfigs: const <AssetSourceConfig>[],
      remoteAssetService: _UnavailableRemoteAssetService(),
      conversationHistory: history,
    );

    final List<String> inputTexts = client.requests.single.input
        .whereType<ResponsesTextInput>()
        .map((ResponsesTextInput input) => input.text)
        .toList();
    expect(inputTexts, <String>[
      ...List<String>.generate(12, (int index) => 'history-${index + 3}'),
      'current-prompt',
    ]);
    expect(client.requests.single.contextManagement, hasLength(1));
    expect(
      client.requests.single.contextManagement.single.compactThreshold,
      100000,
    );
  });

  test(
    'round trips a server compaction item per conversation context',
    () async {
      final _FakeResponsesClient client = _FakeResponsesClient(
        responses: <ResponsesResponse>[
          ResponsesResponse(
            text: '第一次回答',
            model: 'test-model',
            webSearchCitations: const <ResponsesWebSearchCitation>[
              ResponsesWebSearchCitation(
                url: 'https://example.test/first',
                title: '第一次来源',
              ),
            ],
            outputItems: const <ResponsesInputItem>[
              ResponsesRawInput(<String, dynamic>{
                'type': 'compaction',
                'id': 'cmp-1',
                'encrypted_content': 'opaque',
              }),
            ],
          ),
          ResponsesResponse(
            text: '第二次回答',
            model: 'test-model',
            webSearchCitations: const <ResponsesWebSearchCitation>[
              ResponsesWebSearchCitation(
                url: 'https://example.test/second',
                title: '第二次来源',
              ),
            ],
          ),
        ],
      );
      final ResponsesRulesWorkflow workflow = ResponsesRulesWorkflow(
        responsesClient: client,
      );

      await workflow.generateReply(
        prompt: '第一问',
        language: AppLanguage.zhHans,
        game: _game(),
        answerMode: AiAnswerMode.knowledgeThenDirect,
        useGlobalMode: false,
        config: _config(),
        assetSourceConfigs: const <AssetSourceConfig>[],
        remoteAssetService: _UnavailableRemoteAssetService(),
        conversationHistory: const <ChatMessage>[],
      );
      await workflow.generateReply(
        prompt: '第二问',
        language: AppLanguage.zhHans,
        game: _game(),
        answerMode: AiAnswerMode.knowledgeThenDirect,
        useGlobalMode: false,
        config: _config(),
        assetSourceConfigs: const <AssetSourceConfig>[],
        remoteAssetService: _UnavailableRemoteAssetService(),
        conversationHistory: const <ChatMessage>[],
      );

      final List<ResponsesRawInput> compactions = client.requests[1].input
          .whereType<ResponsesRawInput>()
          .toList();
      expect(compactions, hasLength(1));
      expect(compactions.single.value['id'], 'cmp-1');
    },
  );

  test(
    'restores an opaque compaction item in a new workflow instance',
    () async {
      final InMemoryResponsesCompactionStore store =
          InMemoryResponsesCompactionStore();
      final _FakeResponsesClient firstClient = _FakeResponsesClient(
        responses: <ResponsesResponse>[
          ResponsesResponse(
            text: '第一次回答',
            model: 'test-model',
            outputItems: const <ResponsesInputItem>[
              ResponsesRawInput(<String, dynamic>{
                'type': 'compaction',
                'id': 'cmp-persisted',
                'encrypted_content': 'opaque-persisted',
              }),
            ],
          ),
        ],
      );
      final ResponsesRulesWorkflow firstWorkflow = ResponsesRulesWorkflow(
        responsesClient: firstClient,
        compactionStore: store,
      );

      await firstWorkflow.generateReply(
        prompt: '第一问',
        language: AppLanguage.zhHans,
        game: _game(),
        answerMode: AiAnswerMode.knowledgeThenDirect,
        useGlobalMode: false,
        config: _config(),
        assetSourceConfigs: const <AssetSourceConfig>[],
        remoteAssetService: _UnavailableRemoteAssetService(),
        conversationHistory: const <ChatMessage>[],
      );

      final _FakeResponsesClient secondClient = _FakeResponsesClient(
        responses: <ResponsesResponse>[
          ResponsesResponse(
            text: '第二次回答',
            model: 'test-model',
            webSearchCitations: const <ResponsesWebSearchCitation>[
              ResponsesWebSearchCitation(
                url: 'https://example.test/persisted',
                title: '持久化来源',
              ),
            ],
          ),
        ],
      );
      final ResponsesRulesWorkflow secondWorkflow = ResponsesRulesWorkflow(
        responsesClient: secondClient,
        compactionStore: store,
      );

      await secondWorkflow.generateReply(
        prompt: '第二问',
        language: AppLanguage.zhHans,
        game: _game(),
        answerMode: AiAnswerMode.knowledgeThenDirect,
        useGlobalMode: false,
        config: _config(),
        assetSourceConfigs: const <AssetSourceConfig>[],
        remoteAssetService: _UnavailableRemoteAssetService(),
        conversationHistory: const <ChatMessage>[],
      );

      final List<ResponsesRawInput> compactions = secondClient
          .requests
          .single
          .input
          .whereType<ResponsesRawInput>()
          .toList();
      expect(compactions, hasLength(1));
      expect(compactions.single.value['id'], 'cmp-persisted');
      expect(compactions.single.value['encrypted_content'], 'opaque-persisted');
    },
  );
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
