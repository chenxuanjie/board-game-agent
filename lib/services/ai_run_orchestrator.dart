import '../models/ai_run.dart';
import '../models/board_game_ai_answer.dart';
import '../models/rule_citation.dart';

typedef AiStageExecutor = Future<AiStageResult> Function();
typedef AiStageStreamExecutor = Stream<AiStageExecutionEvent> Function();

/// A stage declaration owned by the domain workflow.
class AiStageDefinition {
  const AiStageDefinition({
    required this.stageId,
    required this.scope,
    this.execute,
    this.executeStream,
  });

  final String stageId;
  final AiKnowledgeScope scope;
  final AiStageExecutor? execute;
  final AiStageStreamExecutor? executeStream;
}

/// Runs independent stages and commits only a validated terminal answer.
///
/// A run is the boundary between provider events and the product UI. A stage
/// may still use a future executor, but streaming stages can now forward safe
/// lifecycle events while keeping answer text private until validation passes.
class AiRunOrchestrator {
  const AiRunOrchestrator();

  Stream<AiRunEvent> stream({
    required String runId,
    required List<AiStageDefinition> stages,
    String? sessionId,
    String? contextKey,
    String? model,
    Future<void>? abortTrigger,
  }) async* {
    int sequence = 0;
    final DateTime runStartedAt = DateTime.now();
    bool abortRequested = false;
    abortTrigger?.then((_) => abortRequested = true);

    AiRunEvent next({
      required AiRunEventType type,
      String? stageId,
      AiKnowledgeScope? scope,
      String? status,
      String? responseId,
      String? terminalEventType,
      String? rawType,
      AiStageResult? stageResult,
      BoardGameAiAnswer? answer,
      String delta = '',
      RuleCitation? citation,
      String? itemId,
      String? outputItemType,
      String? toolName,
      String? toolArgumentsPreview,
      String? detail,
      int? attempt,
      String? errorCode,
      String? errorMessage,
      AiRunResult? runResult,
      int? maxAttempts,
      int? sequenceNumber,
      int? lastSequence,
      bool? replay,
      bool duplicateUserMessagePrevented = false,
      bool partialOutputRetained = false,
    }) {
      return AiRunEvent(
        runId: runId,
        sequence: sequence++,
        type: type,
        timestamp: DateTime.now(),
        stageId: stageId,
        scope: scope,
        rawType: rawType ?? terminalEventType ?? stageResult?.terminalEventType,
        status: status,
        responseId: responseId,
        sessionId: sessionId,
        contextKey: contextKey,
        model: stageResult?.model ?? model,
        usage: stageResult?.usage,
        requestCount: stageResult?.requestCount ?? 0,
        delta: delta,
        itemId: itemId,
        outputItemType: outputItemType,
        toolName: toolName,
        toolArgumentsPreview: toolArgumentsPreview,
        detail: detail,
        attempt: attempt,
        maxAttempts: maxAttempts,
        sequenceNumber: sequenceNumber,
        lastSequence: lastSequence,
        replay: replay,
        duplicateUserMessagePrevented: duplicateUserMessagePrevented,
        partialOutputRetained: partialOutputRetained,
        citation: citation,
        stageResult: stageResult,
        answer: answer,
        errorCode: errorCode,
        errorMessage: errorMessage,
        runResult: runResult,
      );
    }

    yield next(type: AiRunEventType.runStarted, status: 'started');
    final List<AiStageResult> results = <AiStageResult>[];

    for (final AiStageDefinition stage in stages) {
      if (abortRequested) {
        final AiRunResult result = _buildRunResult(
          runId: runId,
          status: AiRunStatus.cancelled,
          stages: results,
          sessionId: sessionId,
          contextKey: contextKey,
          model: model,
          startedAt: runStartedAt,
          completedAt: DateTime.now(),
        );
        yield next(
          type: AiRunEventType.cancelled,
          status: 'cancelled',
          runResult: result,
        );
        return;
      }

      yield next(
        type: AiRunEventType.stageStarted,
        stageId: stage.stageId,
        scope: stage.scope,
        status: stage.stageId,
      );

      final DateTime stageStartedAt = DateTime.now();
      AiStageResult? result;
      try {
        final AiStageStreamExecutor? streamExecutor = stage.executeStream;
        if (streamExecutor != null) {
          await for (final AiStageExecutionEvent execution
              in streamExecutor()) {
            if (execution.type == AiStageExecutionEventType.stageCompleted) {
              result = execution.stageResult ?? result;
              continue;
            }
            if (abortRequested) break;
            final AiRunEventType? eventType = _runEventType(execution.type);
            if (eventType == null) continue;
            yield next(
              type: eventType,
              stageId: stage.stageId,
              scope: stage.scope,
              status: execution.status,
              rawType: execution.rawType,
              responseId: execution.responseId,
              delta: execution.delta,
              itemId: execution.itemId,
              outputItemType: execution.outputItemType,
              toolName: execution.toolName,
              toolArgumentsPreview: execution.toolArgumentsPreview,
              detail: execution.detail,
              attempt: execution.attempt,
              citation: execution.citation,
              maxAttempts: execution.maxAttempts,
              sequenceNumber: execution.sequenceNumber,
              lastSequence: execution.lastSequence,
              replay: execution.replay,
              duplicateUserMessagePrevented:
                  execution.duplicateUserMessagePrevented,
              partialOutputRetained: execution.partialOutputRetained,
              errorCode: null,
            );
          }
          result ??= AiStageResult(
            stageId: stage.stageId,
            scope: stage.scope,
            status: abortRequested
                ? AiStageStatus.cancelled
                : AiStageStatus.incomplete,
            errorMessage: abortRequested
                ? null
                : 'Stage stream ended before a validated result.',
          );
        } else if (stage.execute != null) {
          result = await stage.execute!();
        } else {
          result = AiStageResult(
            stageId: stage.stageId,
            scope: stage.scope,
            status: AiStageStatus.failed,
            errorCode: 'missing_executor',
            errorMessage: 'The stage has no executor.',
          );
        }
      } catch (error) {
        result = AiStageResult(
          stageId: stage.stageId,
          scope: stage.scope,
          status: AiStageStatus.failed,
          errorMessage: '$error',
        );
      }
      result = result.copyWith(
        startedAt: result.startedAt ?? stageStartedAt,
        completedAt: result.completedAt ?? DateTime.now(),
        contextKey: result.contextKey ?? contextKey,
      );
      results.add(result);
      yield next(
        type: AiRunEventType.stageCompleted,
        stageId: stage.stageId,
        scope: stage.scope,
        status: result.status.name,
        responseId: result.responseId,
        stageResult: result,
        answer: result.answer,
        errorCode: result.errorCode,
        errorMessage: result.errorMessage,
      );

      if (abortRequested || result.status == AiStageStatus.cancelled) {
        final AiRunResult runResult = _buildRunResult(
          runId: runId,
          status: AiRunStatus.cancelled,
          stages: results,
          responseId: result.responseId,
          terminalEventType: result.terminalEventType,
          sessionId: sessionId,
          contextKey: contextKey,
          model: result.model ?? model,
          startedAt: runStartedAt,
          completedAt: DateTime.now(),
        );
        yield next(
          type: AiRunEventType.cancelled,
          stageId: stage.stageId,
          status: 'cancelled',
          stageResult: result,
          runResult: runResult,
        );
        return;
      }

      if (result.hasAnswer) {
        final AiRunResult runResult = _buildRunResult(
          runId: runId,
          status: AiRunStatus.completed,
          stages: <AiStageResult>[...results],
          responseId: result.responseId,
          terminalEventType: result.terminalEventType,
          sessionId: sessionId,
          contextKey: contextKey,
          model: result.model ?? model,
          startedAt: runStartedAt,
          completedAt: DateTime.now(),
        );
        yield next(
          type: AiRunEventType.completed,
          stageId: stage.stageId,
          scope: stage.scope,
          status: 'completed',
          responseId: result.responseId,
          terminalEventType: result.terminalEventType,
          stageResult: result,
          answer: result.answer,
          runResult: runResult,
        );
        return;
      }
    }

    final AiStageResult? last = results.isEmpty ? null : results.last;
    final bool hasFailure = results.any(
      (AiStageResult result) =>
          result.status == AiStageStatus.failed ||
          result.status == AiStageStatus.unavailable,
    );
    // A later skipped stage must not hide the stage that actually failed or
    // became incomplete. Keep that result on the run terminal event so the UI
    // and diagnostics can retain the provider error and any buffered text.
    AiStageResult? terminalStage;
    for (final AiStageResult result in results.reversed) {
      if (result.status == AiStageStatus.failed ||
          result.status == AiStageStatus.unavailable ||
          result.status == AiStageStatus.incomplete) {
        terminalStage = result;
        break;
      }
    }
    terminalStage ??= last;
    final AiRunEventType terminalType = hasFailure
        ? AiRunEventType.failed
        : AiRunEventType.incomplete;
    final AiRunStatus terminalStatus = hasFailure
        ? AiRunStatus.failed
        : AiRunStatus.incomplete;
    final AiRunResult runResult = _buildRunResult(
      runId: runId,
      status: terminalStatus,
      stages: results,
      responseId: terminalStage?.responseId,
      terminalEventType: terminalStage?.terminalEventType,
      contextKey: contextKey,
      model: terminalStage?.model ?? model,
      startedAt: runStartedAt,
      completedAt: DateTime.now(),
      errorCode: terminalStage?.errorCode,
      errorMessage: terminalStage?.errorMessage,
    );
    yield next(
      type: terminalType,
      status: hasFailure ? 'failed' : 'incomplete',
      stageId: terminalStage?.stageId,
      responseId: terminalStage?.responseId,
      stageResult: terminalStage,
      errorCode: terminalStage?.errorCode,
      errorMessage: terminalStage?.errorMessage,
      runResult: runResult,
    );
  }

