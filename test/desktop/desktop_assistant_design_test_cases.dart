part of '../desktop_workspace_test.dart';

void _registerAssistantDesignTests(_DesktopWorkspaceTestContext context) {
  for (final size in const [Size(320, 600), Size(1280, 800)]) {
    _assistantDesignTest(
      'unconfigured model picker shrinks to its notice at $size',
      (tester) async {
        await context.controller.saveAiApiConfig(AiApiConfig.defaultOpenAi);
        await _mount(tester, context.controller, size);
        await _navigate(tester, 'AI助手');
        await tester.tap(find.byKey(const ValueKey('desktop-model-selector')));
        await tester.pumpAndSettle();
        expect(find.text('请先在设置中配置 AI 服务'), findsOneWidget);
        expect(
          tester
              .getSize(find.byKey(const ValueKey('desktop-model-picker-panel')))
              .height,
          lessThan(180),
        );
        expect(find.text('服务等级'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  _assistantDesignTest(
    'model picker fits one model without a blank list area',
    (tester) async {
      await context.controller.saveAiApiConfig(
        context.controller.aiApiConfig.copyWith(model: 'gpt-5.6-luna'),
      );
      await _mount(tester, context.controller, const Size(1280, 800));
      await _navigate(tester, 'AI助手');
      await tester.tap(find.byKey(const ValueKey('desktop-model-selector')));
      await tester.pumpAndSettle();
      final list = find.byKey(const ValueKey('desktop-model-picker-list'));
      final option = find.byKey(
        const ValueKey('desktop-model-option-gpt-5.6-luna'),
      );
      expect(
        tester.getSize(list).height - tester.getSize(option).height,
        lessThan(20),
      );
      expect(
        tester
            .getSize(find.byKey(const ValueKey('desktop-model-picker-panel')))
            .height,
        lessThan(360),
      );
      await _captureDesktopTypography(tester, 'model-picker-content-height');
      expect(tester.takeException(), isNull);
    },
  );

  _assistantDesignTest(
    'failed model config write retains current choice and retry works',
    (tester) async {
      final preferences = _FailingAiPreferences();
      final controller = await tester.runAsync(
        () => _createController(preferencesService: preferences),
      );
      addTearDown(controller!.dispose);
      await controller.saveAiApiConfig(
        controller.aiApiConfig.copyWith(model: 'gpt-6-astra'),
      );
      preferences.fail = true;
      await expectLater(
        controller.setAiModel('gpt-5.6-luna'),
        throwsStateError,
      );
      expect(controller.aiApiConfig.model, 'gpt-6-astra');
      expect((await preferences.loadAiApiConfig()).model, 'gpt-6-astra');
      preferences.fail = false;
      await controller.setAiModel('gpt-5.6-luna');
      expect(controller.aiApiConfig.model, 'gpt-5.6-luna');
      expect((await preferences.loadAiApiConfig()).model, 'gpt-5.6-luna');
    },
  );

  _assistantDesignTest(
    'assistant header is explicit and model summary has uniform type',
    (tester) async {
      await context.controller.saveAiApiConfig(
        context.controller.aiApiConfig.copyWith(
          model: 'gpt-6-astra',
          reasoningEffort: AiReasoningEffort.max,
        ),
      );
      await _mount(tester, context.controller, const Size(1280, 800));
      await _navigate(tester, 'AI助手');
      expect(find.byIcon(Icons.more_horiz_rounded), findsNothing);
      expect(
        find.byKey(const ValueKey('assistant-header-new-conversation')),
        findsOneWidget,
      );
      final model = find.descendant(
        of: find.byKey(const ValueKey('desktop-model-selector')),
        matching: find.byType(Text),
      );
      expect(model, findsOneWidget);
      final text = tester.widget<Text>(model);
      expect(text.data, 'gpt-6-astra');
      expect(text.style!.fontFamily, 'Noto Sans SC');
      expect(text.style!.fontWeight, FontWeight.w500);
      expect(text.style!.fontSize, 14);
      expect(find.text('最高'), findsNothing);
      expect(find.text('极高'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('desktop-answer-mode-selector')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate((widget) => widget is PopupMenuItem<bool>),
        findsNWidgets(2),
      );
      expect(
        find.byKey(const ValueKey('assistant-mode-knowledge')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('assistant-mode-smart')),
        findsOneWidget,
      );
      await _captureDesktopTypography(tester, 'assistant-answer-mode');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('assistant-mode-knowledge')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in const [Size(320, 600), Size(736, 700), Size(1280, 800)]) {
    _assistantDesignTest(
      'answer choices stay within viewport at $size and enlarged text',
      (tester) async {
        await _mount(
          tester,
          context.controller,
          size,
          textScaler: const TextScaler.linear(1.25),
        );
        await _navigate(tester, 'AI助手');
        await tester.tap(
          find.byKey(const ValueKey('desktop-answer-mode-selector')),
        );
        await tester.pumpAndSettle();
        for (final key in [
          'assistant-mode-knowledge',
          'assistant-mode-smart',
        ]) {
          final rect = tester.getRect(find.byKey(ValueKey(key)));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(size.width));
          expect(rect.top, greaterThanOrEqualTo(0));
          expect(rect.bottom, lessThanOrEqualTo(size.height));
        }
        await tester.tapAt(const Offset(1, 1));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('assistant-mode-smart')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  _assistantDesignTest(
    'answer choice persists, rolls back failure and allows retry',
    (tester) async {
      final preferences = _ControlledAnswerPreferences();
      final controller = AppController(
        preferencesService: preferences,
        aiService: _FakeAiService(),
        conversationStore: _WorkspaceConversationStore(),
        gameManifestService: GameManifestService(),
        remoteAssetService: _NoNetworkAssetService(),
        speechService: SpeechService(),
        ttsService: _UnavailableTtsService(),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildDesktopTheme(),
          home: Scaffold(
            body: AnimatedBuilder(
              animation: controller,
              builder: (context, _) => AssistantAnswerModeSelector(
                controller: controller,
                useGlobalMode: true,
                enabled: true,
              ),
            ),
          ),
        ),
      );
      final trigger = find.byKey(
        const ValueKey('desktop-answer-mode-selector'),
      );
      await tester.tap(trigger);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('assistant-mode-knowledge')));
      await tester.pump(const Duration(milliseconds: 180));
      expect(preferences.calls, 1);
      expect(tester.widget<PopupMenuButton<bool>>(trigger).enabled, isFalse);
      preferences.completion.complete();
      await tester.pumpAndSettle();
      expect(preferences.saved, AiAnswerMode.knowledgeOnly);
      expect(controller.globalAnswerMode, AiAnswerMode.knowledgeOnly);
      expect(controller.gameAnswerMode, AiAnswerMode.knowledgeOnly);
      preferences.completion = Completer<void>();
      preferences.fail = true;
      await tester.tap(trigger);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('assistant-mode-smart')));
      await tester.pump(const Duration(milliseconds: 180));
      preferences.completion.complete();
      await tester.pumpAndSettle();
      expect(controller.globalAnswerMode, AiAnswerMode.knowledgeOnly);
      expect(preferences.saved, AiAnswerMode.knowledgeOnly);
      expect(find.text('模式未保存，请重试'), findsOneWidget);
      expect(tester.widget<PopupMenuButton<bool>>(trigger).enabled, isTrue);
      preferences.completion = Completer<void>();
      preferences.fail = false;
      await tester.tap(trigger);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('assistant-mode-smart')));
      await tester.pump(const Duration(milliseconds: 180));
      preferences.completion.complete();
      await tester.pumpAndSettle();
      expect(controller.globalAnswerMode, AiAnswerMode.knowledgeThenDirect);
      expect(preferences.saved, AiAnswerMode.knowledgeThenDirect);
      expect(controller.gameAnswerMode, AiAnswerMode.knowledgeOnly);
      expect(preferences.calls, 3);
      expect(tester.takeException(), isNull);
    },
  );

  _assistantDesignTest(
    'cover continuity completes and rapid navigation cancels its overlay',
    (tester) async {
      await _mount(tester, context.controller, const Size(1280, 800));
      await _navigate(tester, '游戏库');
      final game = context.controller.games.first;
      final poster = find.byKey(ValueKey('desktop-poster-${game.id}'));
      await tester.tap(poster);
      await tester.pump();
      await tester.pump();
      expect(find.byType(GameCoverFlight), findsOneWidget);
      expect(find.byType(DesktopGameDetailPane), findsOneWidget);
      expect(find.byType(DesktopGamesPane), findsNothing);
      await tester.pumpAndSettle();
      expect(find.byType(GameCoverFlight), findsNothing);
      await _navigate(tester, '首页');
      await _navigate(tester, '游戏库');
      await tester.tap(poster);
      await tester.pump();
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('desktop-sidebar-item-sidebar_ai.png')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(GameCoverFlight), findsNothing);
      expect(find.byType(DesktopAssistantPane), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  _assistantDesignTest(
    'favorite feedback waits for persistence, blocks duplicate presses and reports rollback',
    (tester) async {
      final preferences = _ControlledFavoritePreferences();
      final controller = AppController(
        preferencesService: preferences,
        aiService: _FakeAiService(),
        conversationStore: _WorkspaceConversationStore(),
        gameManifestService: GameManifestService(),
        remoteAssetService: _NoNetworkAssetService(),
        speechService: SpeechService(),
        ttsService: _UnavailableTtsService(),
      );
      await tester.runAsync(controller.reloadGames);
      addTearDown(controller.dispose);
      final game = controller.games.first;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildDesktopTheme(),
          home: Scaffold(
            body: AnimatedBuilder(
              animation: controller,
              builder: (context, _) =>
                  FavoriteToggleButton(controller: controller, game: game),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(IconButton));
      await tester.pump();
      expect(preferences.calls, 1);
      expect(
        tester.widget<IconButton>(find.byType(IconButton)).onPressed,
        isNull,
      );
      expect(
        tester
            .widget<FavoriteFeedbackIcon>(find.byType(FavoriteFeedbackIcon))
            .selected,
        isFalse,
      );
      preferences.completion.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(
        tester
            .widget<FavoriteFeedbackIcon>(find.byType(FavoriteFeedbackIcon))
            .selected,
        isTrue,
      );
      expect(
        tester
            .widget<ScaleTransition>(
              find.descendant(
                of: find.byType(FavoriteFeedbackIcon),
                matching: find.byType(ScaleTransition),
              ),
            )
            .scale
            .value,
        greaterThan(1),
      );
      await tester.pumpAndSettle();
      preferences.completion = Completer<void>();
      preferences.fail = true;
      await tester.tap(find.byType(IconButton));
      await tester.pump();
      preferences.completion.complete();
      await tester.pumpAndSettle();
      expect(controller.isFavorite(game), isTrue);
      expect(find.text(controller.copy.favoriteSaveFailed), findsOneWidget);
      expect(
        tester.widget<IconButton>(find.byType(IconButton)).onPressed,
        isNotNull,
      );
      expect(preferences.calls, 2);
      expect(tester.takeException(), isNull);
    },
  );

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

class _ControlledFavoritePreferences extends _InMemoryPreferencesService {
  Completer<void> completion = Completer<void>();
  bool fail = false;
  int calls = 0;
  @override
  Future<void> saveFavoriteGames(Iterable<FavoriteGameRecord> records) async {
    calls++;
    await completion.future;
    if (fail) throw StateError('test write failure');
    await super.saveFavoriteGames(records);
  }
}

class _ControlledAnswerPreferences extends _InMemoryPreferencesService {
  Completer<void> completion = Completer<void>();
  bool fail = false;
  int calls = 0;
  AiAnswerMode? saved;
  @override
  Future<void> saveGlobalAnswerMode(AiAnswerMode mode) async {
    calls++;
    await completion.future;
    if (fail) throw StateError('test mode write failure');
    saved = mode;
  }
}

class _FailingAiPreferences extends _InMemoryPreferencesService {
  bool fail = false;
  @override
  Future<AiApiConfig> loadAiApiConfig() async =>
      _aiApiConfig ?? await super.loadAiApiConfig();
  @override
  Future<void> saveAiApiConfig(AiApiConfig config) async {
    if (fail) throw StateError('test AI config write failure');
    await super.saveAiApiConfig(config);
  }
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
