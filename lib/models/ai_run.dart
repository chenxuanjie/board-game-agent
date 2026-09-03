import 'package:app_ai_client/app_ai_client.dart';

import 'board_game_ai_answer.dart';
import 'rule_citation.dart';

/// The knowledge boundary a stage is allowed to use.
///
/// Keeping this separate from [AiAnswerMode] makes it possible to change the
/// answer policy without accidentally widening the data a stage can read.
class AiKnowledgeScope {
  const AiKnowledgeScope({
    required this.code,
    required this.allowsGeneralKnowledge,
    this.allowsOfficialDocuments = false,
    this.allowsCommunityDocuments = false,
    this.allowsWebSearch = false,
    this.gameId,
  });

  const AiKnowledgeScope.general()
    : this(code: 'general', allowsGeneralKnowledge: true);

  const AiKnowledgeScope.official({String? gameId})
    : this(
        code: 'official',
        allowsGeneralKnowledge: false,
        allowsOfficialDocuments: true,
        gameId: gameId,
      );

  const AiKnowledgeScope.community({String? gameId})
    : this(
        code: 'community',
        allowsGeneralKnowledge: false,
        allowsCommunityDocuments: true,
        gameId: gameId,
      );

  const AiKnowledgeScope.web({String? gameId})
    : this(
        code: 'web',
        allowsGeneralKnowledge: false,
        allowsWebSearch: true,
        gameId: gameId,
      );

  const AiKnowledgeScope.fallback({String? gameId})
    : this(code: 'fallback', allowsGeneralKnowledge: true, gameId: gameId);

  final String code;
  final bool allowsOfficialDocuments;
  final bool allowsCommunityDocuments;
  final bool allowsWebSearch;
  final bool allowsGeneralKnowledge;
  final String? gameId;

  @override
  bool operator ==(Object other) =>
      other is AiKnowledgeScope && other.code == code && other.gameId == gameId;

  @override
  int get hashCode => Object.hash(code, gameId);
}

/// A client-managed conversation session. The ID is derived from the
/// knowledge scope and provider fingerprint, so switching model/provider
/// cannot accidentally reuse opaque state from another session.
class AiSession {
  const AiSession({
    required this.id,
    required this.contextKey,
    required this.scopeKey,
    required this.model,
  });

  final String id;
  final String contextKey;
  final String scopeKey;
  final String model;
}

enum AiRunEventType {
  runStarted,
  stageStarted,
  status,
  textDelta,
  citationAdded,
  toolStarted,
  toolCompleted,
  outputItem,
  retry,
  responseStreamStarted,
  responseStreamFailed,
  resumeStarted,
  resumeCompleted,
  stageCompleted,
  completed,
  failed,
  incomplete,
  cancelled,
}

/// A safe, provider-neutral event emitted by one running stage.
///
/// This is intentionally smaller than the raw Responses event. It carries
/// enough information for the Run timeline to explain what happened without
/// leaking raw tool payloads, API keys, or hidden model reasoning.
enum AiStageExecutionEventType {
  status,
  textDelta,
  citationAdded,
  toolStarted,
  toolCompleted,
  outputItem,
  retry,
  responseStreamStarted,
  responseStreamFailed,
  resumeStarted,
  resumeCompleted,
  stageCompleted,
}

class AiStageExecutionEvent {
  const AiStageExecutionEvent({
    required this.type,
    this.rawType,
    this.status,
    this.delta = '',
    this.itemId,
    this.outputItemType,
    this.toolName,
    this.toolArgumentsPreview,
    this.detail,
    this.citation,
    this.responseId,
    this.usage,
    this.attempt,
    this.maxAttempts,
    this.sequenceNumber,
    this.lastSequence,
    this.replay,
    this.duplicateUserMessagePrevented = false,
    this.partialOutputRetained = false,
    this.stageResult,
  });

  const AiStageExecutionEvent.result(AiStageResult result)
    : this(type: AiStageExecutionEventType.stageCompleted, stageResult: result);

