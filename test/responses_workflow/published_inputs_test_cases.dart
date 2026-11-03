part of '../responses_rules_workflow_test.dart';

Future<({CatalogHttpFixture fixture, RemoteAssetService assets, GameInfo game})>
_publishedInput({
  String text = '已发布的派生正文',
  AppLanguage language = AppLanguage.zhHans,
  bool community = true,
}) async {
  final directory = await Directory.systemTemp.createTemp(
    'board-published-input-',
  );
  final fixture = CatalogHttpFixture()..put('cabo', text: text);
  final resource =
      (fixture.editions['cabo']!['resources'] as List).firstWhere(
            (r) => r['id'] == 'cabo-rules',
          )
          as Map;
  resource['source_url'] =
      'https://provenance.invalid/discussion/login-required';
  resource['source_class'] = community
      ? 'community_extracted'
      : 'official_extracted';
  resource['language'] = language == AppLanguage.zhHans ? 'cn' : 'en';
  resource['edition_code'] = 'edition-2026';
  resource['priority'] = 0;
  final assets = RemoteAssetService(
    client: fixture.client,
    cacheDirectory: directory,
    serviceOrigin: () => Uri.parse('https://api.test'),
  );
  addTearDown(() async {
    assets.dispose();
    await directory.delete(recursive: true);
  });
  final snapshot = await assets.loadCatalog();
  return (
    fixture: fixture,
    assets: assets,
    game: snapshot.games.single.toGameInfo(language),
  );
}

Future<BoardGameAiAnswer?> _publishedReply(
  ResponsesRulesWorkflow workflow,
  GameInfo game,
  RemoteAssetService assets, {
  bool streaming = false,
  AppLanguage language = AppLanguage.zhHans,
  AiApiConfig? config,
  List<ChatMessage> history = const [],
  String prompt = '规则问题',
}) async {
  final settings = config ?? _config().copyWith(accountService: true);
  if (streaming) {
    final events = await workflow
        .streamReply(
          prompt: prompt,
          language: language,
          game: game,
          answerMode: AiAnswerMode.knowledgeOnly,
          useGlobalMode: false,
          config: settings,
          assetSourceConfigs: const [],
          remoteAssetService: assets,
          conversationHistory: history,
          conversationId: 'conversation:published-input',
        )
        .toList();
    return events.last.answer;
  }
  return workflow.generateReply(
    prompt: prompt,
    language: language,
    game: game,
    answerMode: AiAnswerMode.knowledgeOnly,
    useGlobalMode: false,
    config: settings,
    assetSourceConfigs: const [],
    remoteAssetService: assets,
    conversationHistory: history,
    conversationId: 'conversation:published-input',
  );
}

String _structuredPublishedAnswer(String id) => jsonEncode({
  'status': 'answered',
  'answer': '依据随附正文回答',
  'sourceIds': [id],
});

