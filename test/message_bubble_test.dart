import 'package:board_game_agent/models/answer_source.dart';
import 'package:board_game_agent/models/chat_message.dart';
import 'package:board_game_agent/models/evidence_chunk.dart';
import 'package:board_game_agent/models/app_language.dart';
import 'package:board_game_agent/theme/palette_registry.dart';
import 'package:board_game_agent/ui/app_copy.dart';
import 'package:board_game_agent/ui/widgets/message_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('assistant bubble renders source, evidence and retry action', (
    WidgetTester tester,
  ) async {
    bool retried = false;
    final ChatMessage message = ChatMessage(
      id: 'failed',
      role: ChatRole.assistant,
      text: '这次回答失败了，请稍后再试。',
      timestamp: DateTime(2026, 8, 18, 12, 30),
      source: AnswerSource.insufficient,
      evidence: <EvidenceChunk>[
        const EvidenceChunk(
          sourcePath: 'assets/games/cabo/docs/faq_zh.md',
          content: '',
        ),
      ],
      state: ChatMessageState.failed,
      canRetry: true,
      retryPrompt: '这个规则怎么处理？',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: MessageBubble(
            message: message,
            palette: PaletteRegistry.classic,
            copy: AppCopy(AppLanguage.zhHans),
            onSpeak: () {},
            onRetry: () => retried = true,
            retryTooltip: '重试',
          ),
        ),
      ),
    );

    expect(find.text('信息不足'), findsOneWidget);
    expect(find.text('faq_zh.md'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    await tester.tap(find.text('重试'));
    expect(retried, isTrue);
  });

  testWidgets('streaming bubble exposes an observable progress state', (
    WidgetTester tester,
  ) async {
    final ChatMessage message = ChatMessage(
      id: 'streaming',
      role: ChatRole.assistant,
      text: '',
      timestamp: DateTime(2026, 8, 18),
      state: ChatMessageState.streaming,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: MessageBubble(
            message: message,
            palette: PaletteRegistry.classic,
            copy: AppCopy(AppLanguage.zhHans),
            onSpeak: () {},
          ),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('正在回答…'), findsOneWidget);
  });

  testWidgets('chat bubble keeps time hidden until the parent reveals it', (
    WidgetTester tester,
  ) async {
    bool tapped = false;
    final ChatMessage message = ChatMessage(
      id: 'user-time',
      role: ChatRole.user,
      text: '你好',
      timestamp: DateTime(2026, 8, 18, 12, 30),
    );

    Widget buildBubble({required bool showTimestamp}) {
      return MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: MessageBubble(
            message: message,
            palette: PaletteRegistry.classic,
            copy: AppCopy(AppLanguage.zhHans),
            onSpeak: () {},
            showTimestamp: showTimestamp,
            onTap: () => tapped = true,
          ),
        ),
      );
    }

    await tester.pumpWidget(buildBubble(showTimestamp: false));
    expect(find.text('12:30'), findsNothing);

    await tester.tap(find.text('你好'));
    expect(tapped, isTrue);

    await tester.pumpWidget(buildBubble(showTimestamp: true));
    expect(find.text('12:30'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('12:30')).dy,
      greaterThan(tester.getBottomLeft(find.text('你好')).dy),
    );
  });
}
