part of '../responses_rules_workflow_test.dart';

void _registerKnowledgeWorkflowTests() {
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

  test('keeps official and community documents in separate stages', () async {
    final _FakeResponsesClient client = _FakeResponsesClient(
      responses: <ResponsesResponse>[
        _response(
          '{"status":"answered","answer":"官方规则回答","sourceIds":["official-rulebook"]}',
        ),
      ],
    );
    final ResponsesRulesWorkflow workflow = ResponsesRulesWorkflow(
      responsesClient: client,
    );

    final BoardGameAiAnswer answer = await workflow.generateReply(
      prompt: '规则问题',
      language: AppLanguage.zhHans,
      game: _gameWithSources(),
      answerMode: AiAnswerMode.knowledgeOnly,
      useGlobalMode: false,
      config: _config(),
      assetSourceConfigs: const <AssetSourceConfig>[],
      remoteAssetService: _FakeRemoteAssetService(),
      conversationHistory: const <ChatMessage>[],
    );

    expect(answer.source, AnswerSource.official);
    expect(client.requests, hasLength(1));
    final List<ResponsesFileInput> files = client.requests.single.input
        .whereType<ResponsesFileInput>()
        .toList();
    expect(files, hasLength(1));
    expect(files.single.filename, 'rulebook_en.md');
  });
}
