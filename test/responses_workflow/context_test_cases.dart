part of '../responses_rules_workflow_test.dart';

void _registerContextWorkflowTests() {
  test(
    'isolates new topic compaction and clears only the selected topic',
    () async {
      ResponsesResponse response(String id, {bool compact = false}) =>
          ResponsesResponse(
            text: '回答 $id',
            model: 'test-model',
            webSearchCitations: const [
              ResponsesWebSearchCitation(
                url: 'https://example.test/context',
                title: '来源',
              ),
            ],
            outputItems: compact
                ? [
                    ResponsesRawInput({
                      'type': 'compaction',
                      'id': id,
                      'encrypted_content': 'opaque-$id',
                    }),
                  ]
                : const [],
          );
      final client = _FakeResponsesClient(
        responses: [
          response('first', compact: true),
          response('second', compact: true),
          response('follow-first'),
          response('cleared-first'),
          response('follow-second'),
        ],
      );
      final workflow = ResponsesRulesWorkflow(responsesClient: client);
      Future<void> ask(String id) async {
        await workflow.generateReply(
          prompt: '第一问',
          language: AppLanguage.zhHans,
          game: _game(),
          answerMode: AiAnswerMode.knowledgeThenDirect,
          useGlobalMode: false,
          config: _config(),
          assetSourceConfigs: const [],
          remoteAssetService: _UnavailableRemoteAssetService(),
          conversationHistory: const [],
          conversationId: id,
        );
      }

      await ask('conversation:first');
      await ask('conversation:second');
      expect(client.requests[1].input.whereType<ResponsesRawInput>(), isEmpty);
      await ask('conversation:first');
      expect(
        client.requests[2].input
            .whereType<ResponsesRawInput>()
            .single
            .value['id'],
        'first',
      );
      await workflow.clearConversationContext(
        conversationId: 'conversation:first',
        game: _game(),
        useGlobalMode: false,
      );
      await ask('conversation:first');
      expect(client.requests[3].input.whereType<ResponsesRawInput>(), isEmpty);
      await ask('conversation:second');
      expect(
        client.requests[4].input
            .whereType<ResponsesRawInput>()
            .single
            .value['id'],
        'second',
      );
    },
  );

  test('clearing a topic rejects its late compaction snapshot', () async {
    final started = Completer<void>();
    final pending = Completer<ResponsesResponse>();
    final response = ResponsesResponse(
      text: '回答',
      model: 'test-model',
      webSearchCitations: const [
        ResponsesWebSearchCitation(
          url: 'https://example.test/context',
          title: '来源',
        ),
      ],
      outputItems: const [
        ResponsesRawInput({
          'type': 'compaction',
          'id': 'late',
          'encrypted_content': 'opaque-late',
        }),
      ],
    );
    final client = _FakeResponsesClient(
      responses: [],
      onComplete: (_, _) {
        if (!started.isCompleted) {
          started.complete();
          return pending.future;
        }
        return response;
      },
    );
    final workflow = ResponsesRulesWorkflow(responsesClient: client);
    Future<void> ask() async {
      await workflow.generateReply(
        prompt: '第一问',
        language: AppLanguage.zhHans,
        game: _game(),
        answerMode: AiAnswerMode.knowledgeThenDirect,
        useGlobalMode: false,
        config: _config(),
        assetSourceConfigs: const [],
        remoteAssetService: _UnavailableRemoteAssetService(),
        conversationHistory: const [],
        conversationId: 'conversation:late',
      );
    }

    final first = ask();
    await started.future;
    await workflow.clearConversationContext(
      conversationId: 'conversation:late',
      game: _game(),
      useGlobalMode: false,
    );
    pending.complete(response);
    await first;
    await ask();
    expect(client.requests.last.input.whereType<ResponsesRawInput>(), isEmpty);
  });

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

  test(
    'global knowledge-only does not load game files unless explicitly enabled',
    () async {
      final _FakeResponsesClient client = _FakeResponsesClient(
        responses: <ResponsesResponse>[_response('普通知识库未启用')],
      );
      final ResponsesRulesWorkflow workflow = ResponsesRulesWorkflow(
        responsesClient: client,
      );

      final BoardGameAiAnswer answer = await workflow.generateReply(
        prompt: '规则问题',
        language: AppLanguage.zhHans,
        game: _game(),
        answerMode: AiAnswerMode.knowledgeOnly,
        useGlobalMode: true,
        useCurrentGameKnowledge: false,
        config: _config(),
        assetSourceConfigs: const <AssetSourceConfig>[],
        remoteAssetService: _FakeRemoteAssetService(),
        conversationHistory: const <ChatMessage>[],
      );

      expect(answer.source, AnswerSource.insufficient);
      expect(client.requests, isEmpty);
    },
  );

  test(
    'a compaction item replaces the old local conversation window',
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
                'id': 'cmp-replaces-history',
                'encrypted_content': 'opaque',
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
                url: 'https://example.test/compaction',
                title: '压缩后的上下文',
              ),
            ],
          ),
        ],
      );
      final ResponsesRulesWorkflow secondWorkflow = ResponsesRulesWorkflow(
        responsesClient: secondClient,
        compactionStore: store,
      );
      final List<ChatMessage> history = List<ChatMessage>.generate(
        12,
        (int index) => ChatMessage(
          id: 'old-$index',
          role: index.isEven ? ChatRole.user : ChatRole.assistant,
          text: 'old-history-$index',
          timestamp: DateTime(2026, 1, 1).add(Duration(minutes: index)),
        ),
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
        conversationHistory: history,
      );

      final List<ResponsesTextInput> texts = secondClient.requests.single.input
          .whereType<ResponsesTextInput>()
          .toList();
      expect(texts.map((ResponsesTextInput item) => item.text), <String>[
        '第二问',
      ]);
      expect(
        secondClient.requests.single.input
            .whereType<ResponsesRawInput>()
            .single
            .value['id'],
        'cmp-replaces-history',
      );
    },
  );

  test(
    'drains output-item metadata that arrives after response.completed',
    () async {
      final InMemoryResponsesCompactionStore store =
          InMemoryResponsesCompactionStore();
      final _FakeResponsesClient client = _FakeResponsesClient(
        responses: const <ResponsesResponse>[],
        streams: <List<ResponsesStreamEvent>>[
          <ResponsesStreamEvent>[
            ResponsesStreamEvent.completed(
              ResponsesResponse(
                text:
                    '{"status":"answered","answer":"流式答案","sourceIds":["puerto_rico-knowledge-0"]}',
                model: 'test-model',
                id: 'resp-drain',
              ),
            ),
            const ResponsesStreamEvent(
              type: ResponsesStreamEventType.outputItemDone,
              outputItem: ResponsesRawInput(<String, dynamic>{
                'type': 'compaction',
                'id': 'cmp-after-completed',
                'encrypted_content': 'opaque-after-completed',
              }),
            ),
          ],
        ],
      );
      final ResponsesRulesWorkflow workflow = ResponsesRulesWorkflow(
        responsesClient: client,
        compactionStore: store,
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

      expect(events.last.answer?.text, '流式答案');

      final _FakeResponsesClient nextClient = _FakeResponsesClient(
        responses: <ResponsesResponse>[_response('下一轮')],
      );
      final ResponsesRulesWorkflow nextWorkflow = ResponsesRulesWorkflow(
        responsesClient: nextClient,
        compactionStore: store,
      );
      await nextWorkflow.generateReply(
        prompt: '下一问',
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
        nextClient.requests.single.input
            .whereType<ResponsesRawInput>()
            .single
            .value['id'],
        'cmp-after-completed',
      );
    },
  );

  test(
    'changing the current-game knowledge scope invalidates old compaction',
    () async {
      final InMemoryResponsesCompactionStore store =
          InMemoryResponsesCompactionStore();
      final _FakeResponsesClient firstClient = _FakeResponsesClient(
        responses: <ResponsesResponse>[
          ResponsesResponse(
            text: '通用兜底',
            model: 'test-model',
            outputItems: const <ResponsesInputItem>[
              ResponsesRawInput(<String, dynamic>{
                'type': 'compaction',
                'id': 'cmp-general-only',
                'encrypted_content': 'opaque-general-only',
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
        prompt: '你好',
        language: AppLanguage.zhHans,
        game: _game(),
        answerMode: AiAnswerMode.knowledgeThenDirect,
        useGlobalMode: true,
        useCurrentGameKnowledge: false,
        config: _config(),
        assetSourceConfigs: const <AssetSourceConfig>[],
        remoteAssetService: _UnavailableRemoteAssetService(),
        conversationHistory: const <ChatMessage>[],
      );

      final _FakeResponsesClient secondClient = _FakeResponsesClient(
        responses: <ResponsesResponse>[
          _response('{"status":"insufficient","answer":"","sourceIds":[]}'),
        ],
      );
      final ResponsesRulesWorkflow secondWorkflow = ResponsesRulesWorkflow(
        responsesClient: secondClient,
        compactionStore: store,
      );
      await secondWorkflow.generateReply(
        prompt: '规则问题',
        language: AppLanguage.zhHans,
        game: _game(),
        answerMode: AiAnswerMode.knowledgeOnly,
        useGlobalMode: true,
        useCurrentGameKnowledge: true,
        config: _config(),
        assetSourceConfigs: const <AssetSourceConfig>[],
        remoteAssetService: _FakeRemoteAssetService(),
        conversationHistory: const <ChatMessage>[],
      );

      expect(
        secondClient.requests.single.input.whereType<ResponsesRawInput>(),
        isEmpty,
      );
    },
  );
}