  final AiStageExecutionEventType type;
  final String? rawType;
  final String? status;
  final String delta;
  final String? itemId;
  final String? outputItemType;
  final String? toolName;
  final String? toolArgumentsPreview;
  final String? detail;
  final RuleCitation? citation;
  final String? responseId;
  final AiUsage? usage;
  final int? attempt;
  final int? maxAttempts;
  final int? sequenceNumber;
  final int? lastSequence;
  final bool? replay;
  final bool duplicateUserMessagePrevented;
  final bool partialOutputRetained;
  final AiStageResult? stageResult;
}

enum AiRunStatus { completed, failed, incomplete, cancelled }

enum AiStageStatus {
  answered,
  insufficient,
  unavailable,
  failed,
  incomplete,
  cancelled,
  skipped,
}

/// A validated result from one independent knowledge or answer stage.
class AiStageResult {
  const AiStageResult({
    required this.stageId,
    required this.scope,
    required this.status,
    this.answer,
    this.bufferedText = '',
    this.citations = const <RuleCitation>[],
    this.responseId,
    this.model,
    this.usage,
    this.startedAt,
    this.completedAt,
    this.terminalEventType,
    this.rawEventCount = 0,
    this.outputItemCount = 0,
    this.requestCount = 0,
    this.contextKey,
    this.errorCode,
    this.errorMessage,
  });

  final String stageId;
  final AiKnowledgeScope scope;
  final AiStageStatus status;
  final BoardGameAiAnswer? answer;
  final String bufferedText;
  final List<RuleCitation> citations;
  final String? responseId;
  final String? model;
  final AiUsage? usage;
  final DateTime? startedAt;
  final DateTime? completedAt;

  /// The provider event that committed or terminated this stage, for example
  /// `response.completed` or `response.failed`.
  final String? terminalEventType;

  /// Number of normalized provider events observed by the adapter.
  final int rawEventCount;

  /// Number of output-item lifecycle events retained for this stage.
  final int outputItemCount;
  final int requestCount;
  final String? contextKey;
  final String? errorCode;
  final String? errorMessage;

  bool get hasAnswer =>
      status == AiStageStatus.answered &&
      answer != null &&
      answer!.text.trim().isNotEmpty;

  AiStageResult copyWith({
    DateTime? startedAt,
    DateTime? completedAt,
    String? contextKey,
    int? requestCount,
  }) {
    return AiStageResult(
      stageId: stageId,
      scope: scope,
      status: status,
      answer: answer,
      bufferedText: bufferedText,
      citations: citations,
      responseId: responseId,
      model: model,
      usage: usage,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      terminalEventType: terminalEventType,
      rawEventCount: rawEventCount,
      outputItemCount: outputItemCount,
      requestCount: requestCount ?? this.requestCount,
      contextKey: contextKey ?? this.contextKey,
      errorCode: errorCode,
      errorMessage: errorMessage,
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
    'stageId': stageId,
    'scope': scope.code,
    'status': status.name,
    if (responseId != null) 'responseId': responseId,
    if (model != null) 'model': model,
    if (usage != null) ...<String, dynamic>{
      'inputTokens': usage!.promptTokens,
      'outputTokens': usage!.completionTokens ?? 0,
      'reasoningTokens': usage!.reasoningTokens ?? 0,
    },
    if (startedAt != null) 'startedAt': startedAt!.toIso8601String(),
    if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
    if (contextKey != null) 'contextKey': contextKey,
    if (terminalEventType != null) 'terminalEventType': terminalEventType,
    'rawEventCount': rawEventCount,
    'outputItemCount': outputItemCount,
    'requestCount': requestCount,
    'citationCount': citations.length,
    if (errorCode != null) 'errorCode': errorCode,
    if (errorMessage != null) 'errorMessage': errorMessage,
  };
}

/// A normalized business event consumed by the UI or an observability sink.
class AiRunEvent {
  const AiRunEvent({
    required this.runId,
    required this.sequence,
    required this.type,
    required this.timestamp,
    this.stageId,
    this.scope,
    this.rawType,
    this.responseId,
    this.sessionId,
    this.contextKey,
    this.model,
    this.usage,
    this.requestCount = 0,
    this.delta = '',
    this.status,
    this.itemId,
    this.outputItemType,
    this.toolArgumentsPreview,
    this.detail,
    this.attempt,
    this.maxAttempts,
    this.sequenceNumber,
    this.lastSequence,
    this.replay,
    this.duplicateUserMessagePrevented = false,
    this.partialOutputRetained = false,
    this.citation,
    this.toolName,
    this.errorCode,
    this.errorMessage,
    this.stageResult,
    this.answer,
    this.runResult,
  });