  Future<AiRunResult> run({
    required String runId,
    required List<AiStageDefinition> stages,
    String? sessionId,
    String? contextKey,
    String? model,
    Future<void>? abortTrigger,
  }) async {
    final List<AiRunEvent> events = <AiRunEvent>[];
    await for (final AiRunEvent event in stream(
      runId: runId,
      stages: stages,
      sessionId: sessionId,
      contextKey: contextKey,
      model: model,
      abortTrigger: abortTrigger,
    )) {
      events.add(event);
    }
    AiRunEvent? terminal;
    for (final AiRunEvent event in events.reversed) {
      if (event.type == AiRunEventType.completed ||
          event.type == AiRunEventType.failed ||
          event.type == AiRunEventType.incomplete ||
          event.type == AiRunEventType.cancelled) {
        terminal = event;
        break;
      }
    }
    final List<AiStageResult> stageResults = events
        .where(
          (AiRunEvent event) => event.type == AiRunEventType.stageCompleted,
        )
        .map((AiRunEvent event) => event.stageResult)
        .whereType<AiStageResult>()
        .toList(growable: false);
    return _buildRunResult(
      runId: runId,
      status: switch (terminal?.type) {
        AiRunEventType.completed => AiRunStatus.completed,
        AiRunEventType.cancelled => AiRunStatus.cancelled,
        AiRunEventType.incomplete => AiRunStatus.incomplete,
        _ => AiRunStatus.failed,
      },
      stages: stageResults,
      events: events,
      responseId: terminal?.responseId,
      terminalEventType: terminal?.rawType,
      sessionId: sessionId,
      contextKey: contextKey,
      model: terminal?.model ?? model,
      startedAt: events.isEmpty ? null : events.first.timestamp,
      completedAt: events.isEmpty ? null : events.last.timestamp,
      errorCode: terminal?.errorCode,
      errorMessage: terminal?.errorMessage,
    );
  }

