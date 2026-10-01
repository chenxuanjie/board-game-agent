part of '../desktop_workspace_test.dart';

void _registerAssistantDesignTests(_DesktopWorkspaceTestContext context) {
  _assistantDesignTest(
    'rapid sidebar navigation keeps one current page and restores the draft',
    (tester) async {
      await _mount(tester, context.controller, const Size(1280, 800));
      await _navigate(tester, 'AI助手');
      await tester.enterText(
        find.byKey(const ValueKey('assistant-draft')),
        '保留这份草稿',
      );
      await tester.pump();
      for (final asset in [
        'sidebar_library.png',
        'sidebar_ai.png',
        'sidebar_settings.png',
        'sidebar_ai.png',
      ]) {
        await tester.tap(find.byKey(ValueKey('desktop-sidebar-item-$asset')));
        await tester.pump(const Duration(milliseconds: 25));
        expect(
          find.byType(DesktopAssistantPane),
          asset == 'sidebar_ai.png' ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull);
      }
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('assistant-draft')))
            .controller!
            .text,
        '保留这份草稿',
      );
    },
  );

  for (final size in const [
    Size(320, 600),
    Size(736, 700),
    Size(1280, 800),
    Size(1920, 1080),
  ]) {
    _assistantDesignTest(
      'assistant welcome and tools fit at $size with large text',
      (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        context.controller.openGlobalAssistant();
        await context.controller.saveAiApiConfig(
          context.controller.aiApiConfig.copyWith(model: 'gpt-5.6-luna'),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: buildDesktopTheme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.25)),
              child: child!,
            ),
            home: Scaffold(
              body: DesktopAssistantPane(controller: context.controller),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('assistant-welcome')), findsOneWidget);
        final composer = tester.getRect(
          find.byKey(const ValueKey('desktop-composer-box')),
        );
        expect(composer.width, lessThanOrEqualTo(900));
        expect(composer.left, greaterThanOrEqualTo(0));
        expect(composer.right, lessThanOrEqualTo(size.width));
        expect(composer.bottom, lessThanOrEqualTo(size.height));
        expect(
          find.byKey(const ValueKey('desktop-composer-send')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  _assistantDesignTest(
    'prompt cards fill a draft and preserve it when no model is selected',
    (tester) async {
      await _mount(tester, context.controller, const Size(1280, 800));
      await _navigate(tester, 'AI助手');
      await _captureDesktopTypography(tester, 'assistant-welcome');
      await tester.tap(find.byKey(const ValueKey('assistant-prompt-0')));
      await tester.pumpAndSettle();
      final draft = tester.widget<TextField>(
        find.byKey(const ValueKey('assistant-draft')),
      );
      expect(draft.controller!.text, '帮我梳理一遍回合流程');
      expect(draft.focusNode!.hasFocus, isTrue);
      expect(context.controller.selectedConversation!.messages, isEmpty);
      await tester.tap(find.byKey(const ValueKey('desktop-composer-send')));
      await tester.pump();
      expect(context.controller.selectedConversation!.messages, isEmpty);
      expect(draft.controller!.text, '帮我梳理一遍回合流程');
      expect(
        find.text(context.controller.copy.aiApiModelRequired),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  _assistantDesignTest('new chat isolates a draft and history restores it', (
    tester,
  ) async {
    final controller = AppController(
      preferencesService: _InMemoryPreferencesService(),
      aiService: _FakeAiService(),
      conversationStore: _WorkspaceConversationStore(),
      gameManifestService: GameManifestService(),
      remoteAssetService: _NoNetworkAssetService(),
      speechService: SpeechService(),
      ttsService: _UnavailableTtsService(),
    );
    await tester.runAsync(controller.reloadGames);
    addTearDown(controller.dispose);
    await _mount(tester, controller, const Size(1280, 800));
    await _navigate(tester, 'AI助手');
    final original = controller.selectedConversationId!;
    await tester.enterText(
      find.byKey(const ValueKey('assistant-draft')),
      '原会话草稿',
    );
    await tester.tap(
      find.byKey(const ValueKey('assistant-header-new-conversation')),
    );
    await tester.pumpAndSettle();
    expect(controller.selectedConversationId, isNot(original));
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('assistant-draft')))
          .controller!
          .text,
      isEmpty,
    );
    await tester.tap(
      find.byKey(const ValueKey('assistant-conversations-trigger')),
    );
    await tester.pumpAndSettle();
    await _captureDesktopTypography(tester, 'assistant-drawer');
    await tester.tap(find.byKey(ValueKey('assistant-conversation-$original')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('assistant-draft')))
          .controller!
          .text,
      '原会话草稿',
    );
    expect(tester.takeException(), isNull);
  });

  _assistantDesignTest('composer keyboard keeps Shift Enter as a newline', (
    tester,
  ) async {
    await _mount(tester, context.controller, const Size(1280, 800));
    await _navigate(tester, 'AI助手');
    final draft = find.byKey(const ValueKey('assistant-draft'));
    await tester.enterText(draft, '第一行');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(context.controller.selectedConversation!.messages, isEmpty);
    expect(find.text(context.controller.copy.aiApiModelRequired), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(
      find.text(context.controller.copy.aiApiModelRequired),
      findsOneWidget,
    );
    expect(tester.widget<TextField>(draft).controller!.text, contains('第一行'));
  });
}

void _assistantDesignTest(String name, WidgetTesterCallback body) {
  testWidgets(name, (tester) async {
    final previous = debugDisableShadows;
    try {
      debugDisableShadows = false;
      await body(tester);
    } finally {
      debugDisableShadows = previous;
    }
  });
}
