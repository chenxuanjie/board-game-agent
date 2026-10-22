part of '../responses_rules_workflow_test.dart';

void _registerTelemetryWorkflowTests() {
  test('telemetry records run status, model, session, and usage', () async {
    final InMemoryAiRunTelemetrySink telemetry = InMemoryAiRunTelemetrySink();
    final _FakeResponsesClient client = _FakeResponsesClient(
      responses: <ResponsesResponse>[
        ResponsesResponse(
          text: '普通回答',
          model: 'telemetry-model',
          id: 'resp-telemetry',
          usage: const AiUsage(
            promptTokens: 10,
            completionTokens: 6,
            totalTokens: 16,
            reasoningTokens: 2,
          ),
        ),
      ],
    );
    final ResponsesRulesWorkflow workflow = ResponsesRulesWorkflow(
      responsesClient: client,
      telemetrySink: telemetry,
    );
    await workflow.generateReply(
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

    expect(telemetry.recent, hasLength(1));
    final result = telemetry.recent.single;
    expect(result.status, AiRunStatus.completed);
    expect(result.model, 'telemetry-model');
    expect(result.sessionId, result.contextKey);
    expect(result.requestCount, 1);
    expect(result.inputTokens, 10);
    expect(result.outputTokens, 6);
    expect(result.reasoningTokens, 2);
  });

  test(
    'custom Responses without web search still reaches the knowledge fallback',
    () async {
      final _FakeResponsesClient client = _FakeResponsesClient(
        responses: <ResponsesResponse>[
          _response('{"status":"insufficient","answer":"","sourceIds":[]}'),
          _response('没有联网工具也可以继续回答'),
        ],
        onComplete:
            (ResponsesRequest request, List<ResponsesResponse> responses) {
              if (request.tools.isNotEmpty) {
                throw StateError(
                  'web_search is not supported by this provider',
                );
              }
              return responses.removeAt(0);
            },
      );
      final ResponsesRulesWorkflow workflow = ResponsesRulesWorkflow(
        responsesClient: client,
      );

      final BoardGameAiAnswer answer = await workflow.generateReply(
        prompt: '规则问题',
        language: AppLanguage.zhHans,
        game: _game(),
        answerMode: AiAnswerMode.knowledgeThenDirect,
        useGlobalMode: false,
        config: _config(),
        assetSourceConfigs: const <AssetSourceConfig>[],
        remoteAssetService: _FakeRemoteAssetService(),
        conversationHistory: const <ChatMessage>[],
      );

      expect(answer.text, '没有联网工具也可以继续回答');
      expect(answer.source, AnswerSource.modelKnowledge);
      expect(client.requests, hasLength(3));
      expect(client.requests[1].tools, isNotEmpty);
      expect(client.requests[2].tools, isEmpty);
    },
  );

  test(
    'rejects a structured answer that mixes declared and invented source IDs',
    () async {
      final _FakeResponsesClient client = _FakeResponsesClient(
        responses: <ResponsesResponse>[
          _response(
            '{"status":"answered","answer":"不应提交","sourceIds":["official-rulebook","forged-source"]}',
          ),
          _response('{"status":"insufficient","answer":"","sourceIds":[]}'),
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

      expect(answer.source, AnswerSource.insufficient);
      expect(answer.text, contains('资料不足'));
      expect(answer.citations, isEmpty);
    },
  );

  test(
    'locks the first terminal stream event even if a provider emits a tail event',
    () async {
      final _FakeResponsesClient client = _FakeResponsesClient(
        responses: const <ResponsesResponse>[],
        streams: <List<ResponsesStreamEvent>>[
          <ResponsesStreamEvent>[
            const ResponsesStreamEvent.text('部分结果'),
            const ResponsesStreamEvent.failed(
              '上游失败',
              rawType: 'response.failed',
              errorCode: 'server_error',
            ),
            ResponsesStreamEvent.completed(
              ResponsesResponse(
                text: '不应覆盖失败',
                model: 'test-model',
                id: 'resp-tail',
              ),
            ),
          ],
        ],
      );
      final ResponsesRulesWorkflow workflow = ResponsesRulesWorkflow(
        responsesClient: client,
      );

      final List<BoardGameAiStreamEvent> events = await workflow
          .streamReply(
            prompt: '规则问题',
            language: AppLanguage.zhHans,
            game: _game(),
            answerMode: AiAnswerMode.knowledgeOnly,
            useGlobalMode: false,
            config: _config(),
            assetSourceConfigs: const <AssetSourceConfig>[],
            remoteAssetService: _FakeRemoteAssetService(),
            conversationHistory: const <ChatMessage>[],
          )
          .toList();

      expect(events.last.isFailure, isTrue);
      expect(events.last.runEvent?.rawType, 'response.failed');
      expect(events.last.runEvent?.stageResult?.bufferedText, '部分结果');
      expect(
        events.last.runEvent?.stageResult?.terminalEventType,
        'response.failed',
      );
    },
  );

  test(
    'keeps custom authentication headers and isolates model sessions',
    () async {
      final InMemoryAiRunTelemetrySink telemetry = InMemoryAiRunTelemetrySink();
      final _FakeResponsesClient firstClient = _FakeResponsesClient(
        responses: <ResponsesResponse>[_response('第一次回答')],
      );
      final ResponsesRulesWorkflow firstWorkflow = ResponsesRulesWorkflow(
        responsesClient: firstClient,
        telemetrySink: telemetry,
      );
      final AiApiConfig custom = _config().copyWith(
        name: 'Custom Supplier',
        model: 'model-a',
        apiKeyHeader: 'X-API-Key',
      );
      await firstWorkflow.generateReply(
        prompt: '你好',
        language: AppLanguage.zhHans,
        game: _game(),
        answerMode: AiAnswerMode.knowledgeThenDirect,
        useGlobalMode: true,
        config: custom,
        assetSourceConfigs: const <AssetSourceConfig>[],
        remoteAssetService: _UnavailableRemoteAssetService(),
        conversationHistory: const <ChatMessage>[],
      );

      final _FakeResponsesClient secondClient = _FakeResponsesClient(
        responses: <ResponsesResponse>[_response('第二次回答')],
      );
      final ResponsesRulesWorkflow secondWorkflow = ResponsesRulesWorkflow(
        responsesClient: secondClient,
        telemetrySink: telemetry,
      );
      await secondWorkflow.generateReply(
        prompt: '你好',
        language: AppLanguage.zhHans,
        game: _game(),
        answerMode: AiAnswerMode.knowledgeThenDirect,
        useGlobalMode: true,
        config: custom.copyWith(model: 'model-b'),
        assetSourceConfigs: const <AssetSourceConfig>[],
        remoteAssetService: _UnavailableRemoteAssetService(),
        conversationHistory: const <ChatMessage>[],
      );

      expect(firstClient.requests.single.endpoint.apiKeyHeader, 'X-API-Key');
      expect(telemetry.recent, hasLength(2));
      expect(
        telemetry.recent.first.contextKey,
        isNot(telemetry.recent.last.contextKey),
      );
    },
  );

  test(
    'a telemetry sink failure does not fail an otherwise valid answer',
    () async {
      final _FakeResponsesClient client = _FakeResponsesClient(
        responses: <ResponsesResponse>[_response('回答仍然成功')],
      );
      final ResponsesRulesWorkflow workflow = ResponsesRulesWorkflow(
        responsesClient: client,
        telemetrySink: _FailingTelemetrySink(),
      );

      final BoardGameAiAnswer answer = await workflow.generateReply(
        prompt: '你好',
        language: AppLanguage.zhHans,
        game: _game(),
        answerMode: AiAnswerMode.knowledgeThenDirect,
        useGlobalMode: true,
        config: _config(),
        assetSourceConfigs: const <AssetSourceConfig>[],
        remoteAssetService: _UnavailableRemoteAssetService(),
        conversationHistory: const <ChatMessage>[],
      );

      expect(answer.text, '回答仍然成功');
    },
  );
}
