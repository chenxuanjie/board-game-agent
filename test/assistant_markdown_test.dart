import 'package:board_game_agent/ui/shared/assistant/assistant_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stream partitions preserve fences, lists and replacement text', () {
    final document = StreamingMarkdownDocument();
    const first = 'Intro\n\n```dart\na();\n\nb();\n```\n\n';
    document.update('${first}Next\n');
    expect(document.blocks, ['Intro\n\n', '```dart\na();\n\nb();\n```\n\n']);
    expect(document.blocks.join() + document.tail, '${first}Next\n');
    document.update('- first\n\n  continuation\n\n- second\n\nEnd\n');
    expect(document.blocks.single, '- first\n\n  continuation\n\n- second\n\n');
    document.update('replacement');
    expect(document.blocks, isEmpty);
    expect(document.tail, 'replacement');
  });

  test('late reference definitions restore whole-document interpretation', () {
    final document = StreamingMarkdownDocument();
    document.update('See [rules][book].\n\nOther\n');
    expect(document.blocks, hasLength(1));
    const full =
        'See [rules][book].\n\nOther\n\n[book]: https://example.test\n';
    document.update(full);
    expect(document.blocks, isEmpty);
    expect(document.tail, full);
  });

  testWidgets(
    'completed blocks retain their widget while tail grows; final is complete',
    (tester) async {
      final style = MarkdownStyleSheet(p: const TextStyle(fontSize: 16));
      Future<void> show(String text, {bool streaming = true}) =>
          tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: AssistantMarkdown(
                  data: text,
                  streaming: streaming,
                  styleSheet: style,
                ),
              ),
            ),
          );
      await show('Stable **paragraph**\n\nTail\n');
      final stable = tester.widget(
        find.byKey(const ValueKey('stream-block-0')),
      );
      final element = tester.element(
        find.byKey(const ValueKey('stream-block-0')),
      );
      await show('Stable **paragraph**\n\nTail\nkeeps growing');
      expect(
        identical(
          stable,
          tester.widget(find.byKey(const ValueKey('stream-block-0'))),
        ),
        isTrue,
      );
      expect(
        identical(
          element,
          tester.element(find.byKey(const ValueKey('stream-block-0'))),
        ),
        isTrue,
      );
      const finalText = 'Stable **paragraph**\n\nTail\nkeeps growing';
      await show(finalText, streaming: false);
      expect(find.byType(MarkdownBody), findsOneWidget);
      expect(
        tester.widget<MarkdownBody>(find.byType(MarkdownBody)).data,
        finalText,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
