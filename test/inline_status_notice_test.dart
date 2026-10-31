import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:board_game_agent/ui/shared/inline_status_notice.dart';

void main() {
  Future<void> mount(
    WidgetTester tester, {
    required VoidCallback onDismiss,
    Future<void> Function()? retry,
    Object revision = 1,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: InlineStatusNotice(
            message: '资料更新未完成',
            revision: revision,
            onRetry: retry,
            onDismiss: onDismiss,
          ),
        ),
      ),
    ),
  );

  Future<void> expire(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  }

  testWidgets('notice expires once and a new revision can display again', (
    tester,
  ) async {
    var dismissals = 0;
    await mount(tester, onDismiss: () => ++dismissals);
    await expire(tester);
    expect(find.text('资料更新未完成'), findsNothing);
    expect(dismissals, 1);
    await mount(tester, onDismiss: () => ++dismissals);
    await tester.pump();
    expect(find.text('资料更新未完成'), findsNothing);
    await mount(tester, onDismiss: () => ++dismissals, revision: 2);
    await tester.pumpAndSettle();
    expect(find.text('资料更新未完成'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('status-dismiss')));
    await tester.pumpAndSettle();
    expect(dismissals, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('hover pauses expiry until the pointer leaves', (tester) async {
    var dismissed = false;
    await mount(tester, onDismiss: () => dismissed = true);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(790, 590));
    await mouse.moveTo(tester.getCenter(find.text('资料更新未完成')));
    await tester.pump(const Duration(seconds: 6));
    expect(dismissed, isFalse);
    await mouse.moveTo(const Offset(790, 590));
    await expire(tester);
    expect(dismissed, isTrue);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox());
  });

  for (final dx in [-700.0, 700.0]) {
    testWidgets('notice dismisses horizontally dx=$dx', (tester) async {
      var dismissed = false;
      await mount(tester, onDismiss: () => dismissed = true);
      await tester.drag(find.text('资料更新未完成'), Offset(dx, 0));
      await tester.pumpAndSettle();
      expect(dismissed, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('an active retry prevents expiry and duplicate operations', (
    tester,
  ) async {
    final gate = Completer<void>();
    var calls = 0, dismissals = 0;
    await mount(
      tester,
      onDismiss: () => ++dismissals,
      retry: () async {
        ++calls;
        await gate.future;
      },
    );
    await tester.tap(find.byKey(const ValueKey('status-retry')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('status-retry')));
    await tester.pump(const Duration(seconds: 6));
    expect(calls, 1);
    expect(dismissals, 0);
    gate.complete();
    await tester.pumpAndSettle();
    await expire(tester);
    expect(dismissals, 1);
    await tester.pumpWidget(const SizedBox());
  });
}
