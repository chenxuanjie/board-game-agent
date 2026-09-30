part of '../desktop_workspace_test.dart';

void _registerDesktopTypographyTests(_DesktopWorkspaceTestContext context) {
  testWidgets('real font stays readable at 125 percent in desktop controls', (
    tester,
  ) async {
    final shadowsDisabled = debugDisableShadows;
    debugDisableShadows = false;
    try {
      await context.controller.saveAiApiConfig(
        context.controller.aiApiConfig.copyWith(
          model: 'gpt-5.6-luna',
          apiKey: 'test-key',
        ),
      );
      await context.controller.refreshAiModels();
      await _mount(
        tester,
        context.controller,
        const Size(1280, 800),
        textScaler: const TextScaler.linear(1.25),
      );
      await _captureDesktopTypography(tester, 'home');
      expect(tester.takeException(), isNull);

      await _navigate(tester, '设置');
      final speed = find.byKey(
        const ValueKey<String>('desktop-settings-ai-speed'),
      );
      await tester.ensureVisible(speed);
      await tester.pumpAndSettle();
      for (final dropdown in tester.widgetList<DropdownButton<dynamic>>(
        find.byWidgetPredicate((widget) => widget is DropdownButton<dynamic>),
      )) {
        expect(dropdown.style?.fontFamily, 'Noto Sans SC');
      }
      await _captureDesktopTypography(tester, 'settings');
      await tester.tap(speed);
      await tester.pumpAndSettle();
      await _captureDesktopTypography(tester, 'speed-menu');
      expect(find.text('快速（Fast）').last.hitTestable(), findsOneWidget);
      expect(find.text('标准（Default）').last.hitTestable(), findsOneWidget);
      for (final label in ['自动', '快速（Fast）', '标准（Default）']) {
        final rendered = tester.renderObject<RenderParagraph>(
          find.text(label).last,
        );
        expect(rendered.text.style?.fontFamily, 'Noto Sans SC');
        expect(rendered.didExceedMaxLines, isFalse);
      }
      expect(tester.takeException(), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      await _navigate(tester, 'AI助手');
      await tester.tap(
        find.byKey(const ValueKey<String>('desktop-model-selector')),
      );
      await tester.pumpAndSettle();
      final searchContext = tester.element(
        find.byKey(const ValueKey<String>('desktop-model-picker-search')),
      );
      expect(
        Theme.of(searchContext).textTheme.bodySmall?.fontFamily,
        'Noto Sans SC',
      );
      final focused = Theme.of(
        searchContext,
      ).inputDecorationTheme.focusedBorder;
      expect(focused?.borderSide.color, DesktopColors.orange);
      await _captureDesktopTypography(tester, 'model-picker');
      await tester.tap(
        find.byKey(
          const ValueKey<String>('desktop-model-picker-tab-reasoning'),
        ),
      );
      await tester.pumpAndSettle();
      await _captureDesktopTypography(tester, 'reasoning-picker');
      final xhigh = find.descendant(
        of: find.byKey(
          const ValueKey<String>('desktop-reasoning-option-xhigh'),
        ),
        matching: find.byType(Text),
      );
      expect(
        tester.renderObject<RenderParagraph>(xhigh).didExceedMaxLines,
        isFalse,
      );
      expect(tester.takeException(), isNull);
    } finally {
      debugDisableShadows = shadowsDisabled;
    }
  });
}

// Optional screenshots use production widgets and the bundled font. They are
// test-rendered previews, not evidence of native OS rasterization.
Future<void> _captureDesktopTypography(WidgetTester tester, String name) async {
  final directory = Platform.environment['DESKTOP_UI_CAPTURE_DIR'];
  if (directory == null || directory.isEmpty) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey<String>('desktop-test-capture')),
  );
  await tester.runAsync(() async {
    final rendered = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await rendered.toByteData(format: ImageByteFormat.png);
      if (bytes == null) {
        throw StateError('Desktop screenshot could not be encoded');
      }
      await Directory(directory).create(recursive: true);
      await File(
        '$directory/$name.png',
      ).writeAsBytes(bytes.buffer.asUint8List());
    } finally {
      rendered.dispose();
    }
  });
}
