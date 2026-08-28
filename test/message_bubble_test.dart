import 'package:board_game_agent/models/answer_source.dart';
import 'package:board_game_agent/models/chat_message.dart';
import 'package:board_game_agent/models/evidence_chunk.dart';
import 'package:board_game_agent/models/app_language.dart';
import 'package:board_game_agent/models/rule_citation.dart';
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
          sourcePath: 'assets/games/cabo/docs/local/knowledge/faq_cn.md',
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
    expect(find.text('faq_cn.md'), findsOneWidget);
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

  testWidgets(
    'assistant actions and references render outside the answer bubble',
    (WidgetTester tester) async {
      bool copied = false;
      final ChatMessage message = ChatMessage(
        id: 'complete',
        role: ChatRole.assistant,
        text: '答案正文',
        timestamp: DateTime(2026, 8, 18, 12, 30),
        source: AnswerSource.rulebook,
        citations: <RuleCitation>[
          const RuleCitation(
            sourceType: 'file',
            sourceId: 'rulebook',
            path: 'assets/rulebook.md',
            page: 3,
          ),
        ],
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
              onCopy: () => copied = true,
              copyTooltip: '复制回答',
            ),
          ),
        ),
      );

      expect(find.byTooltip('复制回答'), findsOneWidget);
      expect(find.text('规则库'), findsOneWidget);
      expect(find.text('第 3 页'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byTooltip('复制回答')).dy,
        greaterThan(tester.getBottomLeft(find.text('答案正文')).dy),
      );
      expect(
        tester.getTopLeft(find.text('规则库')).dy,
        greaterThan(tester.getBottomLeft(find.text('答案正文')).dy),
      );

      await tester.tap(find.byTooltip('复制回答'));
      expect(copied, isTrue);
    },
  );

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
