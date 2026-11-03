import 'package:board_game_agent/ui/shared/loading_action_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shrinks, shows real progress and confirms only success', (
    tester,
  ) async {
    var loading = false;
    bool? succeeded;
    var taps = 0;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return SizedBox(
                width: 220,
                height: 52,
                child: LoadingActionButton(
                  onPressed: loading ? null : () => taps++,
                  loading: loading,
                  succeeded: succeeded,
                  label: '测试连接',
                  loadingLabel: '正在检查',
                  doneLabel: '完成',
                  background: Colors.orange,
                  foreground: Colors.white,
                  successBackground: Colors.green,
                  successForeground: Colors.white,
                ),
              );
            },
          ),
        ),
      ),
    );
    final button = find.byType(LoadingActionButton);
    final surface = find.byKey(const ValueKey('loading-action-surface'));
    final original = tester.getSize(button);
    await tester.tap(button);
    expect(taps, 1);

    update(() => loading = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(tester.getSize(surface).width, lessThan(220));
    expect(tester.getSize(button), original);
    await tester.pump(const Duration(milliseconds: 150));
    expect(tester.getSize(surface).width, closeTo(52, .1));
    await tester.tap(button, warnIfMissed: false);
    expect(taps, 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 351));
    expect(tester.getSize(surface).width, closeTo(220, .1));
    expect(find.text('正在检查'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('loading-action-spinner')),
      findsOneWidget,
    );

    update(() {
      loading = false;
      succeeded = true;
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 351));
    expect(find.text('完成'), findsOneWidget);
    expect(
      (tester.widget<Container>(surface).decoration! as BoxDecoration).color!
          .toARGB32(),
      Colors.green.toARGB32(),
    );
    expect(tester.getSize(button), original);
    await tester.tap(button);
    expect(taps, 2);
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pumpAndSettle();
    expect(find.text('测试连接'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failure never shows success and reduced motion stays still', (
    tester,
  ) async {
    var loading = false;
    bool? succeeded;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            disableAnimations: true,
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return LoadingActionButton(
                  onPressed: loading ? null : () {},
                  loading: loading,
                  succeeded: succeeded,
                  label: '测试连接',
                  loadingLabel: '正在检查',
                  doneLabel: '完成',
                  background: Colors.orange,
                  foreground: Colors.white,
                  successBackground: Colors.green,
                  successForeground: Colors.white,
                );
              },
            ),
          ),
        ),
      ),
    );
    update(() => loading = true);
    await tester.pump();
    expect(find.text('正在检查'), findsOneWidget);
    final rotation = tester.widget<RotationTransition>(
      find.descendant(
        of: find.byType(LoadingActionButton),
        matching: find.byType(RotationTransition),
      ),
    );
    expect(rotation.turns.value, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(rotation.turns.value, 0);
    update(() {
      loading = false;
      succeeded = false;
    });
    await tester.pump();
    expect(find.text('完成'), findsNothing);
    expect(find.text('测试连接'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
