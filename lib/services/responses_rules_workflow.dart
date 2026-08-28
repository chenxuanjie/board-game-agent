import 'dart:convert';

import 'package:app_ai_client/app_ai_client.dart';
import 'package:crypto/crypto.dart';

import '../models/ai_api_config.dart';
import '../models/ai_answer_mode.dart';
import '../models/answer_source.dart';
import '../models/app_language.dart';
import '../models/asset_source_config.dart';
import '../models/board_game_ai_answer.dart';
import '../models/chat_message.dart';
import '../models/game_info.dart';
import '../models/game_resource.dart';
import '../models/rule_citation.dart';
import '../models/rule_document.dart';
import 'board_game_prompt_builder.dart';
import 'remote_asset_service.dart';
import 'ai_service.dart';
import 'responses_compaction_store.dart';

/// Three-stage rule workflow for the Responses API.
///
/// The workflow deliberately keeps retrieval and provider transport separate:
/// the selected game's knowledge paths choose declared files, while the shared
/// Responses adapter sends those files to the configured provider.
class ResponsesRulesWorkflow {
  static const int _maxConversationMessages = 12;
  // Keep a safety margin for providers whose model context window is smaller
  // than the largest modern Responses models. Server compaction is a guardrail
  // for long conversations, not a replacement for the local recent window.
  static const int _serverCompactionThreshold = 100000;

  ResponsesRulesWorkflow({
    required ResponsesAiClient responsesClient,
    BoardGamePromptBuilder? promptBuilder,
    ResponsesCompactionStore? compactionStore,
  }) : _responsesClient = responsesClient,
       _promptBuilder = promptBuilder ?? BoardGamePromptBuilder(),
       _compactionStore = compactionStore ?? InMemoryResponsesCompactionStore();

  final ResponsesAiClient _responsesClient;
  final BoardGamePromptBuilder _promptBuilder;
  final ResponsesCompactionStore _compactionStore;
  final Map<String, List<ResponsesInputItem>> _compactionInputsByContext =
      <String, List<ResponsesInputItem>>{};
  Future<void>? _compactionLoadFuture;
  bool _compactionLoaded = false;

  void close() {
    _compactionInputsByContext.clear();
    _responsesClient.close();
  }

  Future<BoardGameAiAnswer> generateReply({
    required String prompt,
    required AppLanguage language,
    required GameInfo game,
    required AiAnswerMode answerMode,
    required bool useGlobalMode,
    required AiApiConfig config,
    required List<AssetSourceConfig> assetSourceConfigs,
    required RemoteAssetService remoteAssetService,
    required List<ChatMessage> conversationHistory,
  }) async {
    await _ensureCompactionLoaded();
    final _WorkflowContext context = await _prepare(
      prompt: prompt,
      language: language,
      game: game,
      config: config,
      useGlobalMode: useGlobalMode,
      assetSourceConfigs: assetSourceConfigs,
      remoteAssetService: remoteAssetService,
      conversationHistory: conversationHistory,
    );

    final _StageResult official = await _runDocumentStage(
      context: context,
      documents: context.documents,
      source: AnswerSource.official,
      language: language,
      game: game,
    );
    if (official.answer != null) return official.answer!;

    if (answerMode == AiAnswerMode.knowledgeOnly) {
      return _unknownAnswer(language);
    }

    final _StageResult web = await _runWebStage(
      context: context,
      language: language,
      game: game,
    );
    if (web.answer != null) return web.answer!;

    return _runKnowledgeStage(
      context: context,
      language: language,
      game: game,
      useGlobalMode: useGlobalMode,
    );
  }

