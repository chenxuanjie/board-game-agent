import 'package:flutter_test/flutter_test.dart';
import 'package:app_ai_client/app_ai_client.dart';

import 'package:board_game_agent/models/ai_run.dart';
import 'package:board_game_agent/models/board_game_ai_answer.dart';
import 'package:board_game_agent/models/answer_source.dart';
import 'package:board_game_agent/services/ai_run_orchestrator.dart';

void main() {
  test(
    'emits an ordered run protocol and commits only a validated answer',
    () async {
      const AiKnowledgeScope official = AiKnowledgeScope.official(
        gameId: 'demo',
      );
      const AiKnowledgeScope community = AiKnowledgeScope.community(
        gameId: 'demo',
      );
      final AiRunOrchestrator orchestrator = const AiRunOrchestrator();

      final List<AiRunEvent> events = await orchestrator
          .stream(
            runId: 'run-1',
            stages: <AiStageDefinition>[
              AiStageDefinition(
                stageId: 'official',
                scope: official,
                execute: () async => const AiStageResult(
                  stageId: 'official',
                  scope: official,
                  status: AiStageStatus.insufficient,
                  bufferedText: '{"status":"insufficient"}',
                ),
              ),
              AiStageDefinition(
                stageId: 'community',
                scope: community,
                execute: () async => AiStageResult(
                  stageId: 'community',
                  scope: community,
                  status: AiStageStatus.answered,
                  responseId: 'resp-community',
                  answer: BoardGameAiAnswer(
                    text: '社区回答',
                    source: AnswerSource.community,
                  ),
                  bufferedText: '{"status":"answered"}',
                ),
              ),
            ],
          )
          .toList();

      expect(events.map((AiRunEvent event) => event.type), <AiRunEventType>[
        AiRunEventType.runStarted,
        AiRunEventType.stageStarted,
        AiRunEventType.stageCompleted,
        AiRunEventType.stageStarted,
        AiRunEventType.stageCompleted,
        AiRunEventType.completed,
      ]);
      expect(
        events.map((AiRunEvent event) => event.sequence),
        orderedEquals(<int>[0, 1, 2, 3, 4, 5]),
      );
      expect(events[2].stageResult?.status, AiStageStatus.insufficient);
      expect(events[4].stageResult?.status, AiStageStatus.answered);
      expect(events[4].responseId, 'resp-community');
      expect(events.last.answer?.text, '社区回答');
    },
  );

  test(
    'does not commit an answer when a stage has text but is not validated',
    () async {
      final List<AiRunEvent> events = await const AiRunOrchestrator()
          .stream(
            runId: 'run-incomplete',
            stages: <AiStageDefinition>[
              AiStageDefinition(
                stageId: 'official',
                scope: const AiKnowledgeScope.official(gameId: 'demo'),
                execute: () async => const AiStageResult(
                  stageId: 'official',
                  scope: AiKnowledgeScope.official(gameId: 'demo'),
                  status: AiStageStatus.incomplete,
                  bufferedText: '已经收到的一段文本',
                  errorCode: 'stream_end',
                ),
              ),
            ],
          )
          .toList();

      expect(events.last.type, AiRunEventType.incomplete);
      expect(events.last.answer, isNull);
      expect(events.last.stageResult?.bufferedText, '已经收到的一段文本');
    },
  );

  test('propagates the terminal response id into the run result', () async {
    final AiRunResult result = await const AiRunOrchestrator().run(
      runId: 'run-response-id',
      stages: <AiStageDefinition>[
        AiStageDefinition(
          stageId: 'general',
          scope: AiKnowledgeScope.general(),
          execute: () async => AiStageResult(
            stageId: 'general',
            scope: AiKnowledgeScope.general(),
            status: AiStageStatus.answered,
            responseId: 'resp-general',
            answer: BoardGameAiAnswer(
              text: '回答',
              source: AnswerSource.generalAdvice,
            ),
          ),
        ),
      ],
    );

    expect(result.status, AiRunStatus.completed);
    expect(result.responseId, 'resp-general');
    expect(result.events.last.responseId, 'resp-general');
  });

  test('serializes run and stage observability fields', () async {
    final DateTime startedAt = DateTime(2026, 8, 28, 10, 0);
    final DateTime completedAt = startedAt.add(const Duration(seconds: 2));
    final AiStageResult stage = AiStageResult(
      stageId: 'general',
      scope: const AiKnowledgeScope.general(),
      status: AiStageStatus.answered,
      answer: BoardGameAiAnswer(text: '回答', source: AnswerSource.generalAdvice),
      responseId: 'resp-observable',
      model: 'model-observable',
      usage: const AiUsage(
        promptTokens: 12,
        completionTokens: 8,
        totalTokens: 20,
        reasoningTokens: 3,
      ),
      startedAt: startedAt,
      completedAt: completedAt,
      terminalEventType: 'response.completed',
      rawEventCount: 3,
      outputItemCount: 1,
      requestCount: 1,
      contextKey: 'global|scope-fingerprint',
    );
    final AiRunResult result = AiRunResult(
      runId: 'run-observable',
      status: AiRunStatus.completed,
      stages: <AiStageResult>[stage],
      contextKey: 'global|scope-fingerprint',
      sessionId: 'session-observable',
      model: 'model-observable',
      startedAt: startedAt,
      completedAt: completedAt,
      requestCount: 1,
      inputTokens: 12,
      outputTokens: 8,
      reasoningTokens: 3,
      citationCount: 0,
    );

    final Map<String, dynamic> map = result.toMap();
    final Map<String, dynamic> stageMap =
        (map['stages'] as List<dynamic>).single as Map<String, dynamic>;
    expect(map['contextKey'], 'global|scope-fingerprint');
    expect(map['sessionId'], 'session-observable');
    expect(map['reasoningTokens'], 3);
    expect(stageMap['contextKey'], 'global|scope-fingerprint');
    expect(stageMap['startedAt'], startedAt.toIso8601String());
    expect(stageMap['completedAt'], completedAt.toIso8601String());
    expect(stageMap['outputTokens'], 8);
    expect(stageMap['reasoningTokens'], 3);
    expect(stageMap['terminalEventType'], 'response.completed');
    expect(stageMap['rawEventCount'], 3);
    expect(stageMap['outputItemCount'], 1);
  });
}
