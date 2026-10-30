part of '../mobile_home_test.dart';

class _CompactComposerController extends AppController {
  _CompactComposerController()
    : super(
        preferencesService: PreferencesService(),
        aiService: _UnusedAiService(),
        gameManifestService: FixtureGameManifestService(),
        remoteAssetService: _NoNetworkAssetService(),
        speechService: SpeechService(),
        ttsService: _UnavailableTtsService(),
      );

  bool listening = false;
  bool sending = false;
  // This fixture exercises controls for an available knowledge context.
  @override
  bool get assistantKnowledgeAvailable => true;
  AppLanguage testLanguage = AppLanguage.zhHans;
  @override
  AppCopy get copy => AppCopy(testLanguage);
  @override
  bool get isListening => listening;
  @override
  bool isSendingForContext({required bool useGlobalMode}) => sending;
  void update({bool? recording, bool? generating}) {
    listening = recording ?? listening;
    sending = generating ?? sending;
    notifyListeners();
  }
}

void _registerCompactComposerTests() {
  testWidgets(
    'plus opens an anchored menu that stays in view and can be dismissed',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final controller = _CompactComposerController();
      final draft = TextEditingController();
      addTearDown(controller.dispose);
      addTearDown(draft.dispose);
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.buildTheme(controller.palette),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: AssistantComposer(
                controller: controller,
                textController: draft,
                useGlobalMode: true,
                onSend: () async {},
              ),
            ),
          ),
        ),
      );
      final trigger = find.byKey(const ValueKey('assistant-context-button'));
      final anchor = tester.getRect(trigger);
      await tester.tap(trigger);
      await tester.pumpAndSettle();
      final menu = find.byKey(const ValueKey('assistant-context-menu'));
      expect(menu, findsOneWidget);
      final bounds = tester.getRect(menu);
      expect(bounds.left, greaterThanOrEqualTo(0));
      expect(bounds.right, lessThanOrEqualTo(320));
      expect(bounds.bottom, lessThanOrEqualTo(anchor.top));
      expect(find.byType(BottomSheet), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(menu, findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('enter does not send while the input method is composing', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final controller = _CompactComposerController();
    final draft = TextEditingController();
    var sends = 0;
    addTearDown(controller.dispose);
    addTearDown(draft.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.buildTheme(controller.palette),
        home: Scaffold(
          body: AssistantComposer(
            controller: controller,
            textController: draft,
            useGlobalMode: true,
            onSend: () async {
              sends++;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('assistant-draft')));
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'nihao',
        selection: TextSelection.collapsed(offset: 5),
        composing: TextRange(start: 0, end: 5),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(sends, 0);
    draft.value = const TextEditingValue(
      text: '你好',
      selection: TextSelection.collapsed(offset: 2),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(sends, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'android keyboard expands the composer and exposes the model selector',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final controller = _CompactComposerController();
      final draft = TextEditingController();
      addTearDown(controller.dispose);
      addTearDown(draft.dispose);
      await tester.binding.setSurfaceSize(const Size(390, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      Widget page(double inset) => MaterialApp(
        theme: AppTheme.buildTheme(controller.palette),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(viewInsets: EdgeInsets.only(bottom: inset)),
          child: child!,
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: AssistantComposer(
              controller: controller,
              textController: draft,
              useGlobalMode: true,
              keyboardVisible: inset > 0,
              onSend: () async {},
              onMicTap: () async {},
            ),
          ),
        ),
      );
      await tester.pumpWidget(page(0));
      await tester.pumpAndSettle();
      final box = find.byKey(const ValueKey('assistant-composer-box'));
      final height = tester.getSize(box).height;
      expect(
        find.byKey(const ValueKey('desktop-model-selector')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('assistant-draft')));
      await tester.pumpWidget(page(300));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('desktop-model-selector')),
        findsOneWidget,
      );
      expect(tester.getSize(box).height, greaterThan(height));
      await tester.tap(find.byKey(const ValueKey('assistant-context-button')));
      await tester.pumpAndSettle();
      final menuBounds = tester.getRect(
        find.byKey(const ValueKey('assistant-context-menu')),
      );
      expect(menuBounds.bottom, lessThanOrEqualTo(500));
      expect(menuBounds.top, greaterThanOrEqualTo(0));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.pumpWidget(page(0));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('desktop-model-selector')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'composer expands and shrinks without losing the draft or focus',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final controller = _CompactComposerController();
      final draft = TextEditingController();
      addTearDown(controller.dispose);
      addTearDown(draft.dispose);
      await tester.binding.setSurfaceSize(const Size(390, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.buildTheme(controller.palette),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: AssistantComposer(
                controller: controller,
                textController: draft,
                useGlobalMode: true,
                onSend: () async {},
                onMicTap: () async {},
              ),
            ),
          ),
        ),
      );
      final box = find.byKey(const ValueKey('assistant-composer-box'));
      final field = find.byKey(const ValueKey('assistant-draft'));
      expect(
        find.byKey(const ValueKey('desktop-model-selector')),
        findsNothing,
      );
      await tester.tap(field);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('desktop-model-selector')),
        findsOneWidget,
      );
      final small = tester.getSize(box).height;
      final longText = '很长的桌游规则问题' * 15;
      await tester.enterText(field, longText);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final halfway = tester.getSize(box).height;
      await tester.pumpAndSettle();
      final large = tester.getSize(box).height;
      expect(large, greaterThan(small));
      expect(halfway, lessThan(large));
      expect(draft.text, longText);
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
      await tester.enterText(field, '短问题');
      await tester.pumpAndSettle();
      expect(tester.getSize(box).height, closeTo(small, 1));
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );
  testWidgets(
    'compact composer exposes controls at narrow widths and large text',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final controller = _CompactComposerController();
      final draft = TextEditingController();
      addTearDown(controller.dispose);
      addTearDown(draft.dispose);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final width in [280.0, 320.0, 390.0, 430.0]) {
        await tester.binding.setSurfaceSize(Size(width, 700));
        for (final language in [AppLanguage.zhHans, AppLanguage.en]) {
          controller.testLanguage = language;
          for (final scale in [1.0, 1.5, 2.0]) {
            await tester.pumpWidget(
              MaterialApp(
                key: UniqueKey(),
                theme: AppTheme.buildTheme(controller.palette),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Scaffold(
                  body: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: AssistantComposer(
                        controller: controller,
                        textController: draft,
                        useGlobalMode: true,
                        onSend: () async {},
                        onMicTap: () async {},
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final mode = find.byKey(const ValueKey('assistant-context-button'));
            final action = find.byKey(
              const ValueKey('assistant-composer-send'),
            );
            expect(
              tester
                  .getRect(find.byKey(const ValueKey('assistant-draft')))
                  .center
                  .dy,
              closeTo(tester.getRect(action).center.dy, 1),
            );
            expect(
              tester.getRect(mode).center.dy,
              closeTo(tester.getRect(action).center.dy, 1),
            );
            expect(tester.getSize(action), const Size(48, 48));
            expect(
              find.byKey(const ValueKey('desktop-model-selector')),
              findsNothing,
            );
            expect(
              find.text(controller.copy.smartSupplementLabel),
              findsNothing,
            );
            expect(tester.takeException(), isNull);
          }
        }
      }
    },
  );

  testWidgets(
    'combined action records, stops recording, sends and exposes generation stop',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final controller = _CompactComposerController();
      final draft = TextEditingController();
      var micTaps = 0;
      var sends = 0;
      addTearDown(controller.dispose);
      addTearDown(draft.dispose);
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.buildTheme(controller.palette),
          home: Scaffold(
            body: AssistantComposer(
              controller: controller,
              textController: draft,
              useGlobalMode: true,
              onMicTap: () async {
                micTaps++;
                controller.update(recording: !controller.listening);
              },
              onSend: () async {
                sends++;
                controller.update(generating: true);
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final action = find.byKey(const ValueKey('assistant-composer-send'));
      Finder icon(IconData data) =>
          find.descendant(of: action, matching: find.byIcon(data));
      expect(icon(Icons.mic_none_rounded), findsOneWidget);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(micTaps, 1);
      expect(icon(Icons.stop_rounded), findsOneWidget);
      draft.text = '语音识别中的问题';
      await tester.pumpAndSettle();
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(micTaps, 2);
      expect(sends, 0);
      expect(icon(Icons.arrow_upward_rounded), findsOneWidget);
      await tester.longPress(action);
      await tester.pumpAndSettle();
      expect(micTaps, 3);
      expect(sends, 0);
      await tester.tap(action);
      await tester.pumpAndSettle();
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(sends, 1);
      expect(icon(Icons.stop_rounded), findsOneWidget);
      expect(
        tester.widget<IconButton>(action).tooltip,
        controller.copy.stopGenerating,
      );
      expect(tester.widget<IconButton>(action).onPressed, isNotNull);
      await tester.tap(find.byKey(const ValueKey('assistant-context-button')));
      await tester.pumpAndSettle();
      expect(find.text('下次发送生效'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('assistant-context-knowledge')),
      );
      await tester.pumpAndSettle();
      expect(controller.allowSmartSupplement(useGlobalMode: true), isFalse);
      expect(controller.sending, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
