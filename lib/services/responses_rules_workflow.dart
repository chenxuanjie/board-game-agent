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
              execute: () => _executeGeneralStreamingStage(
                context: context,
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
          execute: () => _streamKnowledgeStageResult(
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
        execute: () => _streamDocumentStageResult(
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
        execute: () => _streamDocumentStageResult(
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
        execute: () => _streamWebStageResult(
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
        execute: () => _streamKnowledgeStageResult(
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
          if (result != null && result.status != AiStageStatus.skipped) {
            yield BoardGameAiStreamEvent(
              status: '${event.stageId}:${result.status.name}',
              runEvent: event,
            );
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
            );
            continue;
          }
          yield BoardGameAiStreamEvent(
            delta: answer.text,
            answer: answer,
            citations: answer.citations,
            isDone: true,
            runEvent: event,
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
          );
        case AiRunEventType.status:
        case AiRunEventType.textDelta:
        case AiRunEventType.citationAdded:
        case AiRunEventType.toolStarted:
        case AiRunEventType.toolCompleted:
        case AiRunEventType.outputItem:
          break;
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

  Future<AiStageResult> _executeGeneralStreamingStage({
    required _WorkflowContext context,
    required AppLanguage language,
    required GameInfo game,
    Future<void>? abortTrigger,
  }) {
    return _streamGeneralStageResult(
      context: context,
      scope: const AiKnowledgeScope.general(),
      language: language,
      game: game,
      abortTrigger: abortTrigger,
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

  Future<AiStageResult> _streamDocumentStageResult({
    required _WorkflowContext context,
    required List<RuleDocument> documents,
    required AnswerSource source,
    required AiKnowledgeScope scope,
    required AppLanguage language,
    required GameInfo game,
    Future<void>? abortTrigger,
  }) async {
    final _PreparedDocuments prepared = await _prepareDocuments(
      context,
      documents,
    );
    if (prepared.inputs.isEmpty) {
      return AiStageResult(
        stageId: scope.code,
        scope: scope,
        status: AiStageStatus.skipped,
      );
    }
    final _CollectedStream collected = await _collectResponseStream(
      context: context,
      request: _documentRequest(
        context,
        prepared.inputs,
        documents: prepared.documents,
        language: language,
        game: game,
        source: source,
      ),
      abortTrigger: abortTrigger,
    );
    if (collected.terminalType != ResponsesStreamEventType.completed) {
      return AiStageResult(
        stageId: scope.code,
        scope: scope,
        status: _stageStatusForTerminal(collected.terminalType),
        bufferedText: collected.text,
        responseId: collected.response?.id,
        model: collected.response?.model,
        usage: collected.response?.usage,
        terminalEventType: collected.terminalEventType,
        rawEventCount: collected.rawEventCount,
        outputItemCount: collected.outputItemCount,
        requestCount: 1,
        errorCode: collected.errorCode,
        errorMessage: collected.errorMessage,
      );
    }
    final _ParsedAnswer parsed = _parseStructured(
      collected.text,
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
      bufferedText: collected.text,
      responseId: collected.response?.id,
      model: collected.response?.model,
      usage: collected.response?.usage,
      terminalEventType: collected.terminalEventType,
      rawEventCount: collected.rawEventCount,
      outputItemCount: collected.outputItemCount,
      requestCount: 1,
    );
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

  Future<AiStageResult> _streamGeneralStageResult({
    required _WorkflowContext context,
    required AiKnowledgeScope scope,
    required AppLanguage language,
    required GameInfo game,
    Future<void>? abortTrigger,
  }) async {
    final _CollectedStream collected = await _collectResponseStream(
      context: context,
      request: _generalConversationRequest(
        context,
        language: language,
        game: game,
      ),
      abortTrigger: abortTrigger,
    );
    if (collected.terminalType != ResponsesStreamEventType.completed) {
      return AiStageResult(
        stageId: scope.code,
        scope: scope,
        status: _stageStatusForTerminal(collected.terminalType),
        bufferedText: collected.text,
        responseId: collected.response?.id,
        model: collected.response?.model,
        usage: collected.response?.usage,
        terminalEventType: collected.terminalEventType,
        rawEventCount: collected.rawEventCount,
        outputItemCount: collected.outputItemCount,
        requestCount: 1,
        errorCode: collected.errorCode,
        errorMessage: collected.errorMessage,
      );
    }
    final String text = collected.text.trim();
    return AiStageResult(
      stageId: scope.code,
      scope: scope,
      status: text.isEmpty
          ? AiStageStatus.insufficient
          : AiStageStatus.answered,
      answer: text.isEmpty
          ? null
          : BoardGameAiAnswer(text: text, source: AnswerSource.generalAdvice),
      bufferedText: collected.text,
      responseId: collected.response?.id,
      model: collected.response?.model,
      usage: collected.response?.usage,
      terminalEventType: collected.terminalEventType,
      rawEventCount: collected.rawEventCount,
      outputItemCount: collected.outputItemCount,
      requestCount: 1,
    );
  }

  Future<AiStageResult> _streamWebStageResult({
    required _WorkflowContext context,
    required AiKnowledgeScope scope,
    required AppLanguage language,
    required GameInfo game,
    Future<void>? abortTrigger,
  }) async {
    final _CollectedStream collected = await _collectResponseStream(
      context: context,
      request: _webRequest(context, language: language, game: game),
      abortTrigger: abortTrigger,
    );
    if (collected.terminalType != ResponsesStreamEventType.completed) {
      return AiStageResult(
        stageId: scope.code,
        scope: scope,
        status: _stageStatusForTerminal(collected.terminalType),
        bufferedText: collected.text,
        responseId: collected.response?.id,
        model: collected.response?.model,
        usage: collected.response?.usage,
        terminalEventType: collected.terminalEventType,
        rawEventCount: collected.rawEventCount,
        outputItemCount: collected.outputItemCount,
        requestCount: 1,
        errorCode: collected.errorCode,
        errorMessage: collected.errorMessage,
      );
    }
    final List<ResponsesWebSearchCitation> responseCitations =
        _validWebCitations(<ResponsesWebSearchCitation>[
          ...collected.webCitations,
          ...?collected.response?.webSearchCitations,
        ]);
    final Map<String, ResponsesWebSearchCitation> uniqueCitations =
        <String, ResponsesWebSearchCitation>{
          for (final ResponsesWebSearchCitation citation in responseCitations)
            citation.url: citation,
        };
    final String answerText = collected.text.trim();
    if (answerText.isEmpty || uniqueCitations.isEmpty) {
      return AiStageResult(
        stageId: scope.code,
        scope: scope,
        status: AiStageStatus.insufficient,
        bufferedText: collected.text,
        responseId: collected.response?.id,
        model: collected.response?.model,
        usage: collected.response?.usage,
        terminalEventType: collected.terminalEventType,
        rawEventCount: collected.rawEventCount,
        outputItemCount: collected.outputItemCount,
        requestCount: 1,
      );
    }
    return AiStageResult(
      stageId: scope.code,
      scope: scope,
      status: AiStageStatus.answered,
      answer: BoardGameAiAnswer(
        text: answerText,
        source: AnswerSource.web,
        citations: uniqueCitations.values
            .map(_webCitation)
            .toList(growable: false),
      ),
      bufferedText: collected.text,
      responseId: collected.response?.id,
      model: collected.response?.model,
      usage: collected.response?.usage,
      terminalEventType: collected.terminalEventType,
      rawEventCount: collected.rawEventCount,
      outputItemCount: collected.outputItemCount,
      requestCount: 1,
    );
  }

  Future<AiStageResult> _streamKnowledgeStageResult({
    required _WorkflowContext context,
    required AiKnowledgeScope scope,
    required AppLanguage language,
    required GameInfo game,
    required bool useGlobalMode,
    Future<void>? abortTrigger,
  }) async {
    final _CollectedStream collected = await _collectResponseStream(
      context: context,
      request: _knowledgeRequest(
        context,
        language: language,
        game: game,
        useGlobalMode: useGlobalMode,
      ),
      abortTrigger: abortTrigger,
    );
    if (collected.terminalType != ResponsesStreamEventType.completed) {
      return AiStageResult(
        stageId: scope.code,
        scope: scope,
        status: _stageStatusForTerminal(collected.terminalType),
        bufferedText: collected.text,
        responseId: collected.response?.id,
        model: collected.response?.model,
        usage: collected.response?.usage,
        terminalEventType: collected.terminalEventType,
        rawEventCount: collected.rawEventCount,
        outputItemCount: collected.outputItemCount,
        requestCount: 1,
        errorCode: collected.errorCode,
        errorMessage: collected.errorMessage,
      );
    }
    final String text = collected.text.trim();
    return AiStageResult(
      stageId: scope.code,
      scope: scope,
      status: text.isEmpty
          ? AiStageStatus.insufficient
          : AiStageStatus.answered,
      answer: text.isEmpty
          ? null
          : BoardGameAiAnswer(text: text, source: AnswerSource.modelKnowledge),
      bufferedText: collected.text,
      responseId: collected.response?.id,
      model: collected.response?.model,
      usage: collected.response?.usage,
      terminalEventType: collected.terminalEventType,
      rawEventCount: collected.rawEventCount,
      outputItemCount: collected.outputItemCount,
      requestCount: 1,
    );
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

  Future<_CollectedStream> _collectResponseStream({
    required _WorkflowContext context,
    required ResponsesRequest request,
    Future<void>? abortTrigger,
  }) async {
    String text = '';
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
    try {
      await for (final ResponsesStreamEvent event in _responsesClient.stream(
        request,
        abortTrigger: abortTrigger,
      )) {
        rawEventCount += 1;
        if (event.response != null) {
          response = event.response;
          await _rememberCompaction(context, event.response!);
        }
        if (event.outputItem != null) {
          final Map<String, dynamic> value = event.outputItem!.value;
          final String key =
              value['id'] is String && (value['id'] as String).trim().isNotEmpty
              ? 'id:${(value['id'] as String).trim()}'
              : 'json:${jsonEncode(value)}';
          if (outputItemKeys.add(key)) outputItems.add(event.outputItem!);
        }
        switch (event.type) {
          case ResponsesStreamEventType.textDelta:
            text += event.delta;
          case ResponsesStreamEventType.textDone:
            text = _preferCompleteText(text, event.text ?? '');
          case ResponsesStreamEventType.webSearchCitation:
            final ResponsesWebSearchCitation? citation =
                event.webSearchCitation;
            if (citation != null &&
                !webCitations.any(
                  (ResponsesWebSearchCitation item) => item.url == citation.url,
                )) {
              webCitations.add(citation);
            }
          case ResponsesStreamEventType.completed:
            if (terminalType == null) {
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
            errorCode ??= event.errorCode;
            errorMessage ??= event.errorMessage;
          case ResponsesStreamEventType.failed:
            terminalType ??= ResponsesStreamEventType.failed;
            terminalEventType ??= event.rawType ?? 'response.failed';
            errorCode ??= event.errorCode;
            errorMessage ??= event.errorMessage;
          case ResponsesStreamEventType.error:
            terminalType ??= ResponsesStreamEventType.error;
            terminalEventType ??= event.rawType ?? 'error';
            errorCode ??= event.errorCode;
            errorMessage ??= event.errorMessage;
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
        // Keep consuming the provider stream after the terminal response
        // event. Responses API completion is the commit boundary, but
        // draining the stream preserves any trailing output-item metadata and
        // lets the transport close cleanly instead of cancelling it early.
      }
      terminalType ??= ResponsesStreamEventType.incomplete;
      terminalEventType ??= 'stream.end';
      errorMessage ??= terminalType == ResponsesStreamEventType.incomplete
          ? 'Responses stream ended before response.completed.'
          : null;
    } catch (error) {
      terminalType ??= ResponsesStreamEventType.error;
      terminalEventType ??= 'transport.error';
      errorCode ??= _stageErrorCode(error);
      errorMessage ??= _describeStageError(error);
    }

    final ResponsesStreamEventType finalTerminalType = terminalType;
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
    return _CollectedStream(
      terminalType: finalTerminalType,
      text: text,
      response: response,
      webCitations: List<ResponsesWebSearchCitation>.unmodifiable(webCitations),
      terminalEventType: terminalEventType,
      rawEventCount: rawEventCount,
      outputItemCount: outputItems.length,
      errorCode: errorCode,
      errorMessage: errorMessage,
    );
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
    final String value = '$error'.trim();
    if (value.isEmpty) return 'AI stage failed.';
    return value;
  }

  String? _stageErrorCode(Object error) => switch (error) {
    AiConfigurationException() => 'configuration_error',
    AiTransportException() => 'transport_error',
    AiProtocolException() => 'protocol_error',
    _ => null,
  };

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
