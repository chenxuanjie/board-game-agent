import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:board_game_agent/models/app_language.dart';
import 'package:board_game_agent/theme/app_theme.dart';
import 'package:board_game_agent/theme/palette_registry.dart';
import 'package:board_game_agent/ui/app_copy.dart';
import 'package:board_game_agent/ui/widgets/document_failure_view.dart';

void main() {
  testWidgets('document failure view uses stable copy and recovery actions', (
    WidgetTester tester,
  ) async {
    bool retried = false;
    bool backed = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.buildTheme(PaletteRegistry.classic),
        home: Scaffold(
          body: DocumentFailureView(
            copy: AppCopy(AppLanguage.zhHans),
            title: '规则书',
            kind: DocumentFailureKind.render,
            onRetry: () => retried = true,
            onBack: () => backed = true,
          ),
        ),
      ),
    );

    expect(find.text('“规则书”暂时无法打开，文件可能损坏或格式暂不支持。'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('返回'), findsOneWidget);

    await tester.tap(find.text('重试'));
    await tester.tap(find.text('返回'));
    expect(retried, isTrue);
    expect(backed, isTrue);
  });
}
