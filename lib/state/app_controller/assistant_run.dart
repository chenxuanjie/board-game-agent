part of '../app_controller.dart';

extension AppAssistantRunController on AppController {
  void _startRunPresentation(_ChatGenerationState generation) {
    final DateTime startedAt = DateTime.now();
    final String runId = 'client-${startedAt.microsecondsSinceEpoch}';
    generation
      ..runEvents.clear()
      ..runId = runId
      ..runStartedAt = startedAt
      ..runCompletedAt = null
      ..runStatus = null
      ..runSequence = 0
      ..runResult = null
      ..syntheticRun = true;
    _runExpandedByContext[generation.contextKey ?? ''] = true;
    _appendRunEvent(
      generation,
      AiRunEvent(
        runId: runId,
        sequence: generation.runSequence++,
        type: AiRunEventType.runStarted,
        timestamp: startedAt,
        contextKey: _conversationIdForContext(
          useGlobalMode: generation.useGlobalMode,
        ),
        model: _aiApiConfig.model,
      ),
    );
  }

  void _recordRunEvent(_ChatGenerationState generation, AiRunEvent event) {
    if (generation.syntheticRun && event.type == AiRunEventType.runStarted) {
      generation
        ..runEvents.clear()
        ..syntheticRun = false;
    }
    _appendRunEvent(generation, event);
    if (event.runResult != null) {
      generation.runResult = event.runResult;
    }
  }

  void _appendRunEvent(_ChatGenerationState generation, AiRunEvent event) {
    final bool duplicate = generation.runEvents.any(
      (AiRunEvent item) =>
          item.runId == event.runId &&
          item.sequence == event.sequence &&
          item.type == event.type,
    );
    if (duplicate) return;
    generation.runEvents.add(event);
    generation.runId = event.runId;
    if (event.type == AiRunEventType.runStarted) {
      generation.runStartedAt = event.timestamp;
    }
    final AiRunStatus? terminalStatus = _runStatusFromEvent(event);
    if (terminalStatus != null) {
      generation.runStatus = terminalStatus;
      generation.runCompletedAt = event.timestamp;
    }
  }

  void _recordSyntheticProgress(
    _ChatGenerationState generation,
    BoardGameAiStreamEvent event,
  ) {
    if (!generation.syntheticRun) return;
    if (event.status == 'routing') {
      _appendSyntheticStage(generation, 'routing');
    }
    if (event.delta.isNotEmpty || event.answer != null) {
      _appendSyntheticStage(generation, 'answering');
    }
  }

  void _appendSyntheticStage(_ChatGenerationState generation, String stageId) {
    final bool exists = generation.runEvents.any(
      (AiRunEvent event) =>
          event.stageId == stageId &&
          (event.type == AiRunEventType.stageStarted ||
              event.type == AiRunEventType.toolStarted),
    );
    if (exists) return;
    final DateTime timestamp = DateTime.now();
    _appendRunEvent(
      generation,
      AiRunEvent(
        runId: generation.runId!,
        sequence: generation.runSequence++,
        type: AiRunEventType.stageStarted,
        timestamp: timestamp,
        stageId: stageId,
        contextKey: generation.contextKey,
        model: _aiApiConfig.model,
      ),
    );
  }

  void _completeSyntheticAnswerStage(_ChatGenerationState generation) {
    if (!generation.syntheticRun) return;
    _appendSyntheticStage(generation, 'answering');
    final DateTime timestamp = DateTime.now();
    _appendRunEvent(
      generation,
      AiRunEvent(
        runId: generation.runId!,
        sequence: generation.runSequence++,
        type: AiRunEventType.stageCompleted,
        timestamp: timestamp,
        stageId: 'answering',
        contextKey: generation.contextKey,
        model: _aiApiConfig.model,
        stageResult: AiStageResult(
          stageId: 'answering',
          scope: const AiKnowledgeScope.general(),
          status: AiStageStatus.answered,
          model: _aiApiConfig.model,
          startedAt: generation.runStartedAt,
          completedAt: timestamp,
        ),
      ),
    );
  }

