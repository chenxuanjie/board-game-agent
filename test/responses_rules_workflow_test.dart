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

class _FailingTelemetrySink implements AiRunTelemetrySink {
  @override
  Future<void> record(AiRunResult result) async {
    throw StateError('telemetry unavailable');
  }
}
