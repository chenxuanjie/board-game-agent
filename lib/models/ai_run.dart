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
  final String? errorCode;
  final String? errorMessage;

  bool get hasAnswer =>
      status == AiStageStatus.answered &&
      answer != null &&
      answer!.text.trim().isNotEmpty;
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
    this.delta = '',
    this.status,
    this.citation,
    this.toolName,
    this.errorCode,
    this.errorMessage,
    this.stageResult,
    this.answer,
  });

  final String runId;
  final int sequence;
  final AiRunEventType type;
  final DateTime timestamp;
  final String? stageId;
  final AiKnowledgeScope? scope;
  final String? rawType;
  final String? responseId;
  final String delta;
  final String? status;
  final RuleCitation? citation;
  final String? toolName;
  final String? errorCode;
  final String? errorMessage;
  final AiStageResult? stageResult;
  final BoardGameAiAnswer? answer;
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
    this.errorCode,
    this.errorMessage,
  });

  final String runId;
  final AiRunStatus status;
  final BoardGameAiAnswer? answer;
  final List<AiStageResult> stages;
  final List<AiRunEvent> events;
  final String? responseId;
  final String? errorCode;
  final String? errorMessage;

  String get partialText =>
      answer?.text ??
      stages
          .map((AiStageResult stage) => stage.bufferedText)
          .where((String value) => value.trim().isNotEmpty)
          .join();
}
