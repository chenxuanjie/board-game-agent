import 'package:board_game_agent/core/theme/app_motion.dart';
import 'package:board_game_agent/core/theme/app_theme.dart';
import 'package:board_game_agent/core/theme/palette_registry.dart';
import 'package:board_game_agent/ui/desktop/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final desktop in [false, true]) {
    testWidgets(
      '${desktop ? 'desktop' : 'mobile'} notices close by button and horizontal swipe',
      (tester) async {
        late BuildContext source;
        await tester.pumpWidget(
          MaterialApp(
            theme: desktop
                ? buildDesktopTheme()
                : AppTheme.buildTheme(PaletteRegistry.warmwoodStudy),
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  source = context;
                  return const SizedBox.expand();
                },
              ),
            ),
          ),
        );
        Future<void> show() async {
          ScaffoldMessenger.of(
            source,
          ).showSnackBar(const SnackBar(content: Text('测试消息')));
          await tester.pumpAndSettle();
          expect(find.text('测试消息'), findsOneWidget);
        }

        await show();
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();
        expect(find.text('测试消息'), findsNothing);
        for (final dx in [-600.0, 600.0]) {
          await show();
          await tester.drag(find.byType(SnackBar), Offset(dx, 0));
          await tester.pumpAndSettle();
          expect(find.text('测试消息'), findsNothing);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'an actionable notice expires with accessible navigation enabled',
    (tester) async {
      late BuildContext source;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildDesktopTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(accessibleNavigation: true),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) {
                source = context;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      ScaffoldMessenger.of(source).showSnackBar(
        SnackBar(
          content: const Text('已移出喜欢列表'),
          duration: AppMotion.notice,
          persist: false,
          action: SnackBarAction(label: '撤销', onPressed: () {}),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('撤销'), findsOneWidget);
      await tester.pump(AppMotion.notice);
      await tester.pumpAndSettle();
      expect(find.text('已移出喜欢列表'), findsNothing);
    },
  );
}