  AiRunResult _buildRunResult({
    required String runId,
    required AiRunStatus status,
    required List<AiStageResult> stages,
    String? responseId,
    String? terminalEventType,
    String? sessionId,
    String? contextKey,
    String? model,
    DateTime? startedAt,
    DateTime? completedAt,
    List<AiRunEvent> events = const <AiRunEvent>[],
    String? errorCode,
    String? errorMessage,
  }) {
    int requestCount = 0;
    int inputTokens = 0;
    int outputTokens = 0;
    int reasoningTokens = 0;
    int citationCount = 0;
    int rawEventCount = 0;
    int outputItemCount = 0;
    String? latestTerminalEventType = terminalEventType;
    for (final AiStageResult stage in stages) {
      requestCount += stage.requestCount;
      inputTokens += stage.usage?.promptTokens ?? 0;
      outputTokens += stage.usage?.completionTokens ?? 0;
      reasoningTokens += stage.usage?.reasoningTokens ?? 0;
      citationCount += stage.citations.length;
      rawEventCount += stage.rawEventCount;
      outputItemCount += stage.outputItemCount;
      latestTerminalEventType ??= stage.terminalEventType;
    }
    return AiRunResult(
      runId: runId,
      status: status,
      answer: stages.where((AiStageResult stage) => stage.hasAnswer).isEmpty
          ? null
          : stages.lastWhere((AiStageResult stage) => stage.hasAnswer).answer,
      stages: List<AiStageResult>.unmodifiable(stages),
      events: List<AiRunEvent>.unmodifiable(events),
      responseId: responseId,
      sessionId: sessionId,
      contextKey: contextKey,
      model: model,
      startedAt: startedAt,
      completedAt: completedAt,
      terminalEventType: latestTerminalEventType,
      rawEventCount: rawEventCount,
      outputItemCount: outputItemCount,
      requestCount: requestCount,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      reasoningTokens: reasoningTokens,
      citationCount: citationCount,
      errorCode: errorCode,
      errorMessage: errorMessage,
    );
  }

  AiRunEventType? _runEventType(AiStageExecutionEventType type) {
    return switch (type) {
      AiStageExecutionEventType.status => AiRunEventType.status,
      AiStageExecutionEventType.textDelta => AiRunEventType.textDelta,
      AiStageExecutionEventType.citationAdded => AiRunEventType.citationAdded,
      AiStageExecutionEventType.toolStarted => AiRunEventType.toolStarted,
      AiStageExecutionEventType.toolCompleted => AiRunEventType.toolCompleted,
      AiStageExecutionEventType.outputItem => AiRunEventType.outputItem,
      AiStageExecutionEventType.retry => AiRunEventType.retry,
      AiStageExecutionEventType.responseStreamStarted =>
        AiRunEventType.responseStreamStarted,
      AiStageExecutionEventType.responseStreamFailed =>
        AiRunEventType.responseStreamFailed,
      AiStageExecutionEventType.resumeStarted => AiRunEventType.resumeStarted,
      AiStageExecutionEventType.resumeCompleted =>
        AiRunEventType.resumeCompleted,
      AiStageExecutionEventType.stageCompleted => null,
    };
  }
}