  Stream<BoardGameAiStreamEvent> streamReply({
    required String prompt,
    required AppLanguage language,
    required GameInfo game,
    required AiAnswerMode answerMode,
    required bool useGlobalMode,
    required AiApiConfig config,
    required List<AssetSourceConfig> assetSourceConfigs,
    required RemoteAssetService remoteAssetService,
    required List<ChatMessage> conversationHistory,
    Future<void>? abortTrigger,
  }) async* {
    await _ensureCompactionLoaded();
    final _WorkflowContext context = await _prepare(
      prompt: prompt,
      language: language,
      game: game,
      config: config,
      useGlobalMode: useGlobalMode,
      assetSourceConfigs: assetSourceConfigs,
      remoteAssetService: remoteAssetService,
      conversationHistory: conversationHistory,
    );

    yield const BoardGameAiStreamEvent(status: 'official');
    BoardGameAiAnswer? officialAnswer;
    await for (final _StageStreamEvent event in _streamDocumentStage(
      context: context,
      documents: context.documents,
      source: AnswerSource.official,
      language: language,
      game: game,
      abortTrigger: abortTrigger,
    )) {
      if (event.delta.isNotEmpty) {
        yield BoardGameAiStreamEvent(delta: event.delta);
      }
      if (event.citation != null) {
        yield BoardGameAiStreamEvent(
          citations: <RuleCitation>[event.citation!],
        );
      }
      if (event.answer != null) officialAnswer = event.answer;
    }
    if (officialAnswer != null) {
      yield BoardGameAiStreamEvent(
        answer: officialAnswer,
        citations: officialAnswer.citations,
        isDone: true,
      );
      return;
    }

    if (answerMode == AiAnswerMode.knowledgeOnly) {
      final BoardGameAiAnswer answer = _unknownAnswer(language);
      yield BoardGameAiStreamEvent(answer: answer, isDone: true);
      return;
    }

    yield const BoardGameAiStreamEvent(status: 'web_search');
    final List<RuleCitation> webCitations = <RuleCitation>[];
    BoardGameAiAnswer? webAnswer;
    await for (final _StageStreamEvent event in _streamWebStage(
      context: context,
      language: language,
      game: game,
      abortTrigger: abortTrigger,
    )) {
      if (event.delta.isNotEmpty) {
        yield BoardGameAiStreamEvent(delta: event.delta);
      }
      if (event.citation != null &&
          !webCitations.any(
            (RuleCitation item) => item.sourceId == event.citation!.sourceId,
          )) {
        webCitations.add(event.citation!);
        yield BoardGameAiStreamEvent(
          citations: <RuleCitation>[event.citation!],
        );
      }
      if (event.answer != null) {
        webAnswer = event.answer;
      }
    }
    if (webAnswer != null) {
      yield BoardGameAiStreamEvent(
        answer: webAnswer,
        citations: webAnswer.citations,
        isDone: true,
      );
      return;
    }

    yield const BoardGameAiStreamEvent(status: 'answering');
    final StringBuffer buffer = StringBuffer();
    await for (final ResponsesStreamEvent event in _responsesClient.stream(
      _knowledgeRequest(
        context,
        language: language,
        game: game,
        useGlobalMode: useGlobalMode,
      ),
      abortTrigger: abortTrigger,
    )) {
      if (event.response != null) {
        await _rememberCompaction(context, event.response!);
      }
      if (event.type == ResponsesStreamEventType.textDelta &&
          event.delta.isNotEmpty) {
        buffer.write(event.delta);
        yield BoardGameAiStreamEvent(delta: event.delta);
      }
      if (event.type == ResponsesStreamEventType.error) {
        throw StateError(event.errorMessage ?? 'Responses request failed.');
      }
    }
    final String text = buffer.toString().trim();
    final BoardGameAiAnswer answer = BoardGameAiAnswer(
      text: text.isEmpty ? _unknownAnswer(language).text : text,
      source: text.isEmpty
          ? AnswerSource.insufficient
          : AnswerSource.modelKnowledge,
    );
    yield BoardGameAiStreamEvent(answer: answer, isDone: true);
  }

  Future<_WorkflowContext> _prepare({
    required String prompt,
    required AppLanguage language,
    required GameInfo game,
    required AiApiConfig config,
    required bool useGlobalMode,
    required List<AssetSourceConfig> assetSourceConfigs,
    required RemoteAssetService remoteAssetService,
    required List<ChatMessage> conversationHistory,
  }) async {
    return _WorkflowContext(
      prompt: prompt,
      language: language,
      game: game,
      config: config,
      useGlobalMode: useGlobalMode,
      sources: assetSourceConfigs,
      remoteAssetService: remoteAssetService,
      conversation: <ResponsesInputItem>[
        ..._compactionInputsFor(
          config: config,
          game: game,
          useGlobalMode: useGlobalMode,
        ),
        ..._conversationInputs(conversationHistory, prompt),
      ],
      documents: _documentsForGame(game),
    );
  }