  void _finishRunPresentation(
    _ChatGenerationState generation,
    AiRunStatus status,
  ) {
    if (generation.runStatus != null && generation.runCompletedAt != null) {
      _persistRunCheckpoint(generation, generation.runStatus!);
      return;
    }
    if (generation.syntheticRun && status == AiRunStatus.completed) {
      _completeSyntheticAnswerStage(generation);
    }
    final DateTime completedAt = DateTime.now();
    generation
      ..runStatus = status
      ..runCompletedAt = completedAt;
    if (generation.contextKey != null) {
      _runExpandedByContext[generation.contextKey!] =
          status != AiRunStatus.completed;
    }
    if (!_hasTerminalRunEvent(generation)) {
      final AiRunEventType type = switch (status) {
        AiRunStatus.completed => AiRunEventType.completed,
        AiRunStatus.cancelled => AiRunEventType.cancelled,
        AiRunStatus.incomplete => AiRunEventType.incomplete,
        AiRunStatus.failed => AiRunEventType.failed,
      };
      _appendRunEvent(
        generation,
        AiRunEvent(
          runId:
              generation.runId ??
              'client-${completedAt.microsecondsSinceEpoch}',
          sequence: generation.runSequence++,
          type: type,
          timestamp: completedAt,
          contextKey: generation.contextKey,
          model: _aiApiConfig.model,
        ),
      );
    }
    _persistRunCheckpoint(generation, status);
  }

  void _persistRunCheckpoint(
    _ChatGenerationState generation,
    AiRunStatus status,
  ) {
    final String? conversationId = generation.contextKey;
    if (conversationId == null || conversationId.isEmpty) return;
    final AiConversation? conversation = _conversations[conversationId];
    if (conversation == null || generation.runEvents.isEmpty) return;
    final AiRunEvent terminal = generation.runEvents.lastWhere(
      (AiRunEvent event) =>
          event.type == AiRunEventType.completed ||
          event.type == AiRunEventType.failed ||
          event.type == AiRunEventType.incomplete ||
          event.type == AiRunEventType.cancelled,
      orElse: () => generation.runEvents.last,
    );
    final AiRunEvent first = generation.runEvents.first;
    final List<AiRunEvent> checkpointEvents = generation.runEvents
        .where((AiRunEvent event) => event.type != AiRunEventType.textDelta)
        .toList(growable: false);
    final List<AiRunEvent> boundedEvents = checkpointEvents.length <= 240
        ? checkpointEvents
        : checkpointEvents.sublist(checkpointEvents.length - 240);
    final AiRunCheckpoint checkpoint = AiRunCheckpoint(
      runId: generation.runId ?? first.runId,
      status: status,
      events: List<AiRunEvent>.unmodifiable(boundedEvents),
      responseId: terminal.responseId,
      sessionId: terminal.sessionId,
      contextKey: terminal.contextKey ?? conversationId,
      model: terminal.model ?? _aiApiConfig.model,
      startedAt: generation.runStartedAt ?? first.timestamp,
      completedAt: generation.runCompletedAt ?? terminal.timestamp,
      errorCode: terminal.errorCode,
      errorMessage: terminal.errorMessage,
    );
    conversation.lastRun = checkpoint;
    _queueConversationSave(conversationId: conversationId);
  }

  bool _hasTerminalRunEvent(_ChatGenerationState generation) {
    return generation.runEvents.any(
      (AiRunEvent event) =>
          event.type == AiRunEventType.completed ||
          event.type == AiRunEventType.failed ||
          event.type == AiRunEventType.incomplete ||
          event.type == AiRunEventType.cancelled,
    );
  }

  AiRunStatus? _runStatusFromEvent(AiRunEvent? event) {
    return switch (event?.type) {
      AiRunEventType.completed => AiRunStatus.completed,
      AiRunEventType.cancelled => AiRunStatus.cancelled,
      AiRunEventType.incomplete => AiRunStatus.incomplete,
      AiRunEventType.failed => AiRunStatus.failed,
      _ => null,
    };
  }
}
