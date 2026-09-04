import 'dart:async';
import 'dart:convert';

import 'package:app_ai_client/app_ai_client.dart';
import 'package:crypto/crypto.dart';

import '../models/ai_api_config.dart';
import '../models/ai_answer_mode.dart';
import '../models/ai_run.dart';
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
import 'board_game_question_classifier.dart';
import 'board_game_question_router.dart';
import 'remote_asset_service.dart';
import 'ai_service.dart';
import 'responses_compaction_store.dart';
import 'ai_run_orchestrator.dart';
import 'ai_run_telemetry.dart';
import 'ai_error_presenter.dart';

typedef _AiStageResultBuilder = AiStageResult Function(_CollectedStream stream);

/// Stage-based rule workflow for the Responses API.
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
    BoardGameQuestionRouter? questionRouter,
    BoardGameQuestionClassifier? questionClassifier,
    AiRunTelemetrySink? telemetrySink,
  }) : _responsesClient = responsesClient,
       _promptBuilder = promptBuilder ?? BoardGamePromptBuilder(),
       _compactionStore = compactionStore ?? InMemoryResponsesCompactionStore(),
       _questionRouter = questionRouter ?? const BoardGameQuestionRouter(),
       _questionClassifier =
           questionClassifier ?? BoardGameQuestionClassifier(),
       _telemetrySink = telemetrySink ?? InMemoryAiRunTelemetrySink(),
       _orchestrator = const AiRunOrchestrator();

  final ResponsesAiClient _responsesClient;
  final BoardGamePromptBuilder _promptBuilder;
  final ResponsesCompactionStore _compactionStore;
  final BoardGameQuestionRouter _questionRouter;
  final BoardGameQuestionClassifier _questionClassifier;
  final AiRunTelemetrySink _telemetrySink;
  final AiRunOrchestrator _orchestrator;
  final Map<String, List<ResponsesInputItem>> _compactionInputsByContext =
      <String, List<ResponsesInputItem>>{};
  final Map<String, String> _activeCompactionContextByScope =
      <String, String>{};
  Future<void>? _compactionLoadFuture;
  bool _compactionLoaded = false;

  void close() {
    _compactionInputsByContext.clear();
    _activeCompactionContextByScope.clear();
    _responsesClient.close();
  }

  Future<void> _recordTelemetry(AiRunResult result) async {
    try {
      await _telemetrySink.record(result);
    } on Object {
      // Observability must never convert a valid answer into a failed chat.
      // The sink remains independently retryable on the next run.
    }
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
    bool useCurrentGameKnowledge = false,
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
      useCurrentGameKnowledge: useCurrentGameKnowledge,
    );

    if (answerMode == AiAnswerMode.knowledgeThenDirect) {
      final BoardGameQuestionRoutingDecision routing =
          await _resolveQuestionRoute(
            context: context,
            language: language,
            game: game,
            useGlobalMode: useGlobalMode,
            useCurrentGameKnowledge: useCurrentGameKnowledge,
          );
      if (routing.route == BoardGameQuestionRoute.general) {
        final AiRunResult run = await _orchestrator.run(
          runId: _runId(),
          sessionId: context.session.id,
          contextKey: context.contextKey,
          model: context.config.model,
          stages: <AiStageDefinition>[
            AiStageDefinition(
              stageId: 'general',
              scope: const AiKnowledgeScope.general(),
              execute: () => _executeGeneralStage(
                context: context,
                language: language,
                game: game,
              ),
            ),
          ],
        );
        await _recordTelemetry(run);
        return run.answer ?? _unknownAnswer(language);
      }
    }

    final AiRunResult run = await _orchestrator.run(
      runId: _runId(),
      sessionId: context.session.id,
      contextKey: context.contextKey,
      model: context.config.model,
      stages: _stageDefinitions(
        context: context,
        language: language,
        game: game,
        answerMode: answerMode,
        useGlobalMode: useGlobalMode,
        useCurrentGameKnowledge: useCurrentGameKnowledge,
      ),
    );
    await _recordTelemetry(run);
    return run.answer ?? _unknownAnswer(language);
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
    bool useCurrentGameKnowledge = false,
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
      useCurrentGameKnowledge: useCurrentGameKnowledge,
    );

    if (answerMode == AiAnswerMode.knowledgeThenDirect) {
      final BoardGameQuestionRoutingDecision localRouting = _questionRouter
          .decide(
            prompt: prompt,
            game: game,
            useGlobalMode: useGlobalMode,
            useCurrentGameKnowledge: useCurrentGameKnowledge,
          );
      if (localRouting.needsModelClassification) {
        yield const BoardGameAiStreamEvent(status: 'routing');
      }
      final BoardGameQuestionRoutingDecision routing =
          await _resolveQuestionRoute(
            context: context,
            language: language,
            game: game,
            useGlobalMode: useGlobalMode,
            useCurrentGameKnowledge: useCurrentGameKnowledge,
            localDecision: localRouting,
            abortTrigger: abortTrigger,
          );
      if (routing.route == BoardGameQuestionRoute.general) {
        yield* _streamOrchestrated(
          runId: _runId(),
          stages: <AiStageDefinition>[
            AiStageDefinition(
              stageId: 'general',
              scope: const AiKnowledgeScope.general(),
              executeStream: () => _streamGeneralStageEvents(
                context: context,
                scope: const AiKnowledgeScope.general(),
                language: language,
                game: game,
                abortTrigger: abortTrigger,
              ),
            ),
          ],
          contextKey: context.contextKey,
          sessionId: context.session.id,
          model: context.config.model,
          language: language,
          abortTrigger: abortTrigger,
        );
        return;
      }
    }

    yield* _streamOrchestrated(
      runId: _runId(),
      stages: _streamStageDefinitions(
        context: context,
        language: language,
        game: game,
        answerMode: answerMode,
        useGlobalMode: useGlobalMode,
        useCurrentGameKnowledge: useCurrentGameKnowledge,
        abortTrigger: abortTrigger,
      ),
      contextKey: context.contextKey,
      sessionId: context.session.id,
      model: context.config.model,
      language: language,
      abortTrigger: abortTrigger,
    );
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
    required bool useCurrentGameKnowledge,
  }) async {
    final String contextKey = _contextKey(
      config: config,
      game: game,
      useGlobalMode: useGlobalMode,
      useCurrentGameKnowledge: useCurrentGameKnowledge,
    );
    await _activateCompactionContext(
      contextKey: contextKey,
      game: game,
      useGlobalMode: useGlobalMode,
    );
    final List<ResponsesInputItem> compaction = _compactionInputsFor(
      config: config,
      game: game,
      useGlobalMode: useGlobalMode,
      useCurrentGameKnowledge: useCurrentGameKnowledge,
    );
    // A provider compaction item is a replacement snapshot, not an extra
    // history message. Once present, discard the older local input window and
    // send only the opaque snapshot plus the current user turn.
    final List<ResponsesInputItem> conversation = compaction.isNotEmpty
        ? <ResponsesInputItem>[...compaction, ResponsesTextInput(prompt)]
        : _conversationInputs(conversationHistory, prompt);
    final String scopeKey = useGlobalMode ? 'global' : 'game:${game.slug}';
    return _WorkflowContext(
      prompt: prompt,
      language: language,
      game: game,
      config: config,
      useGlobalMode: useGlobalMode,
      useCurrentGameKnowledge: useCurrentGameKnowledge,
      contextKey: contextKey,
      session: AiSession(
        id: contextKey,
        contextKey: contextKey,
        scopeKey: scopeKey,
        model: config.model.trim(),
      ),
      sources: assetSourceConfigs,
      remoteAssetService: remoteAssetService,
      conversation: conversation,
      documents: _documentsForGame(game),
    );
  }

  Future<BoardGameQuestionRoutingDecision> _resolveQuestionRoute({
    required _WorkflowContext context,
    required AppLanguage language,
    required GameInfo game,
    required bool useGlobalMode,
    required bool useCurrentGameKnowledge,
    BoardGameQuestionRoutingDecision? localDecision,
    Future<void>? abortTrigger,
  }) async {
    final BoardGameQuestionRoutingDecision local =
        localDecision ??
        _questionRouter.decide(
          prompt: context.prompt,
          game: game,
          useGlobalMode: useGlobalMode,
          useCurrentGameKnowledge: useCurrentGameKnowledge,
        );
    if (!local.needsModelClassification) return local;
    return _questionClassifier.classifyResponses(
      client: _responsesClient,
      endpoint: _endpoint(context.config),
      language: language,
      game: game,
      useGlobalMode: useGlobalMode,
      prompt: context.prompt,
      fallback: _questionRouter.fallback(
        useGlobalMode: useGlobalMode,
        useCurrentGameKnowledge: useCurrentGameKnowledge,
      ),
      useCurrentGameKnowledge: useCurrentGameKnowledge,
      reasoningEffort: context.config.reasoningEffort.requestValue,
      serviceTier: context.config.responseSpeed.serviceTier,
      abortTrigger: abortTrigger,
    );
  }

  List<AiStageDefinition> _stageDefinitions({
    required _WorkflowContext context,
    required AppLanguage language,
    required GameInfo game,
    required AiAnswerMode answerMode,
    required bool useGlobalMode,
    required bool useCurrentGameKnowledge,
  }) {
    if (useGlobalMode && !useCurrentGameKnowledge) {
      if (answerMode == AiAnswerMode.knowledgeOnly) {
        return <AiStageDefinition>[_unavailableKnowledgeStage(gameId: game.id)];
      }
      return <AiStageDefinition>[
        AiStageDefinition(
          stageId: 'fallback',
          scope: AiKnowledgeScope.fallback(gameId: game.id),
          execute: () async => _asAiStageResult(
            stageId: 'fallback',
            scope: AiKnowledgeScope.fallback(gameId: game.id),
            result: await _runKnowledgeStage(
              context: context,
              language: language,
              game: game,
              useGlobalMode: useGlobalMode,
            ),
          ),
        ),
      ];
    }
    final List<AiStageDefinition> stages = <AiStageDefinition>[
      AiStageDefinition(
        stageId: 'official',
        scope: AiKnowledgeScope.official(gameId: game.id),
        execute: () async => _asAiStageResult(
          stageId: 'official',
          scope: AiKnowledgeScope.official(gameId: game.id),
          result: await _runDocumentStage(
            context: context,
            documents: _documentsForSource(
              context.documents,
              AnswerSource.official,
            ),
            source: AnswerSource.official,
            language: language,
            game: game,
          ),
        ),
      ),
      AiStageDefinition(
        stageId: 'community',
        scope: AiKnowledgeScope.community(gameId: game.id),
        execute: () async => _asAiStageResult(
          stageId: 'community',
          scope: AiKnowledgeScope.community(gameId: game.id),
          result: await _runDocumentStage(
            context: context,
            documents: _documentsForSource(
              context.documents,
              AnswerSource.community,
            ),
            source: AnswerSource.community,
            language: language,
            game: game,
          ),
        ),
      ),
    ];

    if (answerMode == AiAnswerMode.knowledgeOnly) return stages;

    stages.addAll(<AiStageDefinition>[
      AiStageDefinition(
        stageId: 'web',
        scope: AiKnowledgeScope.web(gameId: game.id),
        execute: () async => _asAiStageResult(
          stageId: 'web',
          scope: AiKnowledgeScope.web(gameId: game.id),
          result: await _runWebStage(
            context: context,
            language: language,
            game: game,
          ),
        ),
      ),
      AiStageDefinition(
        stageId: 'fallback',
        scope: AiKnowledgeScope.fallback(gameId: game.id),
        execute: () async => _asAiStageResult(
          stageId: 'fallback',
          scope: AiKnowledgeScope.fallback(gameId: game.id),
          result: await _runKnowledgeStage(
            context: context,
            language: language,
            game: game,
            useGlobalMode: useGlobalMode,
          ),
        ),
      ),
    ]);
    return stages;
  }

  List<AiStageDefinition> _streamStageDefinitions({
    required _WorkflowContext context,
    required AppLanguage language,
    required GameInfo game,
    required AiAnswerMode answerMode,
    required bool useGlobalMode,
    required bool useCurrentGameKnowledge,
    required Future<void>? abortTrigger,
  }) {
    if (useGlobalMode && !useCurrentGameKnowledge) {
      if (answerMode == AiAnswerMode.knowledgeOnly) {
        return <AiStageDefinition>[_unavailableKnowledgeStage(gameId: game.id)];
      }
      final AiKnowledgeScope fallbackScope = AiKnowledgeScope.fallback(
        gameId: game.id,
      );
      return <AiStageDefinition>[
        AiStageDefinition(
          stageId: 'fallback',
          scope: fallbackScope,
          executeStream: () => _streamKnowledgeStageEvents(
            context: context,
            scope: fallbackScope,
            language: language,
            game: game,
            useGlobalMode: useGlobalMode,
            abortTrigger: abortTrigger,
          ),
        ),
      ];
    }
    final AiKnowledgeScope officialScope = AiKnowledgeScope.official(
      gameId: game.id,
    );
    final AiKnowledgeScope communityScope = AiKnowledgeScope.community(
      gameId: game.id,
    );
    final List<AiStageDefinition> stages = <AiStageDefinition>[
      AiStageDefinition(
        stageId: 'official',
        scope: officialScope,
        executeStream: () => _streamDocumentStageEvents(
          context: context,
          documents: _documentsForSource(
            context.documents,
            AnswerSource.official,
          ),
          source: AnswerSource.official,
          scope: officialScope,
          language: language,
          game: game,
          abortTrigger: abortTrigger,
        ),
      ),
      AiStageDefinition(
        stageId: 'community',
        scope: communityScope,
        executeStream: () => _streamDocumentStageEvents(
          context: context,
          documents: _documentsForSource(
            context.documents,
            AnswerSource.community,
          ),
          source: AnswerSource.community,
          scope: communityScope,
          language: language,
          game: game,
          abortTrigger: abortTrigger,
        ),
      ),
    ];

    if (answerMode == AiAnswerMode.knowledgeOnly) return stages;

    final AiKnowledgeScope webScope = AiKnowledgeScope.web(gameId: game.id);
    final AiKnowledgeScope fallbackScope = AiKnowledgeScope.fallback(
      gameId: game.id,
    );
    stages.addAll(<AiStageDefinition>[
      AiStageDefinition(
        stageId: 'web',
        scope: webScope,
        executeStream: () => _streamWebStageEvents(
          context: context,
          scope: webScope,
          language: language,
          game: game,
          abortTrigger: abortTrigger,
        ),
      ),
      AiStageDefinition(
        stageId: 'fallback',
        scope: fallbackScope,
        executeStream: () => _streamKnowledgeStageEvents(
          context: context,
          scope: fallbackScope,
          language: language,
          game: game,
          useGlobalMode: useGlobalMode,
          abortTrigger: abortTrigger,
        ),
      ),
    ]);
    return stages;
  }

  AiStageDefinition _unavailableKnowledgeStage({required String gameId}) {
    final AiKnowledgeScope scope = AiKnowledgeScope.official(gameId: gameId);
    return AiStageDefinition(
      stageId: 'knowledge_scope',
      scope: scope,
      execute: () async => AiStageResult(
        stageId: 'knowledge_scope',
        scope: scope,
        status: AiStageStatus.skipped,
      ),
    );
  }

  Stream<BoardGameAiStreamEvent> _streamOrchestrated({
    required String runId,
    required List<AiStageDefinition> stages,
    required String sessionId,
    required String contextKey,
    required String model,
    required AppLanguage language,
    Future<void>? abortTrigger,
  }) async* {
    await for (final AiRunEvent event in _orchestrator.stream(
      runId: runId,
      stages: stages,
      sessionId: sessionId,
      contextKey: contextKey,
      model: model,
      abortTrigger: abortTrigger,
    )) {
      switch (event.type) {
        case AiRunEventType.runStarted:
          yield BoardGameAiStreamEvent(status: 'started', runEvent: event);
        case AiRunEventType.stageStarted:
          yield BoardGameAiStreamEvent(
            status: _uiStageStatus(event.stageId),
            runEvent: event,
          );
        case AiRunEventType.stageCompleted:
          final AiStageResult? result = event.stageResult;
          if (result != null) {
            yield BoardGameAiStreamEvent(
              status: '${event.stageId}:${result.status.name}',
              runEvent: event,
            );
          } else {
            yield BoardGameAiStreamEvent(runEvent: event);
          }
        case AiRunEventType.completed:
          if (event.runResult != null) {
            await _recordTelemetry(event.runResult!);
          }
          final BoardGameAiAnswer? answer = event.answer;
          if (answer == null) {
            yield BoardGameAiStreamEvent(
              status: 'incomplete',
              isDone: true,
              isFailure: true,
              errorMessage: 'Run completed without a validated answer.',
              runEvent: event,
              runResult: event.runResult,
            );
            continue;
          }
          yield BoardGameAiStreamEvent(
            delta: answer.text,
            answer: answer,
            citations: answer.citations,
            isDone: true,
            runEvent: event,
            runResult: event.runResult,
          );
        case AiRunEventType.failed:
        case AiRunEventType.incomplete:
        case AiRunEventType.cancelled:
          if (event.runResult != null) {
            await _recordTelemetry(event.runResult!);
          }
          final AiStageResult? stageResult = event.stageResult;
          final bool isBenignInsufficient =
              event.type == AiRunEventType.incomplete &&
              (stageResult?.status == AiStageStatus.insufficient ||
                  stageResult?.status == AiStageStatus.skipped) &&
              (event.errorCode == null || event.errorCode!.trim().isEmpty) &&
              (event.errorMessage == null ||
                  event.errorMessage!.trim().isEmpty);
          if (isBenignInsufficient) {
            final BoardGameAiAnswer answer = _unknownAnswer(language);
            yield BoardGameAiStreamEvent(
              delta: answer.text,
              answer: answer,
              status: 'insufficient',
              isDone: true,
              runEvent: event,
            );
            continue;
          }
          yield BoardGameAiStreamEvent(
            status: event.type.name,
            isDone: true,
            isFailure: event.type != AiRunEventType.cancelled,
            errorMessage: event.errorMessage,
            runEvent: event,
            runResult: event.runResult,
          );
        case AiRunEventType.status:
        case AiRunEventType.textDelta:
        case AiRunEventType.citationAdded:
        case AiRunEventType.toolStarted:
        case AiRunEventType.toolCompleted:
        case AiRunEventType.outputItem:
        case AiRunEventType.retry:
        case AiRunEventType.responseStreamStarted:
        case AiRunEventType.responseStreamFailed:
        case AiRunEventType.resumeStarted:
        case AiRunEventType.resumeCompleted:
          final bool isAnswerStage =
              event.stageId == 'answering' ||
              event.stageId == 'general' ||
              event.stageId == 'fallback';
          yield BoardGameAiStreamEvent(
            // Stage text is a private candidate until that stage is validated.
            // Do not leak rule-search or web-search prose into the final chat
            // message; only the completed event below commits answer.text.
            delta: isAnswerStage && event.type == AiRunEventType.textDelta
                ? event.delta
                : '',
            status: event.status,
            citations: event.citation == null
                ? const <RuleCitation>[]
                : <RuleCitation>[event.citation!],
            runEvent: event,
          );
      }
    }
  }

  String? _uiStageStatus(String? stageId) => switch (stageId) {
    'official' => 'official',
    'community' => 'community',
    'web' => 'web_search',
    'general' || 'fallback' => 'answering',
    _ => stageId,
  };

  Stream<AiStageExecutionEvent> _streamDocumentStageEvents({
    required _WorkflowContext context,
    required List<RuleDocument> documents,
    required AnswerSource source,
    required AiKnowledgeScope scope,
    required AppLanguage language,
    required GameInfo game,
    Future<void>? abortTrigger,
  }) async* {
    final _PreparedDocuments prepared = await _prepareDocuments(
      context,
      documents,
    );
    if (prepared.inputs.isEmpty) {
      yield AiStageExecutionEvent.result(
        AiStageResult(
          stageId: scope.code,
          scope: scope,
          status: AiStageStatus.skipped,
          inspectedSources: prepared.documents
              .map((RuleDocument document) => document.toCitation())
              .toList(growable: false),
        ),
      );
      return;
    }
    yield* _streamResponseStageEvents(
      context: context,
      scope: scope,
      request: _documentRequest(
        context,
        prepared.inputs,
        documents: prepared.documents,
        language: language,
        game: game,
        source: source,
      ),
      abortTrigger: abortTrigger,
      buildResult: (_CollectedStream stream) {
        if (stream.terminalType != ResponsesStreamEventType.completed) {
          return AiStageResult(
            stageId: scope.code,
            scope: scope,
            status: _stageStatusForTerminal(stream.terminalType),
            bufferedText: stream.text,
            inspectedSources: prepared.documents
                .map((RuleDocument document) => document.toCitation())
                .toList(growable: false),
            responseId: stream.response?.id,
            model: stream.response?.model,
            usage: stream.response?.usage,
            terminalEventType: stream.terminalEventType,
            rawEventCount: stream.rawEventCount,
            outputItemCount: stream.outputItemCount,
            requestCount: 1,
            errorCode: stream.errorCode,
            errorMessage: stream.errorMessage,
          );
        }
        final _ParsedAnswer parsed = _parseStructured(
          stream.text,
          prepared.documents,
          source,
        );
        return AiStageResult(
          stageId: scope.code,
          scope: scope,
          status: parsed.answer == null
              ? AiStageStatus.insufficient
              : AiStageStatus.answered,
          answer: parsed.answer,
          bufferedText: stream.text,
          inspectedSources: prepared.documents
              .map((RuleDocument document) => document.toCitation())
              .toList(growable: false),
          responseId: stream.response?.id,
          model: stream.response?.model,
          usage: stream.response?.usage,
          terminalEventType: stream.terminalEventType,
          rawEventCount: stream.rawEventCount,
          outputItemCount: stream.outputItemCount,
          requestCount: 1,
        );
      },
    );
  }

  Stream<AiStageExecutionEvent> _streamWebStageEvents({
    required _WorkflowContext context,
    required AiKnowledgeScope scope,
    required AppLanguage language,
    required GameInfo game,
    Future<void>? abortTrigger,
  }) async* {
    yield* _streamResponseStageEvents(
      context: context,
      scope: scope,
      request: _webRequest(context, language: language, game: game),
      abortTrigger: abortTrigger,
      buildResult: (_CollectedStream stream) {
        if (stream.terminalType != ResponsesStreamEventType.completed) {
          return _stageResultFromStream(
            scope: scope,
            stream: stream,
            status: _stageStatusForTerminal(stream.terminalType),
          );
        }
        final List<ResponsesWebSearchCitation> citations = _validWebCitations(
          <ResponsesWebSearchCitation>[
            ...stream.webCitations,
            ...?stream.response?.webSearchCitations,
          ],
        );
        final String answerText = stream.text.trim();
        if (answerText.isEmpty || citations.isEmpty) {
          return _stageResultFromStream(
            scope: scope,
            stream: stream,
            status: AiStageStatus.insufficient,
          );
        }
        return _stageResultFromStream(
          scope: scope,
          stream: stream,
          status: AiStageStatus.answered,
          answer: BoardGameAiAnswer(
            text: answerText,
            source: AnswerSource.web,
            citations: citations.map(_webCitation).toList(growable: false),
          ),
        );
      },
    );
  }

  Stream<AiStageExecutionEvent> _streamKnowledgeStageEvents({
    required _WorkflowContext context,
    required AiKnowledgeScope scope,
    required AppLanguage language,
    required GameInfo game,
    required bool useGlobalMode,
    Future<void>? abortTrigger,
  }) async* {
    yield* _streamResponseStageEvents(
      context: context,
      scope: scope,
      request: _knowledgeRequest(
        context,
        language: language,
        game: game,
        useGlobalMode: useGlobalMode,
      ),
      abortTrigger: abortTrigger,
      buildResult: (_CollectedStream stream) {
        final String text = stream.text.trim();
        return _stageResultFromStream(
          scope: scope,
          stream: stream,
          status: stream.terminalType == ResponsesStreamEventType.completed
              ? (text.isEmpty
                    ? AiStageStatus.insufficient
                    : AiStageStatus.answered)
              : _stageStatusForTerminal(stream.terminalType),
          answer:
              stream.terminalType == ResponsesStreamEventType.completed &&
                  text.isNotEmpty
              ? BoardGameAiAnswer(
                  text: text,
                  source: AnswerSource.modelKnowledge,
                )
              : null,
        );
      },
    );
  }

  Stream<AiStageExecutionEvent> _streamGeneralStageEvents({
    required _WorkflowContext context,
    required AiKnowledgeScope scope,
    required AppLanguage language,
    required GameInfo game,
    Future<void>? abortTrigger,
  }) async* {
    yield* _streamResponseStageEvents(
      context: context,
      scope: scope,
      request: _generalConversationRequest(
        context,
        language: language,
        game: game,
      ),
      abortTrigger: abortTrigger,
      buildResult: (_CollectedStream stream) {
        final String text = stream.text.trim();
        return _stageResultFromStream(
          scope: scope,
          stream: stream,
          status: stream.terminalType == ResponsesStreamEventType.completed
              ? (text.isEmpty
                    ? AiStageStatus.insufficient
                    : AiStageStatus.answered)
              : _stageStatusForTerminal(stream.terminalType),
          answer:
              stream.terminalType == ResponsesStreamEventType.completed &&
                  text.isNotEmpty
              ? BoardGameAiAnswer(
                  text: text,
                  source: AnswerSource.generalAdvice,
                )
              : null,
        );
      },
    );
  }

  AiStageResult _stageResultFromStream({
    required AiKnowledgeScope scope,
    required _CollectedStream stream,
    required AiStageStatus status,
    BoardGameAiAnswer? answer,
  }) {
    return AiStageResult(
      stageId: scope.code,
      scope: scope,
      status: status,
      answer: answer,
      bufferedText: stream.text,
      citations: answer?.citations ?? const <RuleCitation>[],
      responseId: stream.response?.id,
      model: stream.response?.model,
      usage: stream.response?.usage,
      terminalEventType: stream.terminalEventType,
      rawEventCount: stream.rawEventCount,
      outputItemCount: stream.outputItemCount,
      requestCount: 1,
      errorCode: stream.errorCode,
      errorMessage: stream.errorMessage,
    );
  }

  Stream<AiStageExecutionEvent> _streamResponseStageEvents({
    required _WorkflowContext context,
    required AiKnowledgeScope scope,
    required ResponsesRequest request,
    required _AiStageResultBuilder buildResult,
    Future<void>? abortTrigger,
  }) async* {
    String text = '';
    String retainedText = '';
    ResponsesResponse? response;
    ResponsesStreamEventType? terminalType;
    String? terminalEventType;
    String? errorCode;
    String? errorMessage;
    final List<ResponsesWebSearchCitation> webCitations =
        <ResponsesWebSearchCitation>[];
    final List<ResponsesInputItem> outputItems = <ResponsesInputItem>[];
    final Set<String> outputItemKeys = <String>{};
    int rawEventCount = 0;
    int attempts = 0;
    bool emittedProviderEvent = false;
    int? lastSequence;
    bool resumePending = false;
    String? replayPrefix;
    bool sawTextDelta = false;
    bool sawTextDone = false;
    ResponsesStreamEvent? pendingCompleted;

    while (true) {
      attempts += 1;
      bool attemptHadProviderEvent = false;
      bool retryAttempt = false;
      String attemptText = '';
      replayPrefix = attempts > 1 && retainedText.isNotEmpty
          ? retainedText
          : null;
      sawTextDelta = false;
      sawTextDone = false;
      pendingCompleted = null;
      if (attempts == 1) {
        yield AiStageExecutionEvent(
          type: AiStageExecutionEventType.responseStreamStarted,
          status: 'streaming',
          detail: '正在监听 Responses 事件流',
          attempt: attempts,
          maxAttempts: 3,
          lastSequence: lastSequence,
        );
      }
      try {
        await for (final ResponsesStreamEvent event in _responsesClient.stream(
          request,
          abortTrigger: abortTrigger,
        )) {
          rawEventCount += 1;
          if (event.sequenceNumber != null) {
            lastSequence = event.sequenceNumber;
          }
          if (resumePending) {
            resumePending = false;
            yield AiStageExecutionEvent(
              type: AiStageExecutionEventType.resumeCompleted,
              status: 'resumed',
              detail: lastSequence == null
                  ? '已重新建立事件流，继续监听'
                  : '已重新建立事件流，继续监听 sequence $lastSequence',
              attempt: attempts,
              maxAttempts: 3,
              sequenceNumber: event.sequenceNumber,
              lastSequence: lastSequence,
              replay: false,
              duplicateUserMessagePrevented: true,
            );
          }
          // The adapter emits a synthetic `stream.end` event when the
          // provider closes without a terminal Responses event. It is useful
          // for diagnostics, but it must not suppress the single safe retry
          // reserved for a completely empty transport attempt.
          if (event.rawType != 'stream.end') {
            attemptHadProviderEvent = true;
            emittedProviderEvent = true;
          }
          if (event.response != null) {
            response = event.response;
            await _rememberCompaction(context, event.response!);
          }
          if (event.outputItem != null) {
            final Map<String, dynamic> value = event.outputItem!.value;
            final String key =
                value['id'] is String &&
                    (value['id'] as String).trim().isNotEmpty
                ? 'id:${(value['id'] as String).trim()}'
                : 'json:${jsonEncode(value)}';
            if (outputItemKeys.add(key)) outputItems.add(event.outputItem!);
          }
          final String? safeDelta =
              event.type == ResponsesStreamEventType.textDelta
              ? _replaySafeDelta(
                  delta: event.delta,
                  candidateText: '$attemptText${event.delta}',
                  replayPrefix: replayPrefix,
                  onReplayPrefixConsumed: () => replayPrefix = null,
                )
              : null;
          final AiStageExecutionEvent? execution = _stageExecutionEventFor(
            scope,
            event,
            deltaOverride: safeDelta,
          );
          if (execution != null) yield execution;

          switch (event.type) {
            case ResponsesStreamEventType.textDelta:
              sawTextDelta = true;
              final String candidate = '$attemptText${event.delta}';
              final String? prefix = replayPrefix;
              if (prefix != null &&
                  !prefix.startsWith(candidate) &&
                  !candidate.startsWith(prefix)) {
                // Some providers resume after the last acknowledged token
                // instead of replaying it. Reconstruct the complete
                // candidate so the final answer remains contiguous.
                replayPrefix = null;
                text = '$retainedText$candidate';
              } else if (prefix != null && candidate.startsWith(prefix)) {
                text = candidate;
              } else {
                text += event.delta;
              }
              attemptText += event.delta;
              retainedText = _preferCompleteText(retainedText, text);
            case ResponsesStreamEventType.textDone:
              sawTextDone = true;
              text = _preferCompleteText(text, event.text ?? '');
              if (pendingCompleted != null && terminalType == null) {
                terminalType = ResponsesStreamEventType.completed;
                terminalEventType =
                    pendingCompleted.rawType ?? 'response.completed';
                if (pendingCompleted.response != null) {
                  response = pendingCompleted.response;
                  text = _preferCompleteText(text, response!.text);
                }
                pendingCompleted = null;
              }
            case ResponsesStreamEventType.webSearchCitation:
              final ResponsesWebSearchCitation? citation =
                  event.webSearchCitation;
              if (citation != null &&
                  !webCitations.any(
                    (ResponsesWebSearchCitation item) =>
                        item.url == citation.url,
                  )) {
                webCitations.add(citation);
              }
            case ResponsesStreamEventType.completed:
              if (terminalType == null && sawTextDelta && !sawTextDone) {
                // Responses guarantees output_text.done before the response
                // is considered complete. Keep this event pending so a
                // provider that batches the two events cannot commit early.
                pendingCompleted = event;
              } else if (terminalType == null) {
                terminalType = ResponsesStreamEventType.completed;
                terminalEventType = event.rawType ?? 'response.completed';
                if (event.response != null) {
                  response = event.response;
                  text = _preferCompleteText(text, event.response!.text);
                }
              }
            case ResponsesStreamEventType.incomplete:
              terminalType ??= ResponsesStreamEventType.incomplete;
              terminalEventType ??= event.rawType ?? 'response.incomplete';
              final AiErrorPresentation presentation = _streamErrorPresentation(
                event.errorCode,
                event.errorMessage,
              );
              errorCode ??= event.errorCode ?? presentation.code;
              errorMessage ??= presentation.message;
              retryAttempt = _isRetryableStreamFailure(
                event.errorCode,
                event.errorMessage,
              );
            case ResponsesStreamEventType.failed:
              terminalType ??= ResponsesStreamEventType.failed;
              terminalEventType ??= event.rawType ?? 'response.failed';
              final AiErrorPresentation presentation = _streamErrorPresentation(
                event.errorCode,
                event.errorMessage,
              );
              errorCode ??= event.errorCode ?? presentation.code;
              errorMessage ??= presentation.message;
              retryAttempt = _isRetryableStreamFailure(
                event.errorCode,
                event.errorMessage,
              );
            case ResponsesStreamEventType.error:
              terminalType ??= ResponsesStreamEventType.error;
              terminalEventType ??= event.rawType ?? 'error';
              final AiErrorPresentation presentation = _streamErrorPresentation(
                event.errorCode,
                event.errorMessage,
              );
              errorCode ??= event.errorCode ?? presentation.code;
              errorMessage ??= presentation.message;
              retryAttempt = _isRetryableStreamFailure(
                event.errorCode,
                event.errorMessage,
              );
            case ResponsesStreamEventType.status:
            case ResponsesStreamEventType.outputItemAdded:
            case ResponsesStreamEventType.outputItemDone:
            case ResponsesStreamEventType.contentPartAdded:
            case ResponsesStreamEventType.contentPartDone:
            case ResponsesStreamEventType.fileCitation:
            case ResponsesStreamEventType.toolCallDelta:
            case ResponsesStreamEventType.toolCallDone:
            case ResponsesStreamEventType.unknown:
              break;
          }
        }
        if (pendingCompleted != null && terminalType == null) {
          terminalType = ResponsesStreamEventType.incomplete;
          terminalEventType = 'response.completed';
          errorCode = 'missing_output_text_done';
          errorMessage = '响应流在 output_text.done 到达前结束';
        }
        if (retryAttempt && attempts < 3) {
          yield AiStageExecutionEvent(
            type: AiStageExecutionEventType.responseStreamFailed,
            status: 'timeout',
            detail: errorMessage?.trim().isNotEmpty == true
                ? errorMessage
                : 'response.completed 尚未到达',
            attempt: attempts,
            maxAttempts: 3,
            lastSequence: lastSequence,
            partialOutputRetained: text.trim().isNotEmpty,
          );
          retainedText = _preferCompleteText(retainedText, text);
          replayPrefix = retainedText.isEmpty ? null : retainedText;
          text = '';
          response = null;
          terminalType = null;
          terminalEventType = null;
          errorCode = null;
          errorMessage = null;
          webCitations.clear();
          yield AiStageExecutionEvent(
            type: AiStageExecutionEventType.retry,
            status: 'reconnecting',
            detail: '服务暂时不可用，重新连接中（第 ${attempts + 1} 次尝试）',
            attempt: attempts + 1,
            maxAttempts: 3,
            lastSequence: lastSequence,
          );
          if (await _waitForRetry(attempts, abortTrigger)) {
            terminalType = ResponsesStreamEventType.incomplete;
            terminalEventType = 'response.cancelled';
            errorMessage = 'Request cancelled.';
            break;
          }
          yield AiStageExecutionEvent(
            type: AiStageExecutionEventType.resumeStarted,
            status: 'reconnecting',
            detail: lastSequence == null
                ? '重新连接事件流（第 ${attempts + 1} / 3 次）'
                : '从 sequence $lastSequence 继续监听（第 ${attempts + 1} / 3 次）',
            attempt: attempts + 1,
            maxAttempts: 3,
            lastSequence: lastSequence,
            replay: false,
            duplicateUserMessagePrevented: true,
          );
          resumePending = true;
          continue;
        }
        if (!attemptHadProviderEvent && attempts < 2 && !emittedProviderEvent) {
          yield AiStageExecutionEvent(
            type: AiStageExecutionEventType.responseStreamFailed,
            status: 'timeout',
            detail: '响应流没有返回有效事件，response.completed 尚未到达',
            attempt: attempts,
            maxAttempts: 3,
            lastSequence: lastSequence,
            partialOutputRetained: text.trim().isNotEmpty,
          );
          terminalType = null;
          terminalEventType = null;
          errorCode = null;
          errorMessage = null;
          yield AiStageExecutionEvent(
            type: AiStageExecutionEventType.retry,
            status: 'reconnecting',
            detail: '响应流没有返回有效事件，重新连接中（第 ${attempts + 1} 次尝试）',
            attempt: attempts + 1,
            maxAttempts: 3,
            lastSequence: lastSequence,
          );
          if (await _waitForRetry(attempts, abortTrigger)) {
            terminalType = ResponsesStreamEventType.incomplete;
            terminalEventType = 'response.cancelled';
            errorMessage = 'Request cancelled.';
            break;
          }
          yield AiStageExecutionEvent(
            type: AiStageExecutionEventType.resumeStarted,
            status: 'reconnecting',
            detail: '重新连接事件流（第 ${attempts + 1} / 3 次）',
            attempt: attempts + 1,
            maxAttempts: 3,
            lastSequence: lastSequence,
            replay: false,
            duplicateUserMessagePrevented: true,
          );
          resumePending = true;
          continue;
        }
        terminalType ??= ResponsesStreamEventType.incomplete;
        terminalEventType ??= 'stream.end';
        errorMessage ??= terminalType == ResponsesStreamEventType.incomplete
            ? 'Responses stream ended before response.completed.'
            : null;
        break;
      } catch (error) {
        // The provider may report response.completed and then fail while the
        // HTTP stream is being closed. The completed event is authoritative;
        // never turn that close-time error into a retry of the same answer.
        if (terminalType == ResponsesStreamEventType.completed) {
          break;
        }
        if (attempts < 3 && _isRetryableStageError(error)) {
          yield AiStageExecutionEvent(
            type: AiStageExecutionEventType.responseStreamFailed,
            status: 'timeout',
            detail: _describeStageError(error),
            attempt: attempts,
            maxAttempts: 3,
            lastSequence: lastSequence,
            partialOutputRetained: text.trim().isNotEmpty,
          );
          retainedText = _preferCompleteText(retainedText, text);
          replayPrefix = retainedText.isEmpty ? null : retainedText;
          text = '';
          response = null;
          terminalType = null;
          terminalEventType = null;
          errorCode = null;
          errorMessage = null;
          webCitations.clear();
          yield AiStageExecutionEvent(
            type: AiStageExecutionEventType.retry,
            status: 'reconnecting',
            detail: '连接暂时中断，重新连接中（第 ${attempts + 1} 次尝试）',
            attempt: attempts + 1,
            maxAttempts: 3,
            lastSequence: lastSequence,
          );
          if (await _waitForRetry(attempts, abortTrigger)) {
            terminalType = ResponsesStreamEventType.incomplete;
            terminalEventType = 'response.cancelled';
            errorMessage = 'Request cancelled.';
            break;
          }
          yield AiStageExecutionEvent(
            type: AiStageExecutionEventType.resumeStarted,
            status: 'reconnecting',
            detail: lastSequence == null
                ? '重新连接事件流（第 ${attempts + 1} / 3 次）'
                : '从 sequence $lastSequence 继续监听（第 ${attempts + 1} / 3 次）',
            attempt: attempts + 1,
            maxAttempts: 3,
            lastSequence: lastSequence,
            replay: false,
            duplicateUserMessagePrevented: true,
          );
          resumePending = true;
          continue;
        }
        yield AiStageExecutionEvent(
          type: AiStageExecutionEventType.responseStreamFailed,
          status: 'failed',
          detail: _describeStageError(error),
          attempt: attempts,
          maxAttempts: 3,
          lastSequence: lastSequence,
          partialOutputRetained: text.trim().isNotEmpty,
        );
        terminalType ??= ResponsesStreamEventType.error;
        terminalEventType ??= 'transport.error';
        errorCode ??= _stageErrorCode(error);
        errorMessage ??= _describeStageError(error);
        break;
      }
    }

    // A stream that exits through any error path is incomplete unless an
    // explicit terminal event has already set the value above.
    final ResponsesStreamEventType finalTerminalType =
        terminalType ?? ResponsesStreamEventType.incomplete;
    text = _preferCompleteText(retainedText, text);
    final ResponsesResponse? collectedResponse = response;
    if (collectedResponse != null) {
      for (final ResponsesInputItem item in collectedResponse.outputItems) {
        final Map<String, dynamic> value = item is ResponsesRawInput
            ? item.value
            : item.toJson();
        final String key =
            value['id'] is String && (value['id'] as String).trim().isNotEmpty
            ? 'id:${(value['id'] as String).trim()}'
            : 'json:${jsonEncode(value)}';
        if (outputItemKeys.add(key)) outputItems.add(item);
      }
    }
    if (collectedResponse != null &&
        collectedResponse.outputItems.isEmpty &&
        outputItems.isNotEmpty) {
      response = _copyResponseWithOutputItems(collectedResponse, outputItems);
      await _rememberCompaction(context, response);
    }
    final ResponsesResponse? finalResponse = response;
    if (finalResponse != null) {
      webCitations.addAll(
        finalResponse.webSearchCitations.where(
          (ResponsesWebSearchCitation citation) => !webCitations.any(
            (ResponsesWebSearchCitation item) => item.url == citation.url,
          ),
        ),
      );
    }
    final AiStageResult result = buildResult(
      _CollectedStream(
        terminalType: finalTerminalType,
        text: text,
        response: response,
        webCitations: List<ResponsesWebSearchCitation>.unmodifiable(
          webCitations,
        ),
        terminalEventType: terminalEventType,
        rawEventCount: rawEventCount,
        outputItemCount: outputItems.length,
        errorCode: errorCode,
        errorMessage: errorMessage,
      ),
    );
    yield AiStageExecutionEvent.result(result.copyWith(requestCount: attempts));
  }

  AiStageExecutionEvent? _stageExecutionEventFor(
    AiKnowledgeScope scope,
    ResponsesStreamEvent event, {
    String? deltaOverride,
  }) {
    String? preview(String? value) {
      final String trimmed = value?.trim() ?? '';
      if (trimmed.isEmpty) return null;
      return trimmed.length <= 160 ? trimmed : '${trimmed.substring(0, 157)}…';
    }

    String? outputId(ResponsesRawInput? item) {
      final dynamic value = item?.value['id'];
      return value is String && value.trim().isNotEmpty ? value.trim() : null;
    }

    String? outputType(ResponsesRawInput? item) {
      final dynamic value = item?.value['type'];
      return value is String && value.trim().isNotEmpty ? value.trim() : null;
    }

    String? outputName(ResponsesRawInput? item) {
      final dynamic value = item?.value['name'];
      return value is String && value.trim().isNotEmpty ? value.trim() : null;
    }

    switch (event.type) {
      case ResponsesStreamEventType.status:
        if (event.status == 'web_search') {
          return AiStageExecutionEvent(
            type: AiStageExecutionEventType.toolStarted,
            rawType: event.rawType,
            status: event.status,
            toolName: 'web_search',
            detail: '联网搜索已开始。',
          );
        }
        if (event.status == 'web_search_completed') {
          return AiStageExecutionEvent(
            type: AiStageExecutionEventType.toolCompleted,
            rawType: event.rawType,
            status: event.status,
            toolName: 'web_search',
            detail: '联网搜索已完成，等待模型整理引用。',
          );
        }
        return AiStageExecutionEvent(
          type: AiStageExecutionEventType.status,
          rawType: event.rawType,
          status: event.status,
          detail: event.status == null ? null : 'Responses 状态：${event.status}',
        );
      case ResponsesStreamEventType.textDelta:
        return AiStageExecutionEvent(
          type: AiStageExecutionEventType.textDelta,
          rawType: event.rawType,
          delta: deltaOverride ?? event.delta,
          itemId: event.itemId,
        );
      case ResponsesStreamEventType.textDone:
        return AiStageExecutionEvent(
          type: AiStageExecutionEventType.status,
          rawType: event.rawType,
          status: 'text_done',
          detail: '文本段已接收，等待 response.completed。',
        );
      case ResponsesStreamEventType.outputItemAdded:
        final String? type = outputType(event.outputItem);
        final String? name = outputName(event.outputItem);
        final bool isTool =
            type?.contains('function_call') == true ||
            type?.contains('web_search') == true;
        return AiStageExecutionEvent(
          type: isTool
              ? AiStageExecutionEventType.toolStarted
              : AiStageExecutionEventType.outputItem,
          rawType: event.rawType,
          itemId: event.itemId ?? outputId(event.outputItem),
          outputItemType: type,
          toolName:
              name ??
              (type?.contains('web_search') == true ? 'web_search' : null),
          detail: isTool ? '工具调用已开始。' : '收到输出项：${type ?? 'unknown'}。',
        );
      case ResponsesStreamEventType.outputItemDone:
        final String? type = outputType(event.outputItem);
        final String? name = outputName(event.outputItem);
        final bool isTool =
            type?.contains('function_call') == true ||
            type?.contains('web_search') == true;
        return AiStageExecutionEvent(
          type: isTool
              ? AiStageExecutionEventType.toolCompleted
              : AiStageExecutionEventType.outputItem,
          rawType: event.rawType,
          itemId: event.itemId ?? outputId(event.outputItem),
          outputItemType: type,
          toolName:
              name ??
              (type?.contains('web_search') == true ? 'web_search' : null),
          toolArgumentsPreview: preview(
            event.outputItem?.value['arguments'] as String?,
          ),
          detail: isTool ? '工具调用已完成。' : '输出项已完成。',
        );
      case ResponsesStreamEventType.contentPartAdded:
      case ResponsesStreamEventType.contentPartDone:
        return AiStageExecutionEvent(
          type: AiStageExecutionEventType.status,
          rawType: event.rawType,
          status: event.type == ResponsesStreamEventType.contentPartAdded
              ? 'content_started'
              : 'content_completed',
          detail: '内容片段生命周期已更新。',
        );
      case ResponsesStreamEventType.fileCitation:
        final ResponsesFileCitation? citation = event.fileCitation;
        return citation == null
            ? null
            : AiStageExecutionEvent(
                type: AiStageExecutionEventType.citationAdded,
                rawType: event.rawType,
                citation: RuleCitation(
                  sourceType: 'file',
                  sourceId: citation.fileId,
                  title: citation.filename,
                ),
                detail: '已确认文件引用。',
              );
      case ResponsesStreamEventType.webSearchCitation:
        final ResponsesWebSearchCitation? citation = event.webSearchCitation;
        return citation == null
            ? null
            : AiStageExecutionEvent(
                type: AiStageExecutionEventType.citationAdded,
                rawType: event.rawType,
                citation: _webCitation(citation),
                detail: '已确认网页引用。',
              );
      case ResponsesStreamEventType.toolCallDelta:
        return AiStageExecutionEvent(
          type: AiStageExecutionEventType.status,
          rawType: event.rawType,
          status: 'tool_arguments',
          itemId: event.itemId,
          toolName: event.toolName,
          toolArgumentsPreview: preview(event.delta),
          detail: '正在准备工具参数。',
        );
      case ResponsesStreamEventType.toolCallDone:
        return AiStageExecutionEvent(
          type: AiStageExecutionEventType.toolCompleted,
          rawType: event.rawType,
          itemId: event.itemId,
          toolName: event.toolName,
          toolArgumentsPreview: preview(event.toolArguments),
          detail: '工具参数已确认。',
        );
      case ResponsesStreamEventType.completed:
        return AiStageExecutionEvent(
          type: AiStageExecutionEventType.status,
          rawType: event.rawType,
          status: 'response_completed',
          responseId: event.response?.id,
          usage: event.response?.usage,
          detail: '已收到 response.completed。',
        );
      case ResponsesStreamEventType.incomplete:
      case ResponsesStreamEventType.failed:
      case ResponsesStreamEventType.error:
        return AiStageExecutionEvent(
          type: AiStageExecutionEventType.status,
          rawType: event.rawType,
          status: event.type.name,
          responseId: event.response?.id,
          detail: event.errorMessage == null
              ? null
              : _streamErrorPresentation(
                  event.errorCode,
                  event.errorMessage,
                ).message,
        );
      case ResponsesStreamEventType.unknown:
        return AiStageExecutionEvent(
          type: AiStageExecutionEventType.status,
          rawType: event.rawType,
          status: 'provider_event',
          detail: event.rawType == null ? null : '收到 ${event.rawType}。',
        );
    }
  }

  String _replaySafeDelta({
    required String delta,
    required String candidateText,
    required String? replayPrefix,
    required void Function() onReplayPrefixConsumed,
  }) {
    final String prefix = replayPrefix ?? '';
    if (prefix.isEmpty || delta.isEmpty) return delta;
    if (prefix.startsWith(candidateText)) {
      return '';
    }
    if (candidateText.startsWith(prefix)) {
      onReplayPrefixConsumed();
      return candidateText.substring(prefix.length);
    }
    onReplayPrefixConsumed();
    return delta;
  }

  bool _isRetryableStageError(Object error) {
    return error is AiTransportException || error is TimeoutException;
  }

  bool _isRetryableStreamFailure(String? code, String? message) {
    final String value = <String?>[
      code,
      message,
    ].whereType<String>().join(' ').toLowerCase();
    if (value.isEmpty) return false;
    return RegExp(
          r'(^|[^0-9])(?:408|425|429|500|502|503|504)([^0-9]|$)',
        ).hasMatch(value) ||
        value.contains('timeout') ||
        value.contains('timed out') ||
        value.contains('temporarily unavailable') ||
        value.contains('service unavailable') ||
        value.contains('overloaded') ||
        value.contains('rate limit') ||
        value.contains('try again later');
  }

  AiStageResult _asAiStageResult({
    required String stageId,
    required AiKnowledgeScope scope,
    required _StageResult result,
  }) {
    return AiStageResult(
      stageId: stageId,
      scope: scope,
      status: result.status,
      answer: result.answer,
      bufferedText: result.bufferedText,
      inspectedSources: result.inspectedSources,
      citations: result.answer?.citations ?? const <RuleCitation>[],
      responseId: result.responseId,
      model: result.model,
      usage: result.usage,
      terminalEventType: result.terminalEventType,
      requestCount: result.requestCount > 0
          ? result.requestCount
          : result.responseId == null
          ? 0
          : 1,
      errorCode: result.errorCode,
      errorMessage: result.errorMessage,
    );
  }

  Future<AiStageResult> _executeGeneralStage({
    required _WorkflowContext context,
    required AppLanguage language,
    required GameInfo game,
  }) async {
    final _StageResult result = await _runGeneralConversationStage(
      context: context,
      language: language,
      game: game,
    );
    return _asAiStageResult(
      stageId: 'general',
      scope: const AiKnowledgeScope.general(),
      result: result,
    );
  }

  String _runId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(this)}';

  Future<_StageResult> _runDocumentStage({
    required _WorkflowContext context,
    required List<RuleDocument> documents,
    required AnswerSource source,
    required AppLanguage language,
    required GameInfo game,
  }) async {
    final _PreparedDocuments prepared = await _prepareDocuments(
      context,
      documents,
    );
    if (prepared.inputs.isEmpty) {
      return const _StageResult(status: AiStageStatus.skipped);
    }
    try {
      final ResponsesResponse response = await _responsesClient.complete(
        _documentRequest(
          context,
          prepared.inputs,
          documents: prepared.documents,
          language: language,
          game: game,
          source: source,
        ),
      );
      await _rememberCompaction(context, response);
      final AiStageStatus? terminalStatus = _responseStatus(response);
      if (terminalStatus != null) {
        return _StageResult(
          status: terminalStatus,
          bufferedText: response.text,
          inspectedSources: prepared.documents
              .map((RuleDocument document) => document.toCitation())
              .toList(growable: false),
          responseId: response.id,
          model: response.model,
          usage: response.usage,
          terminalEventType: _responseTerminalEventType(response),
          requestCount: 1,
          errorMessage: terminalStatus == AiStageStatus.incomplete
              ? 'Responses response was incomplete.'
              : 'Responses response failed.',
        );
      }
      final _ParsedAnswer parsed = _parseStructured(
        response.text,
        prepared.documents,
        source,
      );
      return _StageResult(
        status: parsed.answer == null
            ? AiStageStatus.insufficient
            : AiStageStatus.answered,
        answer: parsed.answer,
        bufferedText: response.text,
        inspectedSources: prepared.documents
            .map((RuleDocument document) => document.toCitation())
            .toList(growable: false),
        responseId: response.id,
        model: response.model,
        usage: response.usage,
        terminalEventType: _responseTerminalEventType(response),
        requestCount: 1,
      );
    } catch (error) {
      return _StageResult(
        status: AiStageStatus.failed,
        inspectedSources: prepared.documents
            .map((RuleDocument document) => document.toCitation())
            .toList(growable: false),
        requestCount: 1,
        errorCode: _stageErrorCode(error),
        errorMessage: _describeStageError(error),
      );
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
      final AiStageStatus? terminalStatus = _responseStatus(response);
      if (terminalStatus != null) {
        return _StageResult(
          status: terminalStatus,
          bufferedText: response.text,
          responseId: response.id,
          model: response.model,
          usage: response.usage,
          terminalEventType: _responseTerminalEventType(response),
          requestCount: 1,
          errorMessage: terminalStatus == AiStageStatus.incomplete
              ? 'Responses response was incomplete.'
              : 'Responses response failed.',
        );
      }
      final List<ResponsesWebSearchCitation> citations = _validWebCitations(
        response.webSearchCitations,
      );
      if (response.text.trim().isEmpty || citations.isEmpty) {
        return _StageResult(
          status: AiStageStatus.insufficient,
          bufferedText: response.text,
          responseId: response.id,
          model: response.model,
          usage: response.usage,
          terminalEventType: _responseTerminalEventType(response),
          requestCount: 1,
        );
      }
      return _StageResult(
        status: AiStageStatus.answered,
        answer: BoardGameAiAnswer(
          text: response.text.trim(),
          source: AnswerSource.web,
          citations: citations.map(_webCitation).toList(growable: false),
        ),
        bufferedText: response.text,
        responseId: response.id,
        model: response.model,
        usage: response.usage,
        terminalEventType: _responseTerminalEventType(response),
        requestCount: 1,
      );
    } catch (error) {
      return _StageResult(
        status: AiStageStatus.failed,
        requestCount: 1,
        errorCode: _stageErrorCode(error),
        errorMessage: _describeStageError(error),
      );
    }
  }

  Future<_StageResult> _runGeneralConversationStage({
    required _WorkflowContext context,
    required AppLanguage language,
    required GameInfo game,
  }) async {
    try {
      final ResponsesResponse response = await _responsesClient.complete(
        _generalConversationRequest(context, language: language, game: game),
      );
      await _rememberCompaction(context, response);
      final AiStageStatus? terminalStatus = _responseStatus(response);
      if (terminalStatus != null) {
        return _StageResult(
          status: terminalStatus,
          bufferedText: response.text,
          responseId: response.id,
          model: response.model,
          usage: response.usage,
          terminalEventType: _responseTerminalEventType(response),
          requestCount: 1,
          errorMessage: terminalStatus == AiStageStatus.incomplete
              ? 'Responses response was incomplete.'
              : 'Responses response failed.',
        );
      }
      final String text = response.text.trim();
      return _StageResult(
        status: text.isEmpty
            ? AiStageStatus.insufficient
            : AiStageStatus.answered,
        answer: text.isEmpty
            ? null
            : BoardGameAiAnswer(text: text, source: AnswerSource.generalAdvice),
        bufferedText: response.text,
        responseId: response.id,
        model: response.model,
        usage: response.usage,
        terminalEventType: _responseTerminalEventType(response),
        requestCount: 1,
      );
    } catch (error) {
      return _StageResult(
        status: AiStageStatus.failed,
        requestCount: 1,
        errorCode: _stageErrorCode(error),
        errorMessage: _describeStageError(error),
      );
    }
  }

  Future<_StageResult> _runKnowledgeStage({
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
      final AiStageStatus? terminalStatus = _responseStatus(response);
      if (terminalStatus != null) {
        return _StageResult(
          status: terminalStatus,
          bufferedText: response.text,
          responseId: response.id,
          model: response.model,
          usage: response.usage,
          terminalEventType: _responseTerminalEventType(response),
          requestCount: 1,
          errorMessage: terminalStatus == AiStageStatus.incomplete
              ? 'Responses response was incomplete.'
              : 'Responses response failed.',
        );
      }
      final String text = response.text.trim();
      return _StageResult(
        status: text.isEmpty
            ? AiStageStatus.insufficient
            : AiStageStatus.answered,
        answer: text.isEmpty
            ? null
            : BoardGameAiAnswer(
                text: text,
                source: AnswerSource.modelKnowledge,
              ),
        bufferedText: response.text,
        responseId: response.id,
        model: response.model,
        usage: response.usage,
        terminalEventType: _responseTerminalEventType(response),
        requestCount: 1,
      );
    } catch (error) {
      return _StageResult(
        status: AiStageStatus.failed,
        requestCount: 1,
        errorCode: _stageErrorCode(error),
        errorMessage: _describeStageError(error),
      );
    }
  }

  ResponsesResponse _copyResponseWithOutputItems(
    ResponsesResponse response,
    List<ResponsesInputItem> outputItems,
  ) {
    return ResponsesResponse(
      text: response.text,
      model: response.model,
      id: response.id,
      status: response.status,
      fileCitations: response.fileCitations,
      webSearchCitations: response.webSearchCitations,
      outputItems: List<ResponsesInputItem>.unmodifiable(outputItems),
      usage: response.usage,
    );
  }

  String _preferCompleteText(String current, String completed) {
    if (completed.isEmpty) return current;
    if (current.isEmpty || completed.startsWith(current)) return completed;
    return completed.length >= current.length ? completed : current;
  }

  AiStageStatus? _responseStatus(ResponsesResponse response) {
    return switch (response.status?.trim().toLowerCase()) {
      'failed' => AiStageStatus.failed,
      'incomplete' => AiStageStatus.incomplete,
      'cancelled' || 'canceled' => AiStageStatus.cancelled,
      _ => null,
    };
  }

  String _responseTerminalEventType(ResponsesResponse response) {
    final String status = response.status?.trim().toLowerCase() ?? '';
    return switch (status) {
      'failed' => 'response.failed',
      'incomplete' => 'response.incomplete',
      'cancelled' || 'canceled' => 'response.cancelled',
      _ => 'response.completed',
    };
  }

  AiStageStatus _stageStatusForTerminal(ResponsesStreamEventType type) {
    return switch (type) {
      ResponsesStreamEventType.incomplete => AiStageStatus.incomplete,
      ResponsesStreamEventType.failed ||
      ResponsesStreamEventType.error => AiStageStatus.failed,
      ResponsesStreamEventType.completed => AiStageStatus.answered,
      _ => AiStageStatus.incomplete,
    };
  }

  String _describeStageError(Object error) {
    return AiErrorPresentation.from(error).message;
  }

  AiErrorPresentation _streamErrorPresentation(String? code, String? message) {
    final String value = <String?>[
      code,
      message,
    ].whereType<String>().join(' ').trim();
    return AiErrorPresentation.from(value.isEmpty ? 'provider error' : value);
  }

  String? _stageErrorCode(Object error) => AiErrorPresentation.from(error).code;

  Future<bool> _waitForRetry(int attempt, Future<void>? abortTrigger) async {
    final Duration delay = Duration(
      milliseconds: (250 * (1 << (attempt - 1))).clamp(250, 2000).toInt(),
    );
    if (abortTrigger == null) {
      await Future<void>.delayed(delay);
      return false;
    }
    bool cancelled = false;
    await Future.any<void>(<Future<void>>[
      Future<void>.delayed(delay),
      abortTrigger.then((_) => cancelled = true),
    ]);
    return cancelled;
  }

  ResponsesRequest _documentRequest(
    _WorkflowContext context,
    List<ResponsesInputItem> files, {
    required List<RuleDocument> documents,
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
      sourceIds: documents
          .map((RuleDocument document) => document.id)
          .where((String id) => id.trim().isNotEmpty)
          .toList(growable: false),
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
      structuredOutput: _documentStructuredOutput(
        documents
            .map((RuleDocument document) => document.id)
            .toList(growable: false),
      ),
      reasoningEffort: context.config.reasoningEffort.requestValue,
      serviceTier: context.config.responseSpeed.serviceTier,
      contextManagement: _contextManagementFor(context.config),
      store: false,
    );
  }

  ResponsesStructuredOutput _documentStructuredOutput(List<String> sourceIds) =>
      ResponsesStructuredOutput.jsonSchema(
        name: 'rule_answer',
        description: 'A source-grounded answer from the declared rule files.',
        schema: <String, dynamic>{
          'type': 'object',
          'additionalProperties': false,
          'properties': <String, dynamic>{
            'status': <String, dynamic>{
              'type': 'string',
              'enum': <String>['answered', 'insufficient'],
            },
            'answer': <String, dynamic>{'type': 'string'},
            'sourceIds': <String, dynamic>{
              'type': 'array',
              'items': <String, dynamic>{
                'type': 'string',
                if (sourceIds.isNotEmpty) 'enum': sourceIds,
              },
            },
          },
          'required': <String>['status', 'answer', 'sourceIds'],
        },
      );

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
    store: false,
  );

  ResponsesRequest _generalConversationRequest(
    _WorkflowContext context, {
    required AppLanguage language,
    required GameInfo game,
  }) => ResponsesRequest(
    endpoint: _endpoint(context.config),
    instructions: _promptBuilder.buildGeneralConversationSystemPrompt(
      language: language,
      game: game,
    ),
    input: context.conversation,
    maxOutputTokens: 1200,
    reasoningEffort: context.config.reasoningEffort.requestValue,
    serviceTier: context.config.responseSpeed.serviceTier,
    contextManagement: _contextManagementFor(context.config),
    store: false,
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
    store: false,
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
    required bool useCurrentGameKnowledge,
  }) {
    return List<ResponsesInputItem>.unmodifiable(
      _compactionInputsByContext[_contextKey(
            config: config,
            game: game,
            useGlobalMode: useGlobalMode,
            useCurrentGameKnowledge: useCurrentGameKnowledge,
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
    // A response may contain more than one compaction item. The last item is
    // the newest provider snapshot; sending older opaque snapshots as well
    // can reintroduce stale context or exceed the provider's input contract.
    _compactionInputsByContext[context.contextKey] =
        List<ResponsesInputItem>.unmodifiable(<ResponsesInputItem>[
          compactionItems.last,
        ]);
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
    required bool useCurrentGameKnowledge,
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
              config.chatPath.trim(),
              config.providerPreset.name,
              config.reasoningEffort.name,
              config.responseSpeed.name,
              'current-game-knowledge:$useCurrentGameKnowledge',
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

  Future<void> _activateCompactionContext({
    required String contextKey,
    required GameInfo game,
    required bool useGlobalMode,
  }) async {
    final String scopeKey = useGlobalMode ? 'global' : 'game:${game.slug}';
    final String? previous = _activeCompactionContextByScope[scopeKey];
    if (previous == contextKey &&
        !_compactionInputsByContext.keys.any(
          (String key) => key.startsWith('$scopeKey|') && key != contextKey,
        )) {
      return;
    }
    _activeCompactionContextByScope[scopeKey] = contextKey;

    final bool removed = _compactionInputsByContext.keys
        .where(
          (String key) => key.startsWith('$scopeKey|') && key != contextKey,
        )
        .toList(growable: false)
        .map((String key) => _compactionInputsByContext.remove(key))
        .any((List<ResponsesInputItem>? value) => value != null);
    if (!removed) return;
    try {
      await _compactionStore.save(_compactionInputsByContext);
    } catch (_) {
      // The active request remains usable if cleanup persistence is unavailable.
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
      final dynamic rawSourceIds = decoded['sourceIds'];
      if (rawSourceIds is! List) return const _ParsedAnswer();
      if (rawSourceIds.isEmpty ||
          rawSourceIds.any(
            (dynamic value) => value is! String || value.trim().isEmpty,
          )) {
        return const _ParsedAnswer();
      }
      final List<String> ids = rawSourceIds
          .cast<String>()
          .map((String value) => value.trim())
          .where((String value) => value.isNotEmpty)
          .toSet()
          .toList(growable: false);
      if (ids.isEmpty) return const _ParsedAnswer();
      final Set<String> declaredIds = documents
          .map((RuleDocument document) => document.id.trim())
          .where((String id) => id.isNotEmpty)
          .toSet();
      // Do not silently discard an invented ID while accepting the rest. A
      // structured answer is source-grounded only when every claimed source
      // belongs to the exact document set sent in this stage.
      if (ids.any((String id) => !declaredIds.contains(id))) {
        return const _ParsedAnswer();
      }
      final List<RuleCitation> citations = documents
          .where((document) => ids.contains(document.id.trim()))
          .map((document) => document.toCitation())
          .toList(growable: false);
      if (citations.length != ids.length) return const _ParsedAnswer();
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
            derivedFrom: resource?.derivedFrom ?? const <String>[],
            version: resource?.edition,
            url: resource?.sourceUrl,
          );
        })
        .toList(growable: false);
  }

  /// Restrict a stage to documents with matching provenance.
  ///
  /// Manifests distinguish official, community, and locally derived material.
  /// Local translations/extractions are treated as official-stage inputs by
  /// default because they are the app's curated rule corpus; a derived
  /// community source remains in the community stage when its provenance says
  /// so. Path checks are a defensive fallback for older manifests that do not
  /// have a useful `sourceClass` value.
  List<RuleDocument> _documentsForSource(
    List<RuleDocument> documents,
    AnswerSource source,
  ) {
    return documents
        .where((RuleDocument document) => _documentSource(document) == source)
        .toList(growable: false);
  }

  AnswerSource _documentSource(RuleDocument document) {
    final String sourceType = document.sourceType
        .trim()
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
    final String path = document.path.replaceAll('\\', '/').toLowerCase();
    final List<String> provenance = <String>[
      ...document.derivedFrom,
      document.title,
      document.path,
    ].map((String value) => value.toLowerCase()).toList(growable: false);

    bool containsCommunity(String value) =>
        value.contains('community') ||
        value.contains('/fan/') ||
        value.contains('/forum/') ||
        value.contains('boardgamegeek') ||
        value.contains('/bgg/');
    bool containsOfficial(String value) =>
        value.contains('official') ||
        value.contains('publisher') ||
        value.contains('rulebook') ||
        value.contains('rules_reference');

    if (sourceType == 'community' ||
        sourceType.startsWith('community_') ||
        sourceType.contains('fan') ||
        sourceType.contains('forum') ||
        containsCommunity(path)) {
      return AnswerSource.community;
    }
    if (sourceType == 'official' ||
        sourceType.startsWith('official_') ||
        containsOfficial(sourceType)) {
      return AnswerSource.official;
    }

    // A local document can be derived from an official or community source.
    // Prefer explicit provenance over the local path name.
    if (sourceType.startsWith('local')) {
      if (provenance.any(containsCommunity)) return AnswerSource.community;
      return AnswerSource.official;
    }
    if (provenance.any(containsCommunity)) return AnswerSource.community;
    if (provenance.any(containsOfficial) || path.contains('/local/')) {
      return AnswerSource.official;
    }

    // Legacy game objects did not expose source classes and treated their
    // knowledge paths as the rulebook. Preserve that safe default while still
    // excluding the explicit community namespace above.
    return AnswerSource.official;
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
    apiKeyHeader: config.apiKeyHeader,
    chatPath: config.chatPath,
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

  RuleCitation _webCitation(ResponsesWebSearchCitation item) => RuleCitation(
    sourceType: 'web',
    sourceId: item.url,
    title: item.title,
    url: item.url,
  );

  List<ResponsesWebSearchCitation> _validWebCitations(
    Iterable<ResponsesWebSearchCitation> citations,
  ) {
    final Map<String, ResponsesWebSearchCitation> unique =
        <String, ResponsesWebSearchCitation>{};
    for (final ResponsesWebSearchCitation citation in citations) {
      final Uri? uri = Uri.tryParse(citation.url.trim());
      if (uri == null ||
          (uri.scheme != 'https' && uri.scheme != 'http') ||
          uri.host.trim().isEmpty) {
        continue;
      }
      unique[citation.url.trim()] = ResponsesWebSearchCitation(
        url: citation.url.trim(),
        title: citation.title.trim().isEmpty
            ? citation.url.trim()
            : citation.title.trim(),
      );
    }
    return unique.values.toList(growable: false);
  }
}

class _WorkflowContext {
  const _WorkflowContext({
    required this.prompt,
    required this.language,
    required this.game,
    required this.config,
    required this.useGlobalMode,
    required this.useCurrentGameKnowledge,
    required this.contextKey,
    required this.session,
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
  final bool useCurrentGameKnowledge;
  final String contextKey;
  final AiSession session;
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
  const _StageResult({
    this.status = AiStageStatus.insufficient,
    this.answer,
    this.bufferedText = '',
    this.inspectedSources = const <RuleCitation>[],
    this.responseId,
    this.model,
    this.usage,
    this.terminalEventType,
    this.requestCount = 0,
    this.errorCode,
    this.errorMessage,
  });

  final AiStageStatus status;
  final BoardGameAiAnswer? answer;
  final String bufferedText;
  final List<RuleCitation> inspectedSources;
  final String? responseId;
  final String? model;
  final AiUsage? usage;
  final String? terminalEventType;
  final int requestCount;
  final String? errorCode;
  final String? errorMessage;
}

class _CollectedStream {
  const _CollectedStream({
    required this.terminalType,
    required this.text,
    required this.response,
    required this.webCitations,
    this.terminalEventType,
    this.rawEventCount = 0,
    this.outputItemCount = 0,
    this.errorCode,
    this.errorMessage,
  });

  final ResponsesStreamEventType terminalType;
  final String text;
  final ResponsesResponse? response;
  final List<ResponsesWebSearchCitation> webCitations;
  final String? terminalEventType;
  final int rawEventCount;
  final int outputItemCount;
  final String? errorCode;
  final String? errorMessage;
}