void _registerPublishedInputTests() {
  test(
    'SDK response streaming still receives cancellation after input preparation',
    () async {
      final abort = Completer<void>();
      final client = _CancellableResponseClient();
      final workflow = ResponsesRulesWorkflow(responsesClient: client);
      final subscription = workflow
          .streamReply(
            prompt: '规则问题',
            language: AppLanguage.zhHans,
            game: _game(),
            answerMode: AiAnswerMode.knowledgeOnly,
            useGlobalMode: false,
            config: _config(),
            assetSourceConfigs: [],
            remoteAssetService: _FakeRemoteAssetService(),
            conversationHistory: [],
            abortTrigger: abort.future,
          )
          .listen((_) {});
      await client.started.future;
      abort.complete();
      await subscription.cancel().timeout(const Duration(seconds: 1));
      await client.cancelled.future.timeout(const Duration(seconds: 1));
      expect(client.requests, hasLength(1));
      workflow.close();
    },
  );
  test(
    'provider cleanup does not wait for a resource adapter that ignores abort',
    () async {
      final abort = Completer<void>();
      final assets = _HeldKnowledgeFile();
      final client = _FakeResponsesClient(responses: []);
      final workflow = ResponsesRulesWorkflow(responsesClient: client);
      final subscription = workflow
          .streamReply(
            prompt: '规则问题',
            language: AppLanguage.zhHans,
            game: _game(),
            answerMode: AiAnswerMode.knowledgeOnly,
            useGlobalMode: false,
            config: _config(),
            assetSourceConfigs: [],
            remoteAssetService: assets,
            conversationHistory: [],
            abortTrigger: abort.future,
          )
          .listen((_) {});
      await assets.started.future;
      abort.complete();
      await subscription.cancel().timeout(const Duration(seconds: 1));
      expect(client.requests, isEmpty);
      assets.release.complete(utf8.encode('late file'));
      await Future<void>.delayed(Duration.zero);
      expect(client.requests, isEmpty);
      workflow.close();
    },
  );
  test(
    'cancelling a later file never dispatches the already-loaded subset',
    () async {
      final abort = Completer<void>();
      final assets = _CancelSecondKnowledgeFile(abort);
      final client = _FakeResponsesClient(responses: []);
      final events = await ResponsesRulesWorkflow(responsesClient: client)
          .streamReply(
            prompt: '规则问题',
            language: AppLanguage.zhHans,
            game: _game(),
            answerMode: AiAnswerMode.knowledgeOnly,
            useGlobalMode: false,
            config: _config(),
            assetSourceConfigs: [],
            remoteAssetService: assets,
            conversationHistory: [],
            abortTrigger: abort.future,
          )
          .toList();
      expect(assets.calls, 2);
      expect(client.requests, isEmpty);
      expect(events.last.status, 'cancelled');
    },
  );
  test(
    'changing selected language files invalidates the previous file context',
    () async {
      final input = await _publishedInput(community: false);
      final resources = input.fixture.editions['cabo']!['resources'] as List;
      final original =
          resources.firstWhere((r) => r['id'] == 'cabo-rules') as Map;
      final english = utf8.encode('Published English rules');
      final hash = sha256.convert(english).toString();
      input.fixture.contents['cabo-rules-en'] = english;
      resources.add(<String, dynamic>{
        ...original,
        'id': 'cabo-rules-en',
        'language': 'en',
        'path': 'docs/rules_en.md',
        'file_sha256': hash,
        'content_url':
            '/v1/apps/board_game_agent/catalog/resources/cabo-rules-en/content?version=$hash',
      });
      input.fixture.revision++;
      input.fixture.changes.add({
        'revision': input.fixture.revision,
        'edition_id': 'cabo',
        'kind': 'upsert',
      });
      await input.assets.refreshCatalog();
      final catalog = input.assets.catalog!;
      final client = _FakeResponsesClient(
        responses: [
          ResponsesResponse(
            text: _structuredPublishedAnswer('cabo-rules'),
            model: 'test-model',
            outputItems: [_compaction('chinese-context')],
          ),
          _response(_structuredPublishedAnswer('cabo-rules-en')),
        ],
      );
      final workflow = ResponsesRulesWorkflow(responsesClient: client);
      await _publishedReply(
        workflow,
        catalog.games.single.toGameInfo(AppLanguage.zhHans),
        input.assets,
      );
      final answer = await _publishedReply(
        workflow,
        catalog.games.single.toGameInfo(AppLanguage.en),
        input.assets,
        language: AppLanguage.en,
      );
      expect(
        client.requests.last.input.whereType<ResponsesRawInput>(),
        isEmpty,
      );
      expect(
        base64Decode(
          client.requests.last.input
              .whereType<ResponsesFileInput>()
              .single
              .fileData!,
        ),
        english,
      );
      expect(answer!.citations.single.fileSha256, hash);
      expect(answer.citations.single.language, 'en');
    },
  );
  for (final streaming in [false, true]) {
    test(
      'official and community preparation share one decreasing time budget (stream=$streaming)',
      () async {
        final assets = _TimedKnowledgeAssets();
        final client = _FakeResponsesClient(
          responses: [
            _response('{"status":"insufficient","answer":"","sourceIds":[]}'),
            _response(_structuredPublishedAnswer('community-ruling')),
          ],
        );
        final result = await _publishedReply(
          ResponsesRulesWorkflow(responsesClient: client),
          _gameWithSources(),
          assets,
          streaming: streaming,
        );
        expect(result!.source, AnswerSource.community);
        expect(assets.timeouts, hasLength(2));
        expect(
          assets.timeouts.first,
          lessThanOrEqualTo(const Duration(seconds: 20)),
        );
        expect(
          assets.timeouts.last,
          lessThan(assets.timeouts.first - const Duration(milliseconds: 20)),
        );
      },
    );
  }
  for (final streaming in [false, true]) {
    for (final community in [false, true]) {
      for (final language in [AppLanguage.zhHans, AppLanguage.en]) {
        test(
          'published bytes replace provenance URL; citation binds bytes (stream=$streaming community=$community lang=$language)',
          () async {
            final input = await _publishedInput(
              language: language,
              community: community,
            );
            final client = _FakeResponsesClient(
              responses: [_response(_structuredPublishedAnswer('cabo-rules'))],
            );
            final answer = await _publishedReply(
              ResponsesRulesWorkflow(responsesClient: client),
              input.game,
              input.assets,
              streaming: streaming,
              language: language,
            );
            expect(
              answer!.source,
              community ? AnswerSource.community : AnswerSource.official,
            );
            final file = client.requests.single.input
                .whereType<ResponsesFileInput>()
                .single;
            expect(file.fileUrl, isNull);
            expect(
              base64Decode(file.fileData!),
              input.fixture.contents['cabo-rules'],
            );
            expect(
              input.fixture.requests.every((r) => r.url.host == 'api.test'),
              isTrue,
            );
            final download = input.fixture.requests.singleWhere(
              (r) => r.url.path.endsWith('/cabo-rules/content'),
            );
            final digest = sha256
                .convert(base64Decode(file.fileData!))
                .toString();
            expect(download.url.queryParameters['version'], digest);
            final RuleCitation citation = answer.citations.single;
            expect(citation.sourceId, 'cabo-rules');
            expect(citation.fileSha256, digest);
            expect(citation.edition, 'edition-2026');
            expect(citation.publicationRevision, input.fixture.revision);
            expect(citation.url, startsWith('https://provenance.invalid/'));
            expect(
              citation.language,
              language == AppLanguage.zhHans ? 'cn' : 'en',
            );
            final restored = ChatMessage.fromMap(
              ChatMessage(
                id: 'reply',
                role: ChatRole.assistant,
                text: answer.text,
                timestamp: DateTime(2026),
                citations: answer.citations,
              ).toMap(),
            );
            expect(restored.citations.single.toMap(), citation.toMap());
            expect(client.requests.single.instructions, contains(digest));
          },
        );
      }
    }
  }

  for (final streaming in [false, true]) {
    test(
      'missing or corrupt published text never falls back to source URL (stream=$streaming)',
      () async {
        for (final corrupt in [false, true]) {
          final input = await _publishedInput();
          if (corrupt) {
            input.fixture.corrupt = true;
          } else {
            input.fixture.contents.remove('cabo-rules');
          }
          final client = _FakeResponsesClient(responses: []);
          final telemetry = InMemoryAiRunTelemetrySink();
          await _publishedReply(
            ResponsesRulesWorkflow(
              responsesClient: client,
              telemetrySink: telemetry,
            ),
            input.game,
            input.assets,
            streaming: streaming,
          );
          expect(client.requests, isEmpty);
          expect(
            telemetry.recent.single.stages.last.errorCode,
            corrupt ? 'knowledge_integrity' : 'knowledge_unavailable',
          );
          expect(
            input.fixture.requests.every((r) => r.url.host == 'api.test'),
            isTrue,
          );
        }
      },
    );
  }

  test(
    'changed digest rejects stale game metadata and invalidates old compaction',
    () async {
      final input = await _publishedInput(community: false);
      final client = _FakeResponsesClient(
        responses: [
          ResponsesResponse(
            text: _structuredPublishedAnswer('cabo-rules'),
            model: 'test-model',
            outputItems: [_compaction('old-library')],
          ),
          _response(_structuredPublishedAnswer('cabo-rules')),
        ],
      );
      final telemetry = InMemoryAiRunTelemetrySink();
      final workflow = ResponsesRulesWorkflow(
        responsesClient: client,
        telemetrySink: telemetry,
      );
      final first = await _publishedReply(workflow, input.game, input.assets);
      final oldDigest = first!.citations.single.fileSha256;
      input.fixture.put('cabo', text: '更新后的发布正文', bump: true);
      await input.assets.refreshCatalog();
      await _publishedReply(workflow, input.game, input.assets);
      expect(
        client.requests,
        hasLength(1),
      ); // old game + new body cannot be cited
      expect(telemetry.recent.last.errorCode, 'knowledge_integrity');
      final nextGame = input.assets.catalog!.games.single.toGameInfo(
        AppLanguage.zhHans,
      );
      final next = await _publishedReply(workflow, nextGame, input.assets);
      expect(
        client.requests.last.input.whereType<ResponsesRawInput>(),
        isEmpty,
      );
      expect(
        utf8.decode(
          base64Decode(
            client.requests.last.input
                .whereType<ResponsesFileInput>()
                .single
                .fileData!,
          ),
        ),
        '更新后的发布正文',
      );
      expect(next!.citations.single.fileSha256, isNot(oldDigest));
      expect(first.citations.single.fileSha256, oldDigest);
    },
  );

  for (final streaming in [false, true]) {
    test(
      'real SDK full JSON stays below 512 KiB with Base64 and unicode history (stream=$streaming)',
      () async {
        final input = await _publishedInput(
          text: 'x' * (340 * 1024),
          community: false,
        );
        final original = Map<String, dynamic>.from(
          (input.fixture.editions['cabo']!['resources'] as List).firstWhere(
                (r) => r['id'] == 'cabo-rules',
              )
              as Map,
        );
        input.fixture.contents['cabo-extra'] = utf8.encode('y' * (200 * 1024));
        final digest = sha256
            .convert(input.fixture.contents['cabo-extra']!)
            .toString();
        (input.fixture.editions['cabo']!['resources'] as List).add({
          ...original,
          'id': 'cabo-extra',
          'path': 'docs/extra.md',
          'priority': 1000,
          'file_sha256': digest,
          'content_url':
              '/v1/apps/board_game_agent/catalog/resources/cabo-extra/content?version=$digest',
        });
        input.fixture.revision++;
        input.fixture.changes.add({
          'revision': input.fixture.revision,
          'edition_id': 'cabo',
          'kind': 'upsert',
        });
        await input.assets.refreshCatalog();
        final requests = <http.Request>[];
        Future<http.Response> handle(http.Request r) async {
          requests.add(r);
          expect(
            r.bodyBytes.length,
            lessThanOrEqualTo(ResponsesRequestBudget.accountBytes),
          );
          final body = jsonDecode(r.body) as Map<String, dynamic>;
          final items = body['input'] as List;
          final files = items
              .expand((item) => item['content'] as List? ?? [])
              .where((part) => part['type'] == 'input_file')
              .toList();
          expect(files, hasLength(1)); // second whole file cannot fit
          final bytes = base64Decode(
            (files.single['file_data'] as String).split(',').last,
          );
          expect(bytes, hasLength(340 * 1024)); // never truncate a document
          final ids =
              body['text']['format']['schema']['properties']['sourceIds']['items']['enum']
                  as List;
          expect(ids, ['cabo-rules']);
          expect(r.bodyBytes.length, greaterThan(480 * 1024));
          final response = {
            'id': 'resp-budget',
            'object': 'response',
            'created_at': 1,
            'model': 'test-model',
            'status': 'completed',
            'output': [
              _assistantOutput(
                1,
                _structuredPublishedAnswer(ids.single as String),
              ).toJson(),
            ],
          };
          if (!streaming) {
            return http.Response(
              jsonEncode(response),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          return http.Response(
            'data: ${jsonEncode({'type': 'response.completed', 'response': response})}\n\ndata: [DONE]\n\n',
            200,
            headers: {'content-type': 'text/event-stream; charset=utf-8'},
          );
        }

        final client = OpenAiDartResponsesAiClient(
          httpClient: MockClient(handle),
          streamClientFactory: () => MockClient(handle),
        );
        addTearDown(client.close);
        final answer = await _publishedReply(
          ResponsesRulesWorkflow(responsesClient: client),
          input.assets.catalog!.games.single.toGameInfo(AppLanguage.zhHans),
          input.assets,
          streaming: streaming,
          history: [
            ChatMessage(
              id: 'old-user',
              role: ChatRole.user,
              text: '中文' * 5000,
              timestamp: DateTime(2026),
            ),
          ],
        );
        expect(answer!.citations, hasLength(1));
        expect(requests, hasLength(1));
      },
    );
  }

  test(
    'single oversized file and oversized context are stopped before model transport',
    () async {
      final input = await _publishedInput(text: 'x' * (450 * 1024));
      final client = _FakeResponsesClient(responses: []);
      final telemetry = InMemoryAiRunTelemetrySink();
      final workflow = ResponsesRulesWorkflow(
        responsesClient: client,
        telemetrySink: telemetry,
      );
      await _publishedReply(workflow, input.game, input.assets);
      expect(client.requests, isEmpty);
      expect(telemetry.recent.last.stages.last.errorCode, 'request_too_large');
      await _publishedReply(
        workflow,
        input.game,
        input.assets,
        history: [
          ChatMessage(
            id: 'huge',
            role: ChatRole.user,
            text: '中' * 180000,
            timestamp: DateTime(2026),
          ),
        ],
      );
      expect(client.requests, isEmpty);
      expect(telemetry.recent.last.stages.last.requestCount, 0);
    },
  );
}

class _HeldKnowledgeFile extends _FakeRemoteAssetService {
  final started = Completer<void>();
  final release = Completer<List<int>?>();
  @override
  Future<List<int>?> loadBytes({
    required List<AssetSourceConfig> sources,
    required String remotePath,
    int maxBytes = 64 * 1024 * 1024,
    Duration? timeout,
    Future<void>? abortTrigger,
  }) {
    if (!started.isCompleted) started.complete();
    return release.future;
  }
}

class _CancellableResponseClient extends _FakeResponsesClient {
  _CancellableResponseClient() : super(responses: []);
  final started = Completer<void>(), cancelled = Completer<void>();
  @override
  Stream<ResponsesStreamEvent> stream(
    ResponsesRequest request, {
    Future<void>? abortTrigger,
  }) {
    requests.add(request);
    final controller = StreamController<ResponsesStreamEvent>(
      onCancel: () {
        if (!cancelled.isCompleted) cancelled.complete();
      },
    );
    abortTrigger?.then((_) {
      if (!controller.isClosed) unawaited(controller.close());
    });
    started.complete();
    return controller.stream;
  }
}

class _TimedKnowledgeAssets extends _FakeRemoteAssetService {
  final timeouts = <Duration>[];
  @override
  Future<List<int>?> loadBytes({
    required List<AssetSourceConfig> sources,
    required String remotePath,
    int maxBytes = 64 * 1024 * 1024,
    Duration? timeout,
    Future<void>? abortTrigger,
  }) async {
    timeouts.add(timeout!);
    await Future<void>.delayed(const Duration(milliseconds: 35));
    return utf8.encode(remotePath);
  }
}

class _CancelSecondKnowledgeFile extends _FakeRemoteAssetService {
  _CancelSecondKnowledgeFile(this.abort);
  final Completer<void> abort;
  int calls = 0;
  @override
  Future<List<int>?> loadBytes({
    required List<AssetSourceConfig> sources,
    required String remotePath,
    int maxBytes = 64 * 1024 * 1024,
    Duration? timeout,
    Future<void>? abortTrigger,
  }) async {
    if (++calls == 2) abort.complete();
    return utf8.encode(remotePath);
  }
}
