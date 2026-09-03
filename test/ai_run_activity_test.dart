import 'package:board_game_agent/models/ai_run.dart';
import 'package:board_game_agent/models/app_language.dart';
import 'package:board_game_agent/ui/app_copy.dart';
import 'package:board_game_agent/ui/widgets/ai_run_activity.dart';
import 'package:board_game_agent/theme/palette_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final AppCopy copy = AppCopy(AppLanguage.zhHans);

  AiRunEvent event({
    required int sequence,
    required AiRunEventType type,
    String? stageId,
    AiStageResult? stageResult,
  }) {
    return AiRunEvent(
      runId: 'run-1',
      sequence: sequence,
      type: type,
      timestamp: DateTime(2026, 9, 1, 12, 0, sequence),
      stageId: stageId,
      stageResult: stageResult,
    );
  }

  testWidgets('shows only the current safe activity while running', (
    WidgetTester tester,
  ) async {
    final List<AiRunEvent> events = <AiRunEvent>[
      event(sequence: 0, type: AiRunEventType.runStarted),
      event(
        sequence: 1,
        type: AiRunEventType.stageStarted,
        stageId: 'official',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: AiRunActivity(
            events: events,
            isRunning: true,
            palette: PaletteRegistry.classic,
            copy: copy,
          ),
        ),
      ),
    );

    // The activity is a flat list: the stage appears once, without a global
    // run heading wrapping it.
    expect(find.text('正在查阅官方规则'), findsOneWidget);
    expect(find.text('从当前桌游资料中查找依据'), findsOneWidget);
    expect(find.text('rules_lookup'), findsNothing);
    expect(find.text('Agent Run'), findsNothing);
    expect(find.text('执行摘要'), findsNothing);
    expect(find.text('实时运行'), findsNothing);
  });

  testWidgets('keeps the completed activity as a flat stage list', (
    WidgetTester tester,
  ) async {
    final DateTime startedAt = DateTime(2026, 9, 1, 12, 0);
    final List<AiRunEvent> runningEvents = <AiRunEvent>[
      AiRunEvent(
        runId: 'run-2',
        sequence: 0,
        type: AiRunEventType.runStarted,
        timestamp: startedAt,
      ),
      AiRunEvent(
        runId: 'run-2',
        sequence: 1,
        type: AiRunEventType.stageStarted,
        timestamp: startedAt.add(const Duration(seconds: 1)),
        stageId: 'official',
      ),
    ];
    final List<AiRunEvent> completedEvents = <AiRunEvent>[
      ...runningEvents,
      AiRunEvent(
        runId: 'run-2',
        sequence: 2,
        type: AiRunEventType.stageCompleted,
        timestamp: startedAt.add(const Duration(seconds: 2)),
        stageId: 'official',
        stageResult: AiStageResult(
          stageId: 'official',
          scope: const AiKnowledgeScope.official(gameId: 'game-1'),
          status: AiStageStatus.answered,
        ),
      ),
      AiRunEvent(
        runId: 'run-2',
        sequence: 3,
        type: AiRunEventType.completed,
        timestamp: startedAt.add(const Duration(seconds: 3)),
      ),
    ];

    Widget buildActivity({
      required List<AiRunEvent> events,
      required bool isRunning,
    }) {
      return MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: AiRunActivity(
            events: events,
            isRunning: isRunning,
            palette: PaletteRegistry.classic,
            copy: copy,
          ),
        ),
      );
    }

    await tester.pumpWidget(
      buildActivity(events: runningEvents, isRunning: true),
    );
    expect(find.text('正在查阅官方规则'), findsOneWidget);

    await tester.pumpWidget(
      buildActivity(events: completedEvents, isRunning: false),
    );
    await tester.pump();
    expect(find.text('已查阅官方规则'), findsNWidgets(2));
    expect(find.text('回答已完成'), findsNothing);
    expect(find.text('已完成 · 3s'), findsNothing);
    expect(find.text('查看过程'), findsNothing);
  });

  testWidgets('does not show a later stage before the active stage completes', (
    WidgetTester tester,
  ) async {
    final DateTime startedAt = DateTime(2026, 9, 1, 12, 0);
    final List<AiRunEvent> outOfOrderEvents = <AiRunEvent>[
      AiRunEvent(
        runId: 'run-3',
        sequence: 0,
        type: AiRunEventType.runStarted,
        timestamp: startedAt,
      ),
      AiRunEvent(
        runId: 'run-3',
        sequence: 1,
        type: AiRunEventType.stageStarted,
        timestamp: startedAt.add(const Duration(milliseconds: 1)),
        stageId: 'official',
      ),
      // A stale or batched notification must not make the next stage appear
      // while the current stage is still running.
      AiRunEvent(
        runId: 'run-3',
        sequence: 2,
        type: AiRunEventType.stageStarted,
        timestamp: startedAt.add(const Duration(milliseconds: 2)),
        stageId: 'community',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: AiRunActivity(
            events: outOfOrderEvents,
            isRunning: true,
            palette: PaletteRegistry.classic,
            copy: copy,
          ),
        ),
      ),
    );

    expect(find.text('正在查阅官方规则'), findsOneWidget);
    expect(find.text('正在查阅社区资料'), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: AiRunActivity(
            events: <AiRunEvent>[
              ...outOfOrderEvents,
              AiRunEvent(
                runId: 'run-3',
                sequence: 3,
                type: AiRunEventType.stageCompleted,
                timestamp: startedAt.add(const Duration(milliseconds: 3)),
                stageId: 'official',
                stageResult: AiStageResult(
                  stageId: 'official',
                  scope: const AiKnowledgeScope.official(gameId: 'game-1'),
                  status: AiStageStatus.insufficient,
                ),
              ),
            ],
            isRunning: true,
            palette: PaletteRegistry.classic,
            copy: copy,
          ),
        ),
      ),
    );

    expect(find.text('正在查阅社区资料'), findsOneWidget);
  });

  testWidgets('renders response stream failure and resume as separate cards', (
    WidgetTester tester,
  ) async {
    final List<AiRunEvent> events = <AiRunEvent>[
      event(sequence: 0, type: AiRunEventType.runStarted),
      event(
        sequence: 1,
        type: AiRunEventType.stageStarted,
        stageId: 'official',
      ),
      AiRunEvent(
        runId: 'run-1',
        sequence: 2,
        type: AiRunEventType.responseStreamStarted,
        timestamp: DateTime(2026, 9, 1, 12, 0, 2),
        attempt: 1,
        maxAttempts: 3,
      ),
      AiRunEvent(
        runId: 'run-1',
        sequence: 3,
        type: AiRunEventType.responseStreamFailed,
        timestamp: DateTime(2026, 9, 1, 12, 0, 3),
        status: 'timeout',
        detail: 'response.completed 尚未到达',
        attempt: 1,
        maxAttempts: 3,
        lastSequence: 18,
        partialOutputRetained: true,
      ),
      AiRunEvent(
        runId: 'run-1',
        sequence: 4,
        type: AiRunEventType.resumeStarted,
        timestamp: DateTime(2026, 9, 1, 12, 0, 4),
        attempt: 2,
        maxAttempts: 3,
        lastSequence: 18,
        replay: false,
        duplicateUserMessagePrevented: true,
        detail: '从 sequence 18 继续监听（第 2 / 3 次）',
      ),
      AiRunEvent(
        runId: 'run-1',
        sequence: 5,
        type: AiRunEventType.resumeCompleted,
        timestamp: DateTime(2026, 9, 1, 12, 0, 5),
        attempt: 2,
        maxAttempts: 3,
        lastSequence: 19,
        sequenceNumber: 19,
        replay: false,
        duplicateUserMessagePrevented: true,
        detail: '已重新建立事件流，继续监听 sequence 19',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: AiRunActivity(
            events: events,
            isRunning: true,
            palette: PaletteRegistry.classic,
            copy: copy,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('response stream'), findsOneWidget);
    expect(find.text('resume'), findsOneWidget);
    expect(find.text('response.completed 尚未到达'), findsOneWidget);
    expect(find.text('已重新建立事件流，继续监听 sequence 19'), findsOneWidget);
    expect(find.textContaining('attempt: 1 / 3'), findsOneWidget);
    expect(find.text('resume'), findsOneWidget);
  });
}
