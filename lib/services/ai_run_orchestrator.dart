import '../models/ai_run.dart';
import '../models/board_game_ai_answer.dart';

typedef AiStageExecutor = Future<AiStageResult> Function();

/// A stage declaration owned by the domain workflow.
class AiStageDefinition {
  const AiStageDefinition({
    required this.stageId,
    required this.scope,
    required this.execute,
  });

  final String stageId;
  final AiKnowledgeScope scope;
  final AiStageExecutor execute;
}

/// Runs independent stages and commits only a validated terminal answer.
///
/// Stage executors are deliberately future-based: they buffer provider output
/// privately and return an [AiStageResult] only after protocol and provenance
/// validation. No stage delta is forwarded to the chat bubble by this class.
class AiRunOrchestrator {
  const AiRunOrchestrator();

  Stream<AiRunEvent> stream({
    required String runId,
    required List<AiStageDefinition> stages,
    Future<void>? abortTrigger,
  }) async* {
    int sequence = 0;
    bool abortRequested = false;
    abortTrigger?.then((_) => abortRequested = true);

    AiRunEvent next({
      required AiRunEventType type,
      String? stageId,
      AiKnowledgeScope? scope,
      String? status,
      String? responseId,
      AiStageResult? stageResult,
      BoardGameAiAnswer? answer,
      String? errorCode,
      String? errorMessage,
    }) {
      return AiRunEvent(
        runId: runId,
        sequence: sequence++,
        type: type,
        timestamp: DateTime.now(),
        stageId: stageId,
        scope: scope,
        status: status,
        responseId: responseId,
        stageResult: stageResult,
        answer: answer,
        errorCode: errorCode,
        errorMessage: errorMessage,
      );
    }

    yield next(type: AiRunEventType.runStarted, status: 'started');
    final List<AiStageResult> results = <AiStageResult>[];

    for (final AiStageDefinition stage in stages) {
      if (abortRequested) {
        yield next(type: AiRunEventType.cancelled, status: 'cancelled');
        return;
      }

      yield next(
        type: AiRunEventType.stageStarted,
        stageId: stage.stageId,
        scope: stage.scope,
        status: stage.stageId,
      );

      AiStageResult result;
      try {
        result = await stage.execute();
      } catch (error) {
        result = AiStageResult(
          stageId: stage.stageId,
          scope: stage.scope,
          status: AiStageStatus.failed,
          errorMessage: '$error',
        );
      }
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
        yield next(
          type: AiRunEventType.cancelled,
          stageId: stage.stageId,
          status: 'cancelled',
          stageResult: result,
        );
        return;
      }

      if (result.hasAnswer) {
        yield next(
          type: AiRunEventType.completed,
          stageId: stage.stageId,
          scope: stage.scope,
          status: 'completed',
          responseId: result.responseId,
          stageResult: result,
          answer: result.answer,
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
    yield next(
      type: terminalType,
      status: hasFailure ? 'failed' : 'incomplete',
      stageId: terminalStage?.stageId,
      responseId: terminalStage?.responseId,
      stageResult: terminalStage,
      errorCode: terminalStage?.errorCode,
      errorMessage: terminalStage?.errorMessage,
    );
  }

  Future<AiRunResult> run({
    required String runId,
    required List<AiStageDefinition> stages,
    Future<void>? abortTrigger,
  }) async {
    final List<AiRunEvent> events = <AiRunEvent>[];
    await for (final AiRunEvent event in stream(
      runId: runId,
      stages: stages,
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
        .map((AiRunEvent event) => event.stageResult)
        .whereType<AiStageResult>()
        .toList(growable: false);
    return AiRunResult(
      runId: runId,
      status: switch (terminal?.type) {
        AiRunEventType.completed => AiRunStatus.completed,
        AiRunEventType.cancelled => AiRunStatus.cancelled,
        AiRunEventType.incomplete => AiRunStatus.incomplete,
        _ => AiRunStatus.failed,
      },
      answer: terminal?.answer,
      stages: stageResults,
      events: List<AiRunEvent>.unmodifiable(events),
      responseId: terminal?.responseId,
      errorCode: terminal?.errorCode,
      errorMessage: terminal?.errorMessage,
    );
  }
}
