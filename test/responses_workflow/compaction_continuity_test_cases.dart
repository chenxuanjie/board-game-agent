part of '../responses_rules_workflow_test.dart';

ChatMessage _turnMessage(int turn, ChatRole role, String text) => ChatMessage(
  id: '${role.name}-$turn',
  role: role,
  text: text,
  timestamp: DateTime(2026, 1, 1, 0, turn),
);

ResponsesRawInput _compaction(String id) => ResponsesRawInput({
  'type': 'compaction',
  'id': id,
  'encrypted_content': 'opaque-$id',
});

ResponsesRawInput _assistantOutput(int turn, String text) => ResponsesRawInput({
  'type': 'message',
  'id': 'msg-$turn',
  'role': 'assistant',
  'status': 'completed',
  'content': [
    {'type': 'output_text', 'text': text, 'annotations': []},
  ],
});

Future<BoardGameAiAnswer> _contextRound(
  ResponsesRulesWorkflow workflow,
  String prompt,
  List<ChatMessage> history, {
  bool streaming = false,
  Future<void>? abortTrigger,
}) async {
  if (streaming) {
    final events = await workflow
        .streamReply(
          prompt: prompt,
          language: AppLanguage.zhHans,
          game: _game(),
          answerMode: AiAnswerMode.knowledgeThenDirect,
          useGlobalMode: true,
          config: _config(),
          assetSourceConfigs: const [],
          remoteAssetService: _UnavailableRemoteAssetService(),
          conversationHistory: history,
          conversationId: 'conversation:continuity',
          abortTrigger: abortTrigger,
        )
        .toList();
    expect(
      events.last.errorMessage,
      isNull,
      reason: 'Terminal status: ${events.last.status}',
    );
    return events.last.answer ??
        BoardGameAiAnswer(text: '', source: AnswerSource.insufficient);
  }
  return workflow.generateReply(
    prompt: prompt,
    language: AppLanguage.zhHans,
    game: _game(),
    answerMode: AiAnswerMode.knowledgeThenDirect,
    useGlobalMode: true,
    config: _config(),
    assetSourceConfigs: const [],
    remoteAssetService: _UnavailableRemoteAssetService(),
    conversationHistory: history,
    conversationId: 'conversation:continuity',
  );
}