  Future<_StageResult> _runDocumentStage({
    required _WorkflowContext context,
    required List<RuleDocument> documents,
    required AnswerSource source,
    required AppLanguage language,
    required GameInfo game,
  }) async {
    try {
      final _PreparedDocuments prepared = await _prepareDocuments(
        context,
        documents,
      );
      if (prepared.inputs.isEmpty) return const _StageResult();
      final ResponsesResponse response = await _responsesClient.complete(
        _documentRequest(
          context,
          prepared.inputs,
          language: language,
          game: game,
          source: source,
        ),
      );
      await _rememberCompaction(context, response);
      final _ParsedAnswer parsed = _parseStructured(
        response.text,
        prepared.documents,
        source,
      );
      return _StageResult(answer: parsed.answer);
    } catch (_) {
      return const _StageResult();
    }
  }

  Stream<_StageStreamEvent> _streamDocumentStage({
    required _WorkflowContext context,
    required List<RuleDocument> documents,
    required AnswerSource source,
    required AppLanguage language,
    required GameInfo game,
    Future<void>? abortTrigger,
  }) async* {
    try {
      final _PreparedDocuments prepared = await _prepareDocuments(
        context,
        documents,
      );
      if (prepared.inputs.isEmpty) return;
      final StringBuffer raw = StringBuffer();
      String emittedAnswer = '';
      await for (final ResponsesStreamEvent event in _responsesClient.stream(
        _documentRequest(
          context,
          prepared.inputs,
          language: language,
          game: game,
          source: source,
        ),
        abortTrigger: abortTrigger,
      )) {
        if (event.response != null) {
          await _rememberCompaction(context, event.response!);
        }
        if (event.type == ResponsesStreamEventType.textDelta &&
            event.delta.isNotEmpty) {
          raw.write(event.delta);
          final String partial = _partialStructuredAnswer(raw.toString());
          if (partial.length > emittedAnswer.length) {
            final String delta = partial.substring(emittedAnswer.length);
            emittedAnswer = partial;
            yield _StageStreamEvent.delta(delta);
          }
        }
        if (event.type == ResponsesStreamEventType.error) {
          return;
        }
      }
      final BoardGameAiAnswer? answer = _parseStructured(
        raw.toString(),
        prepared.documents,
        source,
      ).answer;
      if (answer != null) {
        yield _StageStreamEvent.answer(answer);
      }
    } catch (_) {
      return;
    }
  }

  Future<_StageResult> _runWebStage({
    required _WorkflowContext context,
    required AppLanguage language,
    required GameInfo game,
  }) async {
    try {
      final ResponsesResponse response = await _responsesClient.complete(
        _webRequest(context, language: language, game: game),
      );
      await _rememberCompaction(context, response);
      if (response.text.trim().isEmpty || response.webSearchCitations.isEmpty) {
        return const _StageResult();
      }
      return _StageResult(
        answer: BoardGameAiAnswer(
          text: response.text.trim(),
          source: AnswerSource.web,
          citations: response.webSearchCitations
              .map(_webCitation)
              .toList(growable: false),
        ),
        streamedText: response.text,
      );
    } catch (_) {
      return const _StageResult();
    }
  }