  final String runId;
  final int sequence;
  final AiRunEventType type;
  final DateTime timestamp;
  final String? stageId;
  final AiKnowledgeScope? scope;
  final String? rawType;
  final String? responseId;
  final String? sessionId;
  final String? contextKey;
  final String? model;
  final AiUsage? usage;
  final int requestCount;
  final String delta;
  final String? status;
  final String? itemId;
  final String? outputItemType;
  final String? toolArgumentsPreview;
  final String? detail;
  final int? attempt;
  final int? maxAttempts;
  final int? sequenceNumber;
  final int? lastSequence;
  final bool? replay;
  final bool duplicateUserMessagePrevented;
  final bool partialOutputRetained;
  final RuleCitation? citation;
  final String? toolName;
  final String? errorCode;
  final String? errorMessage;
  final AiStageResult? stageResult;
  final BoardGameAiAnswer? answer;
  final AiRunResult? runResult;
}

/// The complete outcome of a single orchestrated answer run.
class AiRunResult {
  const AiRunResult({
    required this.runId,
    required this.status,
    this.answer,
    this.stages = const <AiStageResult>[],
    this.events = const <AiRunEvent>[],
    this.responseId,
    this.sessionId,
    this.contextKey,
    this.model,
    this.startedAt,
    this.completedAt,
    this.terminalEventType,
    this.rawEventCount = 0,
    this.outputItemCount = 0,
    this.requestCount = 0,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.reasoningTokens = 0,
    this.citationCount = 0,
    this.errorCode,
    this.errorMessage,
  });

  final String runId;
  final AiRunStatus status;
  final BoardGameAiAnswer? answer;
  final List<AiStageResult> stages;
  final List<AiRunEvent> events;
  final String? responseId;
  final String? sessionId;
  final String? contextKey;
  final String? model;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? terminalEventType;
  final int rawEventCount;
  final int outputItemCount;
  final int requestCount;
  final int inputTokens;
  final int outputTokens;
  final int reasoningTokens;
  final int citationCount;
  final String? errorCode;
  final String? errorMessage;

  String get partialText =>
      answer?.text ??
      stages
          .map((AiStageResult stage) => stage.bufferedText)
          .where((String value) => value.trim().isNotEmpty)
          .join();

  Map<String, dynamic> toMap() => <String, dynamic>{
    'runId': runId,
    'status': status.name,
    if (contextKey != null) 'contextKey': contextKey,
    if (sessionId != null) 'sessionId': sessionId,
    if (model != null) 'model': model,
    if (responseId != null) 'responseId': responseId,
    if (startedAt != null) 'startedAt': startedAt!.toIso8601String(),
    if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
    'requestCount': requestCount,
    if (terminalEventType != null) 'terminalEventType': terminalEventType,
    'rawEventCount': rawEventCount,
    'outputItemCount': outputItemCount,
    'inputTokens': inputTokens,
    'outputTokens': outputTokens,
    'reasoningTokens': reasoningTokens,
    'citationCount': citationCount,
    if (errorCode != null) 'errorCode': errorCode,
    if (errorMessage != null) 'errorMessage': errorMessage,
    'stages': stages.map((AiStageResult stage) => stage.toMap()).toList(),
  };
}