void _registerCompactionContinuityTests() {
  test(
    'an unindexed extra item beside a partial snapshot never guesses a cache boundary',
    () async {
      final store = InMemoryResponsesCompactionStore();
      final client = _FakeResponsesClient(
        responses: [],
        streams: [
          [
            ResponsesStreamEvent.completed(
              ResponsesResponse(
                text: '回答',
                model: 'test-model',
                outputItems: [_assistantOutput(1, '回答')],
              ),
            ),
            ResponsesStreamEvent(
              type: ResponsesStreamEventType.outputItemDone,
              outputItem: _compaction('unknown-position'),
            ),
          ],
        ],
      );
      final workflow = ResponsesRulesWorkflow(
        responsesClient: client,
        compactionStore: store,
      );
      expect(
        (await _contextRound(workflow, '你好', [], streaming: true)).text,
        '回答',
      );
      expect(await store.load(), isEmpty);
    },
  );

  for (final streaming in [false, true]) {
    test(
      'real SDK JSON/SSE preserves the third request after compaction (stream=$streaming)',
      () async {
        final bodies = <Map<String, dynamic>>[];
        Future<http.Response> handle(http.Request request) async {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          final turn = bodies.length;
          final output = [
            if (turn == 1) _compaction('sdk').toJson(),
            _assistantOutput(turn, 'SDK 回答-$turn').toJson(),
          ];
          final response = {
            'id': 'resp-$turn',
            'object': 'response',
            'created_at': 1,
            'model': 'test-model',
            'status': 'completed',
            'output': output,
          };
          if (!streaming) {
            return http.Response(
              jsonEncode(response),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            [
              'data: ${jsonEncode({'type': 'response.output_text.delta', 'delta': 'SDK 回答-$turn', 'output_index': output.length - 1, 'content_index': 0})}',
              'data: ${jsonEncode({'type': 'response.output_text.done', 'text': 'SDK 回答-$turn', 'output_index': output.length - 1, 'content_index': 0})}',
              'data: ${jsonEncode({'type': 'response.completed', 'response': response})}',
              'data: [DONE]',
              '',
            ].join('\n\n'),
            200,
            headers: {'content-type': 'text/event-stream; charset=utf-8'},
          );
        }

        final client = OpenAiDartResponsesAiClient(
          httpClient: MockClient(handle),
          streamClientFactory: () => MockClient(handle),
        );
        addTearDown(client.close);
        final workflow = ResponsesRulesWorkflow(responsesClient: client);
        final history = <ChatMessage>[];
        for (var turn = 1; turn <= 3; turn++) {
          final prompt = '你好，第 $turn 个条件';
          history.add(_turnMessage(turn, ChatRole.user, prompt));
          final answer = await _contextRound(
            workflow,
            prompt,
            List.of(history),
            streaming: streaming,
          );
          expect(answer.text, 'SDK 回答-$turn');
          history.add(_turnMessage(turn, ChatRole.assistant, answer.text));
        }
        final input = bodies.last['input'] as List;
        expect(input.where((item) => item['type'] == 'compaction').length, 1);
        expect(input.where((item) => item['id'] == 'msg-1').length, 1);
        expect(input.where((item) => item['id'] == 'msg-2').length, 1);
        expect(jsonEncode(input), contains('你好，第 2 个条件'));
        expect(bodies.every((body) => body['store'] == false), isTrue);
        expect(
          bodies.every((body) => !body.containsKey('previous_response_id')),
          isTrue,
        );
      },
    );
  }

  test(
    'cancellation after compaction metadata cannot publish a new window',
    () async {
      final abort = Completer<void>();
      final store = InMemoryResponsesCompactionStore();
      final client = _CancellingContextClient(abort);
      final workflow = ResponsesRulesWorkflow(
        responsesClient: client,
        compactionStore: store,
      );
      await _contextRound(
        workflow,
        '你好',
        [_turnMessage(1, ChatRole.user, '你好')],
        streaming: true,
        abortTrigger: abort.future,
      );
      expect(await store.load(), isEmpty);
      await _contextRound(workflow, '你好，重新开始', []);
      expect(
        client.requests.last.input.whereType<ResponsesRawInput>(),
        isEmpty,
      );
    },
  );

  test(
    'a failed secure write does not fail the answer or lose the in-memory continuation',
    () async {
      final client = _FakeResponsesClient(
        responses: [
          ResponsesResponse(
            text: '回答',
            model: 'test-model',
            outputItems: [_compaction('memory')],
          ),
          _response('下轮回答'),
        ],
      );
      final workflow = ResponsesRulesWorkflow(
        responsesClient: client,
        compactionStore: _FailingContextStore(),
      );
      final user = _turnMessage(1, ChatRole.user, '你好');
      expect((await _contextRound(workflow, '你好', [user])).text, '回答');
      await _contextRound(workflow, '你好，继续', [
        user,
        _turnMessage(1, ChatRole.assistant, '回答'),
      ]);
      expect(client.requests.last.input.first.toJson()['id'], 'memory');
    },
  );

  for (final streaming in [false, true]) {
    test(
      'retains five turns with intermittent compaction and restart (stream=$streaming)',
      () async {
        final store = InMemoryResponsesCompactionStore();
        final client = _FakeResponsesClient(
          responses: [
            for (var turn = 1; turn <= 5; turn++)
              ResponsesResponse(
                text: '回答-$turn',
                model: 'test-model',
                outputItems: [
                  // Output before the latest marker is already represented by it.
                  if (turn == 4) _assistantOutput(40, '已包含在压缩结果中'),
                  if (turn == 1 || turn == 4) _compaction('cmp-$turn'),
                  _assistantOutput(turn, '回答-$turn'),
                ],
              ),
          ],
        );
        var workflow = ResponsesRulesWorkflow(
          responsesClient: client,
          compactionStore: store,
        );
        final history = <ChatMessage>[];
        for (var turn = 1; turn <= 5; turn++) {
          if (turn == 3) {
            workflow = ResponsesRulesWorkflow(
              responsesClient: client,
              compactionStore: store,
            );
          }
          final prompt = '你好，补充条件-$turn';
          history.add(_turnMessage(turn, ChatRole.user, prompt));
          final answer = await _contextRound(
            workflow,
            prompt,
            List.of(history),
            streaming: streaming,
          );
          expect(answer.text, '回答-$turn');
          final input = client.requests.last.input
              .map((item) => item.toJson())
              .toList();
          expect(
            input
                .where((item) => item['type'] == 'compaction')
                .map((item) => item['id']),
            turn == 1 ? isEmpty : [turn <= 4 ? 'cmp-1' : 'cmp-4'],
          );
          final encoded = jsonEncode(input);
          for (var prior = turn == 5 ? 4 : 1; prior < turn; prior++) {
            expect(
              input.where((item) => item['id'] == 'msg-$prior'),
              hasLength(1),
            );
            if (prior > 1 && turn < 5) {
              expect(encoded, contains('你好，补充条件-$prior'));
            }
            // The UI answer is not appended a second time next to provider output.
            expect(RegExp('回答-$prior').allMatches(encoded), hasLength(1));
          }
          if (turn == 5) {
            expect(encoded, isNot(contains('msg-1')));
            expect(encoded, isNot(contains('已包含在压缩结果中')));
          }
          history.add(_turnMessage(turn, ChatRole.assistant, answer.text));
        }
        final saved = (await store.load()).values.single.toJson();
        expect(jsonEncode(saved), contains('msg-5'));
      },
    );
  }

  test(
    'late indexed output completes a partial snapshot without reordering or placeholders',
    () async {
      final store = InMemoryResponsesCompactionStore();
      final client = _FakeResponsesClient(
        responses: [_response('下一轮')],
        streams: [
          [
            ResponsesStreamEvent(
              type: ResponsesStreamEventType.outputItemAdded,
              outputIndex: 1,
              outputItem: const ResponsesRawInput({
                'type': 'message',
                'id': 'msg-1',
                'role': 'assistant',
                'content': [],
              }),
            ),
            ResponsesStreamEvent.completed(
              ResponsesResponse(
                text: '第一轮回答',
                model: 'test-model',
                outputItems: [_compaction('late')],
              ),
            ),
            ResponsesStreamEvent(
              type: ResponsesStreamEventType.outputItemDone,
              outputIndex: 2,
              outputItem: const ResponsesRawInput({
                'type': 'reasoning',
                'id': 'reasoning-1',
                'encrypted_content': 'reasoning',
                'summary': [],
              }),
            ),
            ResponsesStreamEvent(
              type: ResponsesStreamEventType.outputItemDone,
              outputIndex: 1,
              outputItem: _assistantOutput(1, '第一轮回答'),
            ),
          ],
        ],
      );
      final workflow = ResponsesRulesWorkflow(
        responsesClient: client,
        compactionStore: store,
      );
      final user = _turnMessage(1, ChatRole.user, '你好');
      await _contextRound(workflow, '你好', [user], streaming: true);
      await _contextRound(workflow, '你好，再补充', [
        user,
        _turnMessage(1, ChatRole.assistant, '第一轮回答'),
      ]);
      final raw = client.requests.last.input
          .map((item) => item.toJson())
          .toList();
      expect(raw.take(3).map((item) => item['id']), [
        'late',
        'msg-1',
        'reasoning-1',
      ]);
      expect((raw[1]['content'] as List), isNotEmpty);
    },
  );

  test(
    'failed response cannot commit its compaction and successful retry keeps intervening chat',
    () async {
      final store = InMemoryResponsesCompactionStore();
      final client = _FakeResponsesClient(
        responses: [
          ResponsesResponse(
            text: '回答-1',
            model: 'test-model',
            outputItems: [_compaction('good'), _assistantOutput(1, '回答-1')],
          ),
          ResponsesResponse(
            text: '未完成',
            status: 'failed',
            model: 'test-model',
            outputItems: [_compaction('bad')],
          ),
          _response('恢复后的回答'),
        ],
      );
      final workflow = ResponsesRulesWorkflow(
        responsesClient: client,
        compactionStore: store,
      );
      final history = [_turnMessage(1, ChatRole.user, '你好')];
      await _contextRound(workflow, '你好', history);
      history.add(_turnMessage(1, ChatRole.assistant, '回答-1'));
      history.add(_turnMessage(2, ChatRole.user, '你好，条件是红色'));
      await _contextRound(workflow, history.last.text, history);
      expect(
        jsonEncode((await store.load()).values.single.toJson()),
        isNot(contains('bad')),
      );
      history.add(_turnMessage(2, ChatRole.assistant, '未完成提示'));
      await _contextRound(workflow, '你好，继续', history);
      final input = jsonEncode(
        client.requests.last.input.map((item) => item.toJson()).toList(),
      );
      expect(input, contains('条件是红色'));
      expect(input, isNot(contains('opaque-bad')));
    },
  );

  test(
    'unaccepted retrieval compaction is not reused for the accepted fallback',
    () async {
      final store = InMemoryResponsesCompactionStore();
      final client = _FakeResponsesClient(
        responses: [
          ResponsesResponse(
            text: '{"status":"insufficient","answer":"","sourceIds":[]}',
            model: 'test-model',
            outputItems: [_compaction('discarded-official')],
          ),
          _response('网页未找到依据'),
          _response('仅供参考的回答'),
        ],
      );
      final workflow = ResponsesRulesWorkflow(
        responsesClient: client,
        compactionStore: store,
      );
      await workflow.generateReply(
        prompt: '规则问题',
        language: AppLanguage.zhHans,
        game: _game(),
        answerMode: AiAnswerMode.knowledgeThenDirect,
        useGlobalMode: false,
        config: _config(),
        assetSourceConfigs: const [],
        remoteAssetService: _FakeRemoteAssetService(),
        conversationHistory: const [],
      );
      expect(client.requests, hasLength(3));
      expect(await store.load(), isEmpty);
      for (final request in client.requests.skip(1)) {
        expect(
          jsonEncode(request.input.map((item) => item.toJson()).toList()),
          isNot(contains('discarded-official')),
        );
      }
    },
  );
}

class _CancellingContextClient extends _FakeResponsesClient {
  _CancellingContextClient(this.abort) : super(responses: [_response('重试成功')]);
  final Completer<void> abort;
  @override
  Stream<ResponsesStreamEvent> stream(
    ResponsesRequest request, {
    Future<void>? abortTrigger,
  }) async* {
    requests.add(request);
    yield ResponsesStreamEvent(
      type: ResponsesStreamEventType.outputItemDone,
      outputIndex: 0,
      outputItem: _compaction('cancelled'),
    );
    abort.complete();
    await Future<void>.value();
    yield ResponsesStreamEvent.completed(
      ResponsesResponse(text: '未采纳回答', model: 'test-model'),
    );
  }
}

class _FailingContextStore extends InMemoryResponsesCompactionStore {
  @override
  Future<void> save(Map<String, ResponsesContextWindow> itemsByContext) async {
    throw StateError('secure storage unavailable');
  }
}