  Stream<_StageStreamEvent> _streamWebStage({
    required _WorkflowContext context,
    required AppLanguage language,
    required GameInfo game,
    Future<void>? abortTrigger,
  }) async* {
    try {
      final StringBuffer text = StringBuffer();
      final List<RuleCitation> citations = <RuleCitation>[];
      await for (final ResponsesStreamEvent event in _responsesClient.stream(
        _webRequest(context, language: language, game: game),
        abortTrigger: abortTrigger,
      )) {
        if (event.response != null) {
          await _rememberCompaction(context, event.response!);
        }
        if (event.type == ResponsesStreamEventType.textDelta &&
            event.delta.isNotEmpty) {
          text.write(event.delta);
          yield _StageStreamEvent.delta(event.delta);
        }
        if (event.webSearchCitation != null) {
          final RuleCitation citation = _webCitation(event.webSearchCitation!);
          if (!citations.any((item) => item.sourceId == citation.sourceId)) {
            citations.add(citation);
            yield _StageStreamEvent.citation(citation);
          }
        }
        if (event.type == ResponsesStreamEventType.error) {
          return;
        }
      }
      final String answerText = text.toString().trim();
      if (answerText.isEmpty || citations.isEmpty) return;
      yield _StageStreamEvent.answer(
        BoardGameAiAnswer(
          text: answerText,
          source: AnswerSource.web,
          citations: citations,
        ),
      );
    } catch (_) {
      return;
    }
  }

  Future<BoardGameAiAnswer> _runKnowledgeStage({
    required _WorkflowContext context,
    required AppLanguage language,
    required GameInfo game,
    required bool useGlobalMode,
  }) async {
    try {
      final ResponsesResponse response = await _responsesClient.complete(
        _knowledgeRequest(
          context,
          language: language,
          game: game,
          useGlobalMode: useGlobalMode,
        ),
      );
      await _rememberCompaction(context, response);
      final String text = response.text.trim();
      return BoardGameAiAnswer(
        text: text.isEmpty ? _unknownAnswer(language).text : text,
        source: text.isEmpty
            ? AnswerSource.insufficient
            : AnswerSource.modelKnowledge,
      );
    } catch (_) {
      return _unknownAnswer(language);
    }
  }

  ResponsesRequest _documentRequest(
    _WorkflowContext context,
    List<ResponsesInputItem> files, {
    required AppLanguage language,
    required GameInfo game,
    required AnswerSource source,
  }) {
    final String sourceLabel = source == AnswerSource.official
        ? '官方资料'
        : '社区资料';
    final String system = _promptBuilder.buildResponsesDocumentInstructions(
      language: language,
      game: game,
      sourceLabel: sourceLabel,
    );
    return ResponsesRequest(
      endpoint: _endpoint(context.config),
      instructions: system,
      input: <ResponsesInputItem>[
        ...context.conversation.whereType<ResponsesRawInput>(),
        ...files,
        ...context.conversation.where(
          (ResponsesInputItem item) => item is! ResponsesRawInput,
        ),
      ],
      maxOutputTokens: 1200,
      reasoningEffort: context.config.reasoningEffort.requestValue,
      serviceTier: context.config.responseSpeed.serviceTier,
      contextManagement: _contextManagementFor(context.config),
    );
  }

  ResponsesRequest _webRequest(
    _WorkflowContext context, {
    required AppLanguage language,
    required GameInfo game,
  }) => ResponsesRequest(
    endpoint: _endpoint(context.config),
    instructions: _promptBuilder.buildResponsesWebInstructions(
      language: language,
      game: game,
    ),
    input: context.conversation,
    tools: const <ResponsesToolDefinition>[ResponsesToolDefinition.webSearch()],
    maxOutputTokens: 1200,
    reasoningEffort: context.config.reasoningEffort.requestValue,
    serviceTier: context.config.responseSpeed.serviceTier,
    contextManagement: _contextManagementFor(context.config),
  );

  ResponsesRequest _knowledgeRequest(
    _WorkflowContext context, {
    required AppLanguage language,
    required GameInfo game,
    bool useGlobalMode = false,
  }) => ResponsesRequest(
    endpoint: _endpoint(context.config),
    instructions: _promptBuilder.buildResponsesKnowledgeInstructions(
      language: language,
      game: game,
      useGlobalMode: useGlobalMode,
    ),
    input: context.conversation,
    maxOutputTokens: 1200,
    reasoningEffort: context.config.reasoningEffort.requestValue,
    serviceTier: context.config.responseSpeed.serviceTier,
    contextManagement: _contextManagementFor(context.config),
  );

