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
  stageCompleted,
  completed,
  failed,
  incomplete,
  cancelled,
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
      requestCount: requestCount,
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
    'inputTokens': inputTokens,
    'outputTokens': outputTokens,
    'reasoningTokens': reasoningTokens,
    'citationCount': citationCount,
    if (errorCode != null) 'errorCode': errorCode,
    if (errorMessage != null) 'errorMessage': errorMessage,
    'stages': stages.map((AiStageResult stage) => stage.toMap()).toList(),
  };
}
