part of '../mobile_home_test.dart';

class _CompactComposerController extends AppController {
  _CompactComposerController()
    : super(
        preferencesService: PreferencesService(),
        aiService: _UnusedAiService(),
        gameManifestService: GameManifestService(),
        remoteAssetService: _NoNetworkAssetService(),
        speechService: SpeechService(),
        ttsService: _UnavailableTtsService(),
      );

  bool listening = false;
  bool sending = false;
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
    'compact composer stays on one row at narrow widths and large text',
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
            final mode = find.byKey(
              const ValueKey('desktop-answer-mode-selector'),
            );
            final model = find.byKey(const ValueKey('desktop-model-selector'));
            final action = find.byKey(
              const ValueKey('assistant-composer-send'),
            );
            expect(
              tester.getRect(mode).center.dy,
              closeTo(tester.getRect(action).center.dy, 1),
            );
            expect(
              tester.getRect(model).center.dy,
              closeTo(tester.getRect(action).center.dy, 1),
            );
            expect(tester.getSize(action), const Size(48, 48));
            expect(
              tester
                  .widget<AssistantAnswerModeSelector>(
                    find.byType(AssistantAnswerModeSelector),
                  )
                  .iconOnly,
              isTrue,
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
      await tester.tap(
        find.byKey(const ValueKey('desktop-answer-mode-selector')),
      );
      await tester.pumpAndSettle();
      expect(find.text('下次发送生效'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('assistant-mode-knowledge')));
      await tester.pumpAndSettle();
      expect(controller.allowSmartSupplement(useGlobalMode: true), isFalse);
      expect(controller.sending, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