  List<ResponsesContextManagement> _contextManagementFor(AiApiConfig config) {
    final AiProviderPreset preset = config.providerPreset;
    if (preset != AiProviderPreset.openAi &&
        preset != AiProviderPreset.custom) {
      return const <ResponsesContextManagement>[];
    }
    return const <ResponsesContextManagement>[
      ResponsesContextManagement.compaction(
        compactThreshold: _serverCompactionThreshold,
      ),
    ];
  }

  List<ResponsesInputItem> _compactionInputsFor({
    required AiApiConfig config,
    required GameInfo game,
    required bool useGlobalMode,
  }) {
    return List<ResponsesInputItem>.unmodifiable(
      _compactionInputsByContext[_contextKey(
            config: config,
            game: game,
            useGlobalMode: useGlobalMode,
          )] ??
          const <ResponsesInputItem>[],
    );
  }

  Future<void> _rememberCompaction(
    _WorkflowContext context,
    ResponsesResponse response,
  ) async {
    final List<ResponsesInputItem> compactionItems = response.outputItems
        .where(
          (ResponsesInputItem item) =>
              item is ResponsesRawInput && item.value['type'] == 'compaction',
        )
        .toList(growable: false);
    if (compactionItems.isEmpty) return;
    _compactionInputsByContext[_contextKey(
      config: context.config,
      game: context.game,
      useGlobalMode: context.useGlobalMode,
    )] = List<ResponsesInputItem>.unmodifiable(
      compactionItems,
    );
    try {
      await _compactionStore.save(_compactionInputsByContext);
    } catch (_) {
      // Compaction persistence is a cache optimization. A secure-storage
      // failure must not turn an otherwise valid AI response into a failure.
    }
  }

  String _contextKey({
    required AiApiConfig config,
    required GameInfo game,
    required bool useGlobalMode,
  }) {
    final String scope = useGlobalMode ? 'global' : 'game:${game.slug}';
    final String endpointFingerprint = sha256
        .convert(
          utf8.encode(
            <String>[
              config.name.trim(),
              config.baseUrl.trim(),
              config.model.trim(),
              config.apiKey.trim(),
              config.apiKeyHeader.trim(),
            ].join('|'),
          ),
        )
        .toString();
    return '$scope|$endpointFingerprint';
  }

  Future<void> _ensureCompactionLoaded() {
    if (_compactionLoaded) return Future<void>.value();
    return _compactionLoadFuture ??= _loadCompactionState();
  }

  Future<void> _loadCompactionState() async {
    try {
      final Map<String, List<ResponsesInputItem>> stored =
          await _compactionStore.load();
      _compactionInputsByContext
        ..clear()
        ..addAll(stored);
    } catch (_) {
      // A corrupt/unavailable secure store should not block the first chat.
      _compactionInputsByContext.clear();
    } finally {
      _compactionLoaded = true;
    }
  }

  Future<_PreparedDocuments> _prepareDocuments(
    _WorkflowContext context,
    List<RuleDocument> documents,
  ) async {
    final List<ResponsesInputItem> inputs = <ResponsesInputItem>[];
    final List<RuleDocument> loaded = <RuleDocument>[];
    for (final RuleDocument document in documents.take(4)) {
      if (isOtherStoragePath(document.path)) {
        continue;
      }
      if (document.url != null && _isPublicHttps(document.url!)) {
        inputs.add(
          ResponsesFileInput.url(
            document.url!,
            filename: document.title,
            role: ResponsesInputRole.user,
          ),
        );
        loaded.add(document);
        continue;
      }
      final List<int>? bytes = await context.remoteAssetService.loadBytes(
        sources: context.sources,
        remotePath: document.path,
      );
      if (bytes == null || bytes.isEmpty) continue;
      inputs.add(
        ResponsesFileInput.data(
          base64Encode(bytes),
          mediaType: _mediaType(document.format),
          filename: document.title,
          role: ResponsesInputRole.user,
        ),
      );
      loaded.add(document);
    }
    return _PreparedDocuments(inputs: inputs, documents: loaded);
  }

