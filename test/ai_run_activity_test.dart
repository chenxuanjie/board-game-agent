import 'package:board_game_agent/models/ai_run.dart';
import 'package:board_game_agent/models/app_language.dart';
import 'package:board_game_agent/models/rule_citation.dart';
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
    String? detail,
    int? attempt,
    int? maxAttempts,
  }) {
    return AiRunEvent(
      runId: 'run-1',
      sequence: sequence,
      type: type,
      timestamp: DateTime(2026, 9, 1, 12, 0, sequence),
      stageId: stageId,
      stageResult: stageResult,
      detail: detail,
      attempt: attempt,
      maxAttempts: maxAttempts,
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
      event(
        sequence: 2,
        type: AiRunEventType.responseStreamStarted,
        attempt: 1,
        maxAttempts: 3,
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
    expect(find.text('连接过程'), findsNothing);
    expect(find.text('正在重连'), findsNothing);
  });

  testWidgets('does not show a reconnect card for a healthy response stream', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: AiRunActivity(
            events: <AiRunEvent>[
              event(sequence: 0, type: AiRunEventType.runStarted),
              event(
                sequence: 1,
                type: AiRunEventType.responseStreamStarted,
                attempt: 1,
                maxAttempts: 3,
              ),
            ],
            isRunning: true,
            palette: PaletteRegistry.classic,
            copy: copy,
          ),
        ),
      ),
    );

    expect(find.text('连接过程'), findsNothing);
    expect(find.text('正在重连'), findsNothing);
    expect(find.text('resume'), findsNothing);
  });

  testWidgets('ignores a late run failure after response.completed', (
    WidgetTester tester,
  ) async {
    final DateTime startedAt = DateTime(2026, 9, 1, 12, 0);
    final List<AiRunEvent> events = <AiRunEvent>[
      AiRunEvent(
        runId: 'run-late-error',
        sequence: 0,
        type: AiRunEventType.runStarted,
        timestamp: startedAt,
      ),
      AiRunEvent(
        runId: 'run-late-error',
        sequence: 1,
        type: AiRunEventType.stageStarted,
        timestamp: startedAt.add(const Duration(milliseconds: 1)),
        stageId: 'answering',
      ),
      AiRunEvent(
        runId: 'run-late-error',
        sequence: 2,
        type: AiRunEventType.stageCompleted,
        timestamp: startedAt.add(const Duration(milliseconds: 2)),
        stageId: 'answering',
        stageResult: AiStageResult(
          stageId: 'answering',
          scope: const AiKnowledgeScope.general(),
          status: AiStageStatus.answered,
        ),
      ),
      AiRunEvent(
        runId: 'run-late-error',
        sequence: 3,
        type: AiRunEventType.completed,
        timestamp: startedAt.add(const Duration(milliseconds: 3)),
      ),
      // A transport close error delivered after the terminal event must not
      // turn this completed run into a second failure card.
      AiRunEvent(
        runId: 'run-late-error',
        sequence: 4,
        type: AiRunEventType.failed,
        timestamp: startedAt.add(const Duration(milliseconds: 4)),
        errorMessage: 'connection reset after completion',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: AiRunActivity(
            events: events,
            isRunning: false,
            palette: PaletteRegistry.classic,
            copy: copy,
          ),
        ),
      ),
    );

    expect(find.text('回答未完成'), findsNothing);
    expect(find.text('resume 失败'), findsNothing);
  });

  testWidgets('merges a failed reconnect into the streamed stage', (
    WidgetTester tester,
  ) async {
    final DateTime startedAt = DateTime(2026, 9, 1, 12, 0);
    final List<AiRunEvent> events = <AiRunEvent>[
      AiRunEvent(
        runId: 'run-merged-failure',
        sequence: 0,
        type: AiRunEventType.runStarted,
        timestamp: startedAt,
      ),
      AiRunEvent(
        runId: 'run-merged-failure',
        sequence: 1,
        type: AiRunEventType.stageStarted,
        timestamp: startedAt.add(const Duration(milliseconds: 1)),
        stageId: 'answering',
      ),
      AiRunEvent(
        runId: 'run-merged-failure',
        sequence: 2,
        type: AiRunEventType.responseStreamFailed,
        timestamp: startedAt.add(const Duration(milliseconds: 2)),
        detail: '响应尚未完成，连接已中断',
        attempt: 1,
        maxAttempts: 3,
      ),
      AiRunEvent(
        runId: 'run-merged-failure',
        sequence: 3,
        type: AiRunEventType.resumeStarted,
        timestamp: startedAt.add(const Duration(milliseconds: 3)),
        detail: '重新连接事件流（第 2 / 3 次）',
        attempt: 2,
        maxAttempts: 3,
      ),
      AiRunEvent(
        runId: 'run-merged-failure',
        sequence: 4,
        type: AiRunEventType.stageCompleted,
        timestamp: startedAt.add(const Duration(milliseconds: 4)),
        stageId: 'answering',
        stageResult: const AiStageResult(
          stageId: 'answering',
          scope: AiKnowledgeScope.general(),
          status: AiStageStatus.incomplete,
          errorMessage: 'network disconnected',
        ),
      ),
      AiRunEvent(
        runId: 'run-merged-failure',
        sequence: 5,
        type: AiRunEventType.failed,
        timestamp: startedAt.add(const Duration(milliseconds: 5)),
        errorMessage: 'network disconnected',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: AiRunActivity(
            events: events,
            isRunning: false,
            palette: PaletteRegistry.classic,
            copy: copy,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('回答未完成'), findsOneWidget);
    expect(find.text('resume 失败'), findsNothing);
    await tester.tap(find.byType(ExpansionTile).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('第 1 次尝试'), findsOneWidget);
    expect(find.textContaining('第 2 次尝试'), findsOneWidget);
  });

  testWidgets('keeps reconnect details in the latest stage when active is gone', (
    WidgetTester tester,
  ) async {
    final DateTime startedAt = DateTime(2026, 9, 1, 12, 0);
    final List<AiRunEvent> events = <AiRunEvent>[
      AiRunEvent(
        runId: 'run-lost-active',
        sequence: 0,
        type: AiRunEventType.runStarted,
        timestamp: startedAt,
      ),
      AiRunEvent(
        runId: 'run-lost-active',
        sequence: 1,
        type: AiRunEventType.stageStarted,
        timestamp: startedAt.add(const Duration(milliseconds: 1)),
        stageId: 'answering',
      ),
      // This terminal stage snapshot models a rebuild that has lost the
      // renderer's active pointer while the same Run is still reconnecting.
      AiRunEvent(
        runId: 'run-lost-active',
        sequence: 2,
        type: AiRunEventType.stageCompleted,
        timestamp: startedAt.add(const Duration(milliseconds: 2)),
        stageId: 'answering',
        stageResult: const AiStageResult(
          stageId: 'answering',
          scope: AiKnowledgeScope.general(),
          status: AiStageStatus.incomplete,
        ),
      ),
      AiRunEvent(
        runId: 'run-lost-active',
        sequence: 3,
        type: AiRunEventType.resumeStarted,
        timestamp: startedAt.add(const Duration(milliseconds: 3)),
        detail: '重新连接事件流（第 2 / 3 次）',
        attempt: 2,
        maxAttempts: 3,
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

    expect(find.text('resume'), findsNothing);
    expect(find.text('回答未完成'), findsOneWidget);
    expect(find.textContaining('第 2 次尝试'), findsOneWidget);
  });

  testWidgets('folds a temporary connection row into a later stage', (
    WidgetTester tester,
  ) async {
    final DateTime startedAt = DateTime(2026, 9, 1, 12, 0);
    final List<AiRunEvent> events = <AiRunEvent>[
      AiRunEvent(
        runId: 'run-late-stage',
        sequence: 0,
        type: AiRunEventType.responseStreamFailed,
        timestamp: startedAt,
        detail: '网络连接不可用',
        attempt: 1,
        maxAttempts: 3,
      ),
      AiRunEvent(
        runId: 'run-late-stage',
        sequence: 1,
        type: AiRunEventType.stageStarted,
        timestamp: startedAt.add(const Duration(milliseconds: 1)),
        stageId: 'answering',
      ),
      AiRunEvent(
        runId: 'run-late-stage',
        sequence: 2,
        type: AiRunEventType.resumeStarted,
        timestamp: startedAt.add(const Duration(milliseconds: 2)),
        detail: '重新连接事件流（第 2 / 3 次）',
        attempt: 2,
        maxAttempts: 3,
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

    expect(find.text('resume'), findsNothing);
    expect(find.text('正在生成回答'), findsOneWidget);
    expect(find.textContaining('第 1 次尝试'), findsOneWidget);
    expect(find.textContaining('第 2 次尝试'), findsOneWidget);
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
          inspectedSources: const <RuleCitation>[
            RuleCitation(
              sourceType: 'official',
              sourceId: 'rules-book',
              title: '波多黎各规则书',
            ),
          ],
          citations: const <RuleCitation>[
            RuleCitation(
              sourceType: 'official',
              sourceId: 'rules-book',
              title: '波多黎各规则书',
              page: 5,
              section: '贸易阶段',
              quote: '船长阶段开始时，船长选择一种商品。',
            ),
          ],
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
    await tester.pumpAndSettle();
    expect(find.textContaining('用时'), findsOneWidget);
    expect(find.text('已查阅官方规则'), findsNothing);
    expect(find.textContaining('资料：波多黎各规则书'), findsNothing);
    expect(find.text('回答已完成'), findsNothing);
    expect(find.text('已完成 · 3s'), findsNothing);
    expect(find.text('查看过程'), findsNothing);

    await tester.tap(find.textContaining('用时'));
    await tester.pumpAndSettle();
    expect(find.text('已查阅官方规则'), findsOneWidget);
    expect(find.textContaining('资料：波多黎各规则书'), findsOneWidget);
    expect(find.text('章节：贸易阶段'), findsOneWidget);
    expect(find.text('页码：第 5 页'), findsOneWidget);
    expect(find.textContaining('引用：船长阶段开始时'), findsOneWidget);

    await tester.tap(find.textContaining('用时'));
    await tester.pumpAndSettle();
    expect(find.textContaining('资料：波多黎各规则书'), findsNothing);
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

  testWidgets('expands during reconnect and collapses after it succeeds', (
    WidgetTester tester,
  ) async {
    final List<AiRunEvent> reconnectingEvents = <AiRunEvent>[
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
    ];
    final List<AiRunEvent> recoveredEvents = <AiRunEvent>[
      ...reconnectingEvents,
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
            events: reconnectingEvents,
            isRunning: true,
            palette: PaletteRegistry.classic,
            copy: copy,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('正在查阅官方规则'), findsOneWidget);
    expect(find.text('resume'), findsNothing);
    expect(find.textContaining('响应尚未完成，连接已中断'), findsOneWidget);
    expect(find.textContaining('已重新建立事件流，继续监听 sequence 19'), findsNothing);
    expect(find.textContaining('第 1 次尝试'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: AiRunActivity(
            events: recoveredEvents,
            isRunning: true,
            palette: PaletteRegistry.classic,
            copy: copy,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('正在查阅官方规则'), findsOneWidget);
    expect(find.text('resume'), findsNothing);
    expect(find.textContaining('第 1 次尝试'), findsOneWidget);
    // Reconnect details remain inside the same stage while the run is active.
    expect(find.textContaining('已重新建立事件流'), findsOneWidget);
    expect(find.textContaining('已重新建立事件流'), findsOneWidget);
  });

  testWidgets('collapses completed details but keeps them user-expandable', (
    WidgetTester tester,
  ) async {
    final DateTime startedAt = DateTime(2026, 9, 1, 12, 0);
    final AiRunEvent started = AiRunEvent(
      runId: 'run-collapse',
      sequence: 0,
      type: AiRunEventType.stageStarted,
      timestamp: startedAt,
      stageId: 'official',
    );
    final AiRunEvent completed = AiRunEvent(
      runId: 'run-collapse',
      sequence: 1,
      type: AiRunEventType.stageCompleted,
      timestamp: startedAt.add(const Duration(seconds: 1)),
      stageId: 'official',
      stageResult: AiStageResult(
        stageId: 'official',
        scope: const AiKnowledgeScope.official(gameId: 'game-1'),
        status: AiStageStatus.answered,
      ),
    );

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
      buildActivity(events: <AiRunEvent>[started], isRunning: true),
    );
    expect(find.text('从当前桌游资料中查找依据'), findsOneWidget);

    await tester.pumpWidget(
      buildActivity(events: <AiRunEvent>[started, completed], isRunning: true),
    );
    await tester.pumpAndSettle();
    expect(find.text('资料：波多黎各规则书'), findsNothing);

    await tester.tap(find.byType(ExpansionTile).first);
    await tester.pumpAndSettle();
    expect(find.text('资料：波多黎各规则书'), findsNothing);
  });

  testWidgets('failed protocol details stay visible while the run retries', (
    WidgetTester tester,
  ) async {
    final List<AiRunEvent> events = <AiRunEvent>[
      event(sequence: 0, type: AiRunEventType.runStarted),
      AiRunEvent(
        runId: 'run-1',
        sequence: 1,
        type: AiRunEventType.responseStreamFailed,
        timestamp: DateTime(2026, 9, 1, 12, 0, 1),
        detail: 'response.completed 尚未到达',
        attempt: 1,
        maxAttempts: 3,
        lastSequence: 18,
        partialOutputRetained: true,
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
    expect(find.textContaining('第 1 次尝试'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: AiRunActivity(
            events: events,
            isRunning: false,
            palette: PaletteRegistry.classic,
            copy: copy,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('resume'), findsOneWidget);
    expect(find.textContaining('第 1 次尝试'), findsNothing);
    await tester.tap(find.text('resume'));
    await tester.pumpAndSettle();
    expect(find.textContaining('第 1 次尝试'), findsOneWidget);
  });

  testWidgets(
    'terminal completion collapses details even when it arrives with the final answer',
    (WidgetTester tester) async {
      final DateTime startedAt = DateTime(2026, 9, 1, 12, 0);
      final List<AiRunEvent> runningEvents = <AiRunEvent>[
        AiRunEvent(
          runId: 'run-terminal',
          sequence: 0,
          type: AiRunEventType.stageStarted,
          timestamp: startedAt,
          stageId: 'official',
        ),
        AiRunEvent(
          runId: 'run-terminal',
          sequence: 1,
          type: AiRunEventType.responseStreamFailed,
          timestamp: startedAt.add(const Duration(milliseconds: 1)),
          detail: '响应流中断，准备重连',
          attempt: 1,
          maxAttempts: 3,
        ),
        AiRunEvent(
          runId: 'run-terminal',
          sequence: 2,
          type: AiRunEventType.resumeStarted,
          timestamp: startedAt.add(const Duration(milliseconds: 2)),
          detail: '从 sequence 3 继续监听（第 2 / 3 次）',
          attempt: 2,
          maxAttempts: 3,
        ),
      ];
      final List<AiRunEvent> completedEvents = <AiRunEvent>[
        ...runningEvents,
        AiRunEvent(
          runId: 'run-terminal',
          sequence: 3,
          type: AiRunEventType.resumeCompleted,
          timestamp: startedAt.add(const Duration(milliseconds: 3)),
          attempt: 2,
          maxAttempts: 3,
          detail: '已重新建立事件流，继续监听 sequence 4',
        ),
        AiRunEvent(
          runId: 'run-terminal',
          sequence: 4,
          type: AiRunEventType.stageCompleted,
          timestamp: startedAt.add(const Duration(milliseconds: 4)),
          stageId: 'official',
          stageResult: AiStageResult(
            stageId: 'official',
            scope: const AiKnowledgeScope.official(gameId: 'game-1'),
            status: AiStageStatus.answered,
          ),
        ),
        AiRunEvent(
          runId: 'run-terminal',
          sequence: 5,
          type: AiRunEventType.status,
          timestamp: startedAt.add(const Duration(milliseconds: 5)),
          status: 'response_completed',
        ),
        AiRunEvent(
          runId: 'run-terminal',
          sequence: 6,
          type: AiRunEventType.completed,
          timestamp: startedAt.add(const Duration(milliseconds: 6)),
        ),
      ];

      Widget buildActivity(List<AiRunEvent> events, bool isRunning) {
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

      await tester.pumpWidget(buildActivity(runningEvents, true));
      expect(find.textContaining('第 1 次尝试'), findsOneWidget);

      await tester.pumpWidget(buildActivity(completedEvents, false));
      await tester.pumpAndSettle();
      expect(find.textContaining('用时'), findsOneWidget);
      expect(find.text('resume'), findsNothing);
      await tester.tap(find.textContaining('用时'));
      await tester.pumpAndSettle();
      expect(find.text('已查阅官方规则'), findsAtLeastNWidgets(1));
      expect(find.text('resume'), findsNothing);
      expect(find.textContaining('第 1 次尝试'), findsOneWidget);
    },
  );

  testWidgets('shows only citation facts that are present', (
    WidgetTester tester,
  ) async {
    final DateTime startedAt = DateTime(2026, 9, 1, 12, 0);
    final List<AiRunEvent> events = <AiRunEvent>[
      AiRunEvent(
        runId: 'run-facts',
        sequence: 0,
        type: AiRunEventType.stageStarted,
        timestamp: startedAt,
        stageId: 'official',
      ),
      AiRunEvent(
        runId: 'run-facts',
        sequence: 1,
        type: AiRunEventType.stageCompleted,
        timestamp: startedAt.add(const Duration(seconds: 1)),
        stageId: 'official',
        stageResult: const AiStageResult(
          stageId: 'official',
          scope: AiKnowledgeScope.official(gameId: 'game-1'),
          status: AiStageStatus.insufficient,
          inspectedSources: <RuleCitation>[
            RuleCitation(
              sourceType: 'official',
              sourceId: 'rules-book',
              title: '规则书',
            ),
          ],
        ),
      ),
      AiRunEvent(
        runId: 'run-facts',
        sequence: 2,
        type: AiRunEventType.completed,
        timestamp: startedAt.add(const Duration(seconds: 2)),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: AiRunActivity(
            events: events,
            isRunning: false,
            palette: PaletteRegistry.classic,
            copy: copy,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('用时'));
    await tester.pumpAndSettle();

    expect(find.text('资料：规则书'), findsOneWidget);
    expect(find.textContaining('页码：'), findsNothing);
    expect(find.textContaining('章节：'), findsNothing);
    expect(find.textContaining('引用：'), findsNothing);
    expect(find.textContaining('detail:'), findsNothing);
  });
}
