import 'package:board_game_agent/ui/shared/assistant/assistant_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final compact in [true, false]) {
    testWidgets(
      'conversation transitions retain input and one scroll client compact=$compact',
      (tester) async {
        final identity = ValueNotifier('a');
        final welcome = ValueNotifier(true);
        final reduced = ValueNotifier(false);
        final delta = ValueNotifier('首段');
        final input = TextEditingController(text: '未发送草稿');
        final focus = FocusNode();
        final scroll = ScrollController();
        addTearDown(() {
          identity.dispose();
          welcome.dispose();
          reduced.dispose();
          delta.dispose();
          input.dispose();
          focus.dispose();
          scroll.dispose();
        });
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AnimatedBuilder(
                animation: Listenable.merge([
                  identity,
                  welcome,
                  reduced,
                  delta,
                ]),
                builder: (context, _) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(disableAnimations: reduced.value),
                  child: Column(
                    children: [
                      Expanded(
                        child: AssistantConversationTransition(
                          identity: identity.value,
                          compact: compact,
                          showWelcome: welcome.value,
                          welcome: const Center(child: Text('欢迎')),
                          messages: ListView(
                            controller: scroll,
                            children: [
                              Text('对话 ${identity.value}'),
                              Text(delta.value),
                              const SizedBox(height: 1200),
                            ],
                          ),
                        ),
                      ),
                      TextField(controller: input, focusNode: focus),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.byType(TextField));
        await tester.pumpAndSettle();
        final editable = tester.state<EditableTextState>(
          find.byType(EditableText),
        );
        welcome.value = false;
        await tester.pump();
        expect(
          find.byKey(const ValueKey('assistant-welcome-exit')),
          findsOneWidget,
        );
        expect(scroll.positions, hasLength(1));
        expect(
          tester.state<EditableTextState>(find.byType(EditableText)),
          same(editable),
        );
        expect(focus.hasFocus, isTrue);
        await tester.pump(const Duration(milliseconds: 60));
        identity.value = 'b';
        await tester.pump();
        expect(
          find.byKey(const ValueKey('assistant-welcome-exit')),
          findsNothing,
        );
        expect(find.text('对话 a'), findsNothing);
        expect(find.text('对话 b'), findsOneWidget);
        expect(scroll.positions, hasLength(1));
        expect(input.text, '未发送草稿');
        expect(focus.hasFocus, isTrue);
        await tester.pump(const Duration(milliseconds: 250));
        final fade = find.byKey(
          const ValueKey('assistant-conversation-transition'),
        );
        expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
        delta.value = '首段，追加流式内容';
        await tester.pump();
        expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
        reduced.value = true;
        identity.value = 'c';
        await tester.pump();
        expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
        expect(
          tester.state<EditableTextState>(find.byType(EditableText)),
          same(editable),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