  _ParsedAnswer _parseStructured(
    String raw,
    List<RuleDocument> documents,
    AnswerSource source,
  ) {
    try {
      final dynamic decoded = jsonDecode(_stripCodeFences(raw));
      if (decoded is! Map) return const _ParsedAnswer();
      final String status = '${decoded['status'] ?? ''}'.toLowerCase();
      final String answer = '${decoded['answer'] ?? ''}'.trim();
      if (status != 'answered' || answer.isEmpty) return const _ParsedAnswer();
      final Set<String> ids =
          (decoded['sourceIds'] is List
                  ? (decoded['sourceIds'] as List).whereType<String>()
                  : const <String>[])
              .toSet();
      final List<RuleCitation> citations = documents
          .where((document) => ids.contains(document.id))
          .map((document) => document.toCitation())
          .toList();
      if (citations.isEmpty) return const _ParsedAnswer();
      return _ParsedAnswer(
        answer: BoardGameAiAnswer(
          text: answer,
          source: source,
          citations: citations,
        ),
      );
    } catch (_) {
      return const _ParsedAnswer();
    }
  }

  List<RuleDocument> _documentsForGame(GameInfo game) {
    final Map<String, GameResource> resourcesByPath = <String, GameResource>{
      for (final GameResource resource in game.resources)
        if (!resource.isInOthersDirectory &&
            resource.assetPathFor(game.slug).trim().isNotEmpty)
          resource.assetPathFor(game.slug): resource,
    };

    return game.knowledgeAssetPaths
        .where((path) => path.trim().isNotEmpty && !isOtherStoragePath(path))
        .toList(growable: false)
        .asMap()
        .entries
        .map((entry) {
          final GameResource? resource = resourcesByPath[entry.value];
          return RuleDocument(
            id: resource?.id ?? '${game.slug}-knowledge-${entry.key}',
            title: resource?.fileName ?? _documentTitle(entry.value),
            path: entry.value,
            format: resource?.format ?? _documentFormat(entry.value),
            language: resource?.language ?? _documentLanguage(entry.value),
            sourceType: resource?.sourceClass ?? 'official',
            version: resource?.edition,
            url: resource?.sourceUrl,
          );
        })
        .toList(growable: false);
  }

  String _documentTitle(String path) {
    final String normalized = path.replaceAll('\\', '/');
    final int slash = normalized.lastIndexOf('/');
    return slash == -1 ? normalized : normalized.substring(slash + 1);
  }

  String _documentFormat(String path) {
    final String title = _documentTitle(path);
    final int dot = title.lastIndexOf('.');
    return dot == -1 ? 'bin' : title.substring(dot + 1).toLowerCase();
  }

  String _documentLanguage(String path) {
    final String title = _documentTitle(path).toLowerCase();
    if (title.contains('_en.') || title.contains('-en.')) return 'en';
    if (title.contains('_zh.') ||
        title.contains('-zh.') ||
        title.contains('_zh-hans.') ||
        title.contains('-zh-hans.')) {
      return 'zh';
    }
    return 'unknown';
  }

  List<ResponsesInputItem> _conversationInputs(
    List<ChatMessage> history,
    String prompt,
  ) {
    final List<ChatMessage> nonEmptyHistory = history
        .where((message) => message.text.trim().isNotEmpty)
        .toList(growable: false);
    final int start = nonEmptyHistory.length > _maxConversationMessages
        ? nonEmptyHistory.length - _maxConversationMessages
        : 0;
    final List<ResponsesInputItem> result = nonEmptyHistory
        .sublist(start)
        .map(
          (message) => ResponsesTextInput(
            message.text.trim(),
            role: message.role == ChatRole.user
                ? ResponsesInputRole.user
                : ResponsesInputRole.assistant,
          ),
        )
        .toList();
    if (result.isEmpty ||
        result.last is! ResponsesTextInput ||
        (result.last as ResponsesTextInput).text != prompt) {
      result.add(ResponsesTextInput(prompt));
    }
    return result;
  }

