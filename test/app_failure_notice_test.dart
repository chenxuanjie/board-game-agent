import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:board_game_agent/ui/shared/app_failure_notice.dart';
import 'package:board_game_agent/core/theme/app_theme.dart';
import 'package:board_game_agent/core/theme/palette_registry.dart';

void main() {
  testWidgets(
    'top notice renews during exit instead of stacking or blocking the page',
    (tester) async {
      late BuildContext source;
      var actions = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.buildTheme(PaletteRegistry.warmwoodStudy),
          home: Scaffold(
            body: Builder(
              builder: (context) {
                source = context;
                return Center(
                  child: TextButton(
                    onPressed: () => actions++,
                    child: const Text('继续操作'),
                  ),
                );
              },
            ),
          ),
        ),
      );
      showAppFailureNotice(source, '点赞失败，请检查网络');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('app-failure-notice')), findsOneWidget);
      await tester.tap(find.text('继续操作'));
      expect(actions, 1);
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 40));
      showAppFailureNotice(source, '收藏未保存，请重试');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('app-failure-notice')), findsOneWidget);
      expect(find.text('点赞失败，请检查网络'), findsNothing);
      expect(find.text('收藏未保存，请重试'), findsOneWidget);
      await tester.tap(find.byTooltip('关闭提示'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('app-failure-notice')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'notice fits narrow large text and survives the originating route closing',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.buildTheme(PaletteRegistry.warmwoodStudy),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  child: const Text('打开'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => Scaffold(
                        body: Center(
                          child: TextButton(
                            child: const Text('发送'),
                            onPressed: () {
                              showAppFailureNotice(context, '点赞失败，请检查网络后重试');
                              Navigator.of(context).pop();
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('发送'));
      await tester.pumpAndSettle();
      final bounds = tester.getRect(
        find.byKey(const ValueKey('app-failure-notice')),
      );
      expect(bounds.left, greaterThanOrEqualTo(12));
      expect(bounds.right, lessThanOrEqualTo(308));
      expect(bounds.top, lessThan(100));
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('app-failure-notice')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
