part of '../responses_rules_workflow_test.dart';

void _registerStreamingWorkflowTests() {
  test('does not expose buffered stage text before response.completed', () async {
    final _FakeResponsesClient client = _FakeResponsesClient(
      responses: <ResponsesResponse>[
        _response(
          '{"status":"answered","answer":"最终规则答案","sourceIds":["puerto_rico-knowledge-0"]}',
        ),
      ],
      streams: <List<ResponsesStreamEvent>>[
        <ResponsesStreamEvent>[
          const ResponsesStreamEvent.text('{"status":"answered","answer":"中间"'),
          const ResponsesStreamEvent.text('间文本"}'),
          const ResponsesStreamEvent.textDone(
            '{"status":"answered","answer":"最终规则答案","sourceIds":["puerto_rico-knowledge-0"]}',
          ),
          ResponsesStreamEvent.completed(
            ResponsesResponse(
              text:
                  '{"status":"answered","answer":"最终规则答案","sourceIds":["puerto_rico-knowledge-0"]}',
              model: 'test-model',
              id: 'resp-stream',
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

    expect(
      events.map((BoardGameAiStreamEvent event) => event.delta).join(),
      '最终规则答案',
    );
    expect(
      events.where(
        (BoardGameAiStreamEvent event) => event.delta.contains('中间'),
      ),
      isEmpty,
    );
    expect(events.last.answer?.text, '最终规则答案');
    expect(events.last.isDone, isTrue);
  });

  test('retries once when a stream closes without any provider event', () async {
    final _FakeResponsesClient client = _FakeResponsesClient(
      responses: <ResponsesResponse>[
        _response(
          '{"status":"answered","answer":"重连后答案","sourceIds":["puerto_rico-knowledge-0"]}',
        ),
      ],
      streams: <List<ResponsesStreamEvent>>[
        <ResponsesStreamEvent>[],
        <ResponsesStreamEvent>[
          ResponsesStreamEvent.completed(
            _response(
              '{"status":"answered","answer":"重连后答案","sourceIds":["puerto_rico-knowledge-0"]}',
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
          prompt: '重连问题',
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

    expect(
      events.any(
        (BoardGameAiStreamEvent event) =>
            event.runEvent?.type == AiRunEventType.retry,
      ),
      isTrue,
    );
    expect(client.requests, hasLength(2));
    expect(events.last.answer?.text, '重连后答案');
  });

  test('reconnects after a retryable terminal stream error', () async {
    final _FakeResponsesClient client = _FakeResponsesClient(
      responses: <ResponsesResponse>[
        _response(
          '{"status":"answered","answer":"503 后恢复","sourceIds":["puerto_rico-knowledge-0"]}',
        ),
      ],
      streams: <List<ResponsesStreamEvent>>[
        <ResponsesStreamEvent>[
          const ResponsesStreamEvent.failed(
            'HTTP 503: Service Unavailable',
            errorCode: '503',
          ),
        ],
        <ResponsesStreamEvent>[
          ResponsesStreamEvent.completed(
            _response(
              '{"status":"answered","answer":"503 后恢复","sourceIds":["puerto_rico-knowledge-0"]}',
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
          prompt: '临时不可用后重连',
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

    expect(client.requests, hasLength(2));
    expect(
      events.any(
        (BoardGameAiStreamEvent event) =>
            event.runEvent?.type == AiRunEventType.retry,
      ),
      isTrue,
    );
    expect(events.last.answer?.text, '503 后恢复');
  });

  test('does not duplicate replayed deltas after reconnect', () async {
    const String payload =
        '{"status":"answered","answer":"重连后的完整答案","sourceIds":["puerto_rico-knowledge-0"]}';
    final _FakeResponsesClient client = _FakeResponsesClient(
      responses: const <ResponsesResponse>[],
      streams: <List<ResponsesStreamEvent>>[
        <ResponsesStreamEvent>[
          const ResponsesStreamEvent.text('{"status":"answered","answer":"重连后'),
          const ResponsesStreamEvent.failed(
            'HTTP 503: Service Unavailable',
            errorCode: '503',
          ),
        ],
        <ResponsesStreamEvent>[
          const ResponsesStreamEvent.text('{"status":"answered","answer":"重连后'),
          const ResponsesStreamEvent.text(
            '的完整答案","sourceIds":["puerto_rico-knowledge-0"]}',
          ),
          const ResponsesStreamEvent.textDone(payload),
          ResponsesStreamEvent.completed(
            ResponsesResponse(
              text: payload,
              model: 'test-model',
              id: 'resp-replayed',
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
          prompt: '重连去重',
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

    expect(events.last.answer?.text, '重连后的完整答案');
    expect(
      events
          .where(
            (BoardGameAiStreamEvent event) =>
                event.runEvent?.type == AiRunEventType.textDelta,
          )
          .map((BoardGameAiStreamEvent event) => event.runEvent!.delta)
          .join(),
      payload,
    );
  });

  test(
    'waits for output_text.done before committing response.completed',
    () async {
      final _FakeResponsesClient client = _FakeResponsesClient(
        responses: const <ResponsesResponse>[],
        streams: <List<ResponsesStreamEvent>>[
          <ResponsesStreamEvent>[
            const ResponsesStreamEvent.text(
              '{"status":"answered","answer":"未完成',
            ),
            ResponsesStreamEvent.completed(
              ResponsesResponse(
                text: '{"status":"answered","answer":"不应提交","sourceIds":[]}',
                model: 'test-model',
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
            prompt: '缺少 done',
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
      expect(events.last.runEvent?.errorCode, 'missing_output_text_done');
    },
  );

  test('does not retry when the stream fails after response.completed', () async {
    final String payload =
        '{"status":"answered","answer":"完成的回答","sourceIds":["puerto_rico-knowledge-0"]}';
    final _TerminalThenErrorResponsesClient client =
        _TerminalThenErrorResponsesClient(payload);
    final ResponsesRulesWorkflow workflow = ResponsesRulesWorkflow(
      responsesClient: client,
    );

    final List<BoardGameAiStreamEvent> events = await workflow
        .streamReply(
          prompt: '完成后关闭',
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

    expect(events.last.answer?.text, '完成的回答');
    expect(events.last.isFailure, isFalse);
    expect(client.streamRequests, 1);
    expect(
      events.where(
        (BoardGameAiStreamEvent event) =>
            event.runEvent?.type == AiRunEventType.retry,
      ),
      isEmpty,
    );
  });

  test(
    'commits an explicit insufficient answer when knowledge stages find nothing',
    () async {
      final _FakeResponsesClient client = _FakeResponsesClient(
        responses: <ResponsesResponse>[
          _response('{"status":"insufficient","answer":"","sourceIds":[]}'),
        ],
      );
      final ResponsesRulesWorkflow workflow = ResponsesRulesWorkflow(
        responsesClient: client,
      );

      final List<BoardGameAiStreamEvent> events = await workflow
          .streamReply(
            prompt: '没有资料的问题',
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

      expect(events.last.isDone, isTrue);
      expect(events.last.isFailure, isFalse);
      expect(events.last.status, 'insufficient');
      expect(events.last.answer?.source, AnswerSource.insufficient);
      expect(events.last.answer?.text, contains('资料不足'));
    },
  );

  test('persists a compaction output item emitted during streaming', () async {
    final InMemoryResponsesCompactionStore store =
        InMemoryResponsesCompactionStore();
    final _FakeResponsesClient firstClient = _FakeResponsesClient(
      responses: <ResponsesResponse>[
        ResponsesResponse(
          text:
              '{"status":"answered","answer":"流式答案","sourceIds":["puerto_rico-knowledge-0"]}',
          model: 'test-model',
          id: 'resp-stream-compaction',
        ),
      ],
      streams: <List<ResponsesStreamEvent>>[
        <ResponsesStreamEvent>[
          const ResponsesStreamEvent(
            type: ResponsesStreamEventType.outputItemDone,
            outputItem: ResponsesRawInput(<String, dynamic>{
              'type': 'compaction',
              'id': 'cmp-stream',
              'encrypted_content': 'opaque-stream',
            }),
          ),
          ResponsesStreamEvent.completed(
            ResponsesResponse(
              text:
                  '{"status":"answered","answer":"流式答案","sourceIds":["puerto_rico-knowledge-0"]}',
              model: 'test-model',
              id: 'resp-stream-compaction',
            ),
          ),
        ],
      ],
    );
    final ResponsesRulesWorkflow firstWorkflow = ResponsesRulesWorkflow(
      responsesClient: firstClient,
      compactionStore: store,
    );

    final List<BoardGameAiStreamEvent> firstEvents = await firstWorkflow
        .streamReply(
          prompt: '第一问',
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
    expect(firstEvents.last.answer?.text, '流式答案');

    final _FakeResponsesClient secondClient = _FakeResponsesClient(
      responses: <ResponsesResponse>[
        _response(
          '{"status":"answered","answer":"第二次答案","sourceIds":["puerto_rico-knowledge-0"]}',
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
      answerMode: AiAnswerMode.knowledgeOnly,
      useGlobalMode: false,
      config: _config(),
      assetSourceConfigs: const <AssetSourceConfig>[],
      remoteAssetService: _FakeRemoteAssetService(),
      conversationHistory: const <ChatMessage>[],
    );
    expect(
      secondClient.requests.single.input
          .whereType<ResponsesRawInput>()
          .single
          .value['id'],
      'cmp-stream',
    );
  });

  test(
    'reports a late stream failure without committing the buffered text',
    () async {
      final _FakeResponsesClient client = _FakeResponsesClient(
        responses: const <ResponsesResponse>[],
        streams: <List<ResponsesStreamEvent>>[
          <ResponsesStreamEvent>[
            const ResponsesStreamEvent.text(
              '{"status":"answered","answer":"部分答案',
            ),
            const ResponsesStreamEvent.failed(
              'upstream failed',
              errorCode: 'upstream_failed',
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

      expect(
        events.where((BoardGameAiStreamEvent event) => event.delta.isNotEmpty),
        isEmpty,
      );
      expect(events.last.isDone, isTrue);
      expect(events.last.isFailure, isTrue);
      expect(events.last.runEvent?.stageResult?.bufferedText, contains('部分答案'));
      expect(events.last.runEvent?.stageResult?.errorCode, 'upstream_failed');
      expect(events.last.runResult?.status, AiRunStatus.failed);
      expect(events.last.runResult?.stages, isNotEmpty);
    },
  );

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
}