  AiEndpointConfig _endpoint(AiApiConfig config) => AiEndpointConfig(
    name: config.name,
    baseUrl: config.baseUrl,
    apiKey: config.apiKey,
    model: config.model,
    apiKeyHeader: 'Authorization',
  );

  BoardGameAiAnswer _unknownAnswer(AppLanguage language) => BoardGameAiAnswer(
    text: language == AppLanguage.zhHans
        ? '当前规则资料不足，暂时没有找到直接依据。'
        : 'The available rule sources do not contain enough information.',
    source: AnswerSource.insufficient,
  );

  bool _isPublicHttps(String value) {
    final Uri? uri = Uri.tryParse(value);
    return uri?.scheme == 'https' && uri?.host.isNotEmpty == true;
  }

  String _mediaType(String format) => switch (format.toLowerCase()) {
    'pdf' => 'application/pdf',
    'txt' => 'text/plain',
    'md' || 'markdown' => 'text/markdown',
    _ => 'application/octet-stream',
  };

  String _stripCodeFences(String value) => value
      .trim()
      .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
      .replaceFirst(RegExp(r'\s*```$'), '')
      .trim();

  String _partialStructuredAnswer(String raw) {
    final RegExpMatch? statusMatch = RegExp(
      r'"status"\s*:\s*"([^"\\]+)"',
      caseSensitive: false,
    ).firstMatch(raw);
    if (statusMatch?.group(1)?.toLowerCase() != 'answered') return '';
    final RegExpMatch? answerMatch = RegExp(
      r'"answer"\s*:\s*"',
      caseSensitive: false,
    ).firstMatch(raw);
    if (answerMatch == null) return '';

    final StringBuffer encoded = StringBuffer();
    bool escaped = false;
    for (int index = answerMatch.end; index < raw.length; index += 1) {
      final String character = raw[index];
      if (escaped) {
        encoded.write(character);
        escaped = false;
        continue;
      }
      if (character == r'\') {
        encoded.write(character);
        escaped = true;
        continue;
      }
      if (character == '"') break;
      encoded.write(character);
    }
    final String value = encoded.toString();
    if (value.isEmpty) return '';
    try {
      return jsonDecode('"$value"') as String;
    } catch (_) {
      return value
          .replaceAll(r'\n', '\n')
          .replaceAll(r'\r', '\r')
          .replaceAll(r'\"', '"')
          .replaceAll(r'\\', r'\');
    }
  }

  RuleCitation _webCitation(ResponsesWebSearchCitation item) => RuleCitation(
    sourceType: 'web',
    sourceId: item.url,
    title: item.title,
    url: item.url,
  );
}

class _WorkflowContext {
  const _WorkflowContext({
    required this.prompt,
    required this.language,
    required this.game,
    required this.config,
    required this.useGlobalMode,
    required this.sources,
    required this.remoteAssetService,
    required this.conversation,
    required this.documents,
  });

  final String prompt;
  final AppLanguage language;
  final GameInfo game;
  final AiApiConfig config;
  final bool useGlobalMode;
  final List<AssetSourceConfig> sources;
  final RemoteAssetService remoteAssetService;
  final List<ResponsesInputItem> conversation;
  final List<RuleDocument> documents;
}

class _PreparedDocuments {
  const _PreparedDocuments({required this.inputs, required this.documents});

  final List<ResponsesInputItem> inputs;
  final List<RuleDocument> documents;
}

class _ParsedAnswer {
  const _ParsedAnswer({this.answer});

  final BoardGameAiAnswer? answer;
}

class _StageResult {
  const _StageResult({this.answer, this.streamedText = ''});

  final BoardGameAiAnswer? answer;
  final String streamedText;
}

class _StageStreamEvent {
  const _StageStreamEvent({this.delta = '', this.citation, this.answer});

  const _StageStreamEvent.delta(String value) : this(delta: value);

  const _StageStreamEvent.citation(RuleCitation value) : this(citation: value);

  const _StageStreamEvent.answer(BoardGameAiAnswer value) : this(answer: value);

  final String delta;
  final RuleCitation? citation;
  final BoardGameAiAnswer? answer;
}
