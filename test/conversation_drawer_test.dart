import 'support/catalog_fixture.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:board_game_agent/app/state/app_controller.dart';
import 'package:board_game_agent/core/localization/app_language.dart';
import 'package:board_game_agent/core/theme/app_theme.dart';
import 'package:board_game_agent/features/assistant/models/ai_answer_mode.dart';
import 'package:board_game_agent/features/assistant/models/ai_api_config.dart';
import 'package:board_game_agent/features/assistant/models/chat_message.dart';
import 'package:board_game_agent/features/assistant/models/ai_conversation.dart';
import 'package:board_game_agent/features/assistant/models/answer_source.dart';
import 'package:board_game_agent/features/assistant/models/board_game_ai_answer.dart';
import 'package:board_game_agent/features/assistant/services/ai_service.dart';
import 'package:board_game_agent/features/assistant/services/conversation_store.dart';
import 'package:board_game_agent/features/assistant/services/speech_service.dart';
import 'package:board_game_agent/features/assistant/services/tts_service.dart';
import 'package:board_game_agent/features/games/models/game_info.dart';
import 'package:board_game_agent/features/library/models/asset_source_config.dart';
import 'package:board_game_agent/features/library/models/cached_asset.dart';
import 'package:board_game_agent/features/library/models/remote_asset_file.dart';
import 'package:board_game_agent/features/library/services/remote_asset_service.dart';
import 'package:board_game_agent/features/settings/services/preferences_service.dart';
import 'package:board_game_agent/ui/desktop/business_panes.dart';
import 'package:board_game_agent/ui/desktop/theme.dart';
import 'package:board_game_agent/ui/mobile/assistant_chat_screen.dart';
import 'package:board_game_agent/ui/shared/assistant/assistant_motion.dart';
import 'package:board_game_agent/ui/shared/assistant/conversation_search_dialog.dart';
import 'package:board_game_agent/core/localization/app_copy.dart';

void _uiTest(String name, WidgetTesterCallback body, {Timeout? timeout}) {
  testWidgets(name, (tester) async {
    final before = debugDisableShadows;
    try {
      debugDisableShadows = false;
      await body(tester);
    } finally {
      debugDisableShadows = before;
    }
  }, timeout: timeout);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Noto Sans SC',
    )..addFont(rootBundle.load('assets/fonts/NotoSansSC-Variable.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    rootBundle.clear();
  });

  _uiTest('conversation search remains usable with keyboard and large text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.view.viewInsets = FakeViewPadding(
      bottom: 250 * tester.view.devicePixelRatio,
    );
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: ConversationSearchDialog(
          messages: [
            ChatMessage(
              id: 'one',
              role: ChatRole.user,
              text: '战争之匣的规则',
              timestamp: DateTime.utc(2026),
            ),
          ],
          copy: AppCopy(AppLanguage.zhHans),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('assistant-search-query')),
      '战争',
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('assistant-search-result-one')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final desktop in [false, true]) {
    _uiTest(
      'new action reuses an unsent draft and first send preserves the input desktop=$desktop',
      (tester) async {
        final store = _MemoryStore();
        final controller = await _controller(store);
        addTearDown(controller.dispose);
        controller.openGlobalAssistant();
        await _mount(
          tester,
          controller,
          desktop ? const Size(1280, 800) : const Size(320, 700),
          desktop: desktop,
        );
        final initial = controller.selectedConversationId;
        final field = find.byKey(const ValueKey('assistant-draft'));
        final editor = find.descendant(
          of: field,
          matching: find.byType(EditableText),
        );
        await tester.enterText(field, '空白页的草稿');
        final editable = tester.state<EditableTextState>(editor);
        for (var i = 0; i < 3; i++) {
          await tester.tap(
            find.byKey(const ValueKey('assistant-header-new-conversation')),
          );
          await tester.pumpAndSettle();
          expect(controller.selectedConversationId, initial);
          expect(controller.conversations, isEmpty);
          expect(tester.widget<TextField>(field).controller!.text, '空白页的草稿');
        }
        expect(store.writes, 0);
        await controller.saveAiApiConfig(
          controller.aiApiConfig.copyWith(model: 'gpt-5.6-luna'),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(
            ValueKey(
              desktop ? 'desktop-composer-send' : 'assistant-composer-send',
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 40));
        expect(tester.state<EditableTextState>(editor), same(editable));
        await tester.pumpAndSettle();
        expect(controller.conversations, hasLength(1));
        expect(controller.conversations.single.messages.first.text, '空白页的草稿');
        expect(tester.widget<TextField>(field).controller!.text, isEmpty);
        await _capture(tester, 'assistant-first-send-desktop-$desktop');
        await tester.tap(
          find.byKey(const ValueKey('assistant-header-new-conversation')),
        );
        await tester.pumpAndSettle();
        final pending = controller.selectedConversationId;
        expect(pending, isNot(initial));
        await tester.enterText(field, '下一份草稿');
        await tester.tap(
          find.byKey(const ValueKey('assistant-header-new-conversation')),
        );
        await tester.pumpAndSettle();
        expect(controller.selectedConversationId, pending);
        expect(tester.widget<TextField>(field).controller!.text, '下一份草稿');
        expect(controller.conversations, hasLength(1));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    _uiTest(
      'shared header searches and deletes without a clear action desktop=$desktop',
      (tester) async {
        final now = DateTime.utc(2026);
        final conversation = AiConversation(
          id: 'global',
          title: '测试对话',
          scope: AiConversationScope.global,
          createdAt: now,
          updatedAt: now,
          messages: List.generate(
            70,
            (i) => ChatMessage(
              id: 'msg-$i',
              role: ChatRole.user,
              text: i == 2 ? '目标规则在哪里' : '普通消息 $i',
              timestamp: now,
            ),
          ),
        );
        final store = _MemoryStore()
          ..value = jsonEncode({
            'version': 4,
            'selectedConversationId': 'global',
            'conversations': {'global': conversation.toMap()},
          });
        final controller = _buildController(store);
        addTearDown(controller.dispose);
        await tester.runAsync(controller.initialize);
        await _mount(
          tester,
          controller,
          desktop ? const Size(1280, 800) : const Size(390, 844),
          desktop: desktop,
        );
        expect(
          find.byKey(const ValueKey('assistant-header-back')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('assistant-header-share')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('assistant-conversations-trigger')),
          findsOneWidget,
        );
        Future<void> openMenu() async {
          await tester.tap(find.byKey(const ValueKey('assistant-more-menu')));
          await tester.pumpAndSettle();
          expect(find.text('查找'), findsOneWidget);
          expect(find.text('清空'), findsNothing);
          expect(
            find.byKey(const ValueKey('assistant-menu-clear')),
            findsNothing,
          );
          expect(find.text('删除'), findsOneWidget);
          expect(find.text('语音朗读'), findsNothing);
        }

        await openMenu();
        await _capture(tester, 'assistant-actions-desktop-$desktop');
        await tester.tap(find.byKey(const ValueKey('assistant-menu-find')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('assistant-search-query')),
          '目标规则',
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('assistant-search-result-msg-2')),
        );
        for (
          var i = 0;
          i < 100 && find.text('目标规则在哪里').hitTestable().evaluate().isEmpty;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(find.text('目标规则在哪里').hitTestable(), findsOneWidget);
        await openMenu();
        await tester.tap(find.byKey(const ValueKey('assistant-menu-delete')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(controller.selectedConversation!.messages, hasLength(70));
        await openMenu();
        await tester.tap(find.byKey(const ValueKey('assistant-menu-delete')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('assistant-confirm-change')),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
        expect(find.text('操作未完成，请重试'), findsNothing);
        expect(controller.selectedConversationId, isNot('global'));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  _uiTest('game assistant opened as a page has a working back button', (
    tester,
  ) async {
    final controller = await _controller(_MemoryStore());
    addTearDown(controller.dispose);
    controller.openGameAssistant('puerto-rico');
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.buildTheme(controller.palette),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => AssistantChatScreen(controller: controller),
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('assistant-header-back')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('assistant-header-back')));
    await tester.pumpAndSettle();
    expect(find.text('打开'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  _uiTest(
    'compact assistant remains usable with large text and a short viewport',
    (tester) async {
      final controller = await _controller(_MemoryStore());
      addTearDown(controller.dispose);
      controller.openGlobalAssistant();
      await _mount(tester, controller, const Size(320, 600), textScale: 1.5);
      await _capture(tester, 'assistant-small-large-text');
      for (final key in [
        'assistant-conversations-trigger',
        'assistant-header-new-conversation',
        'assistant-more-menu',
      ]) {
        final rect = tester.getRect(find.byKey(ValueKey(key)));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(320));
        expect(rect.height, greaterThanOrEqualTo(48));
      }
      final composer = find.byKey(const ValueKey('assistant-composer-box'));
      final collapsedHeight = tester.getSize(composer).height;
      await tester.enterText(
        find.byKey(const ValueKey('assistant-draft')),
        '战争之匣的回合流程是什么？\n请按行动顺序详细解释，并列出需要注意的规则。',
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(composer).height, greaterThan(collapsedHeight));
      expect(find.byKey(const ValueKey('assistant-prompt-0')), findsNothing);
      await _capture(tester, 'assistant-small-multiline');
      await tester.tap(find.byKey(const ValueKey('assistant-context-button')));
      await tester.pumpAndSettle();
      final contextMenu = tester.getRect(
        find.byKey(const ValueKey('assistant-context-menu')),
      );
      expect(contextMenu.left, greaterThanOrEqualTo(0));
      expect(contextMenu.right, lessThanOrEqualTo(320));
      expect(contextMenu.top, greaterThanOrEqualTo(64));
      await _capture(tester, 'assistant-small-context');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('assistant-more-menu')));
      await tester.pumpAndSettle();
      expect(find.text('清空'), findsNothing);
      await _capture(tester, 'assistant-small-actions');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  _uiTest('header buttons respond to press and return to their original size', (
    tester,
  ) async {
    final controller = await _controller(_MemoryStore());
    addTearDown(controller.dispose);
    controller.openGlobalAssistant();
    await _mount(tester, controller, const Size(320, 700));
    final button = find.byKey(
      const ValueKey('assistant-conversations-trigger'),
    );
    final scale = find
        .ancestor(of: button, matching: find.byType(AnimatedScale))
        .first;
    final gesture = await tester.startGesture(tester.getCenter(button));
    await tester.pump(const Duration(milliseconds: 160));
    expect(tester.widget<AnimatedScale>(scale).scale, lessThan(1));
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedScale>(scale).scale, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'message motion does not restart on a delta and respects reduced motion',
    (tester) async {
      Widget scene(String text, {bool reduced = false}) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: AssistantMessageEntrance(
            key: const ValueKey('one-message'),
            child: Text(text),
          ),
        ),
      );
      await tester.pumpWidget(scene('第一段'));
      await tester.pump(const Duration(milliseconds: 80));
      final opacity = tester.widget<Opacity>(find.byType(Opacity)).opacity;
      expect(opacity, greaterThan(0));
      await tester.pumpWidget(scene('第一段，第二段'));
      expect(
        tester.widget<Opacity>(find.byType(Opacity)).opacity,
        greaterThanOrEqualTo(opacity),
      );
      await tester.pump(const Duration(milliseconds: 160));
      expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1);
      await tester.pumpWidget(scene('关闭动画', reduced: true));
      expect(
        tester
            .widget<TweenAnimationBuilder<double>>(
              find.byType(TweenAnimationBuilder<double>),
            )
            .duration,
        Duration.zero,
      );
      expect(tester.takeException(), isNull);
    },
  );

  test('native snapshots commit and browser snapshots round trip', () async {
    final directory = await Directory.systemTemp.createTemp(
      'conversation-store-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final native = ConversationStore(directory: directory);
    await native.save('{"version":4}');
    await native.save('{"version":4,"conversations":{}}');
    expect(await native.load(), '{"version":4,"conversations":{}}');
    expect(
      await File('${directory.path}/chat_conversations.json.tmp').exists(),
      isFalse,
    );
    const browser = ConversationStore(browserStorage: true);
    await browser.save('{"version":4}');
    expect(await browser.load(), '{"version":4}');
  });

  test(
    'new topics isolate messages and restore alongside v4 conversations',
    () async {
      final store = _MemoryStore();
      final ai = _DelayedAi();
      final controller = await _controller(store, ai: ai);
      controller.openGameAssistant('puerto-rico');
      final legacy = controller.selectedConversationId!;
      final first = await controller.createConversation(useGlobalMode: false);
      await controller.saveAiApiConfig(
        controller.aiApiConfig.copyWith(model: 'gpt-5.6-luna'),
      );
      final response = controller.sendPrompt('建筑如何计分？');
      await ai.started.future;
      expect(ai.requestedConversationId, first);
      ai.events.add(const BoardGameAiStreamEvent(delta: '部分答案'));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final second = await controller.createConversation(useGlobalMode: false);
      ai.events.add(const BoardGameAiStreamEvent(delta: '旧请求迟到的内容'));
      await ai.events.close();
      await response;
      expect(controller.messagesForContext(useGlobalMode: false), isEmpty);
      controller.selectConversation(first);
      expect(
        controller.messagesForContext(useGlobalMode: false).first.text,
        '建筑如何计分？',
      );
      expect(controller.conversations, hasLength(1));
      expect(
        controller
            .messagesForContext(useGlobalMode: false)
            .map((m) => m.text)
            .join(),
        isNot(contains('迟到')),
      );
      controller.selectConversation(second);
      expect(controller.messagesForContext(useGlobalMode: false), isEmpty);
      expect(first, legacy);
      expect(await controller.createConversation(useGlobalMode: false), second);
      await controller.disposeServices();
      controller.dispose();
      final restored = _buildController(store);
      await restored.initialize();
      // Let the startup warm-up finish before disposing its controller.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(restored.selectedConversationId, first);
      expect(restored.conversations.map((c) => c.id), [first]);
      restored.selectConversation(first);
      expect(restored.selectedConversation!.messages.first.text, '建筑如何计分？');
      await restored.disposeServices();
      restored.dispose();
    },
  );

  test(
    'repeated new actions remain transient until a valid nonempty send',
    () async {
      final store = _MemoryStore();
      final controller = await _controller(store);
      addTearDown(controller.dispose);
      controller.openGlobalAssistant();
      final drafts = await Future.wait(
        List.generate(
          12,
          (_) => controller.createConversation(useGlobalMode: true),
        ),
      );
      expect(drafts.toSet(), hasLength(1));
      expect(controller.conversations, isEmpty);
      await controller.sendPrompt('   ', useGlobalMode: true);
      await controller.sendPrompt('尚未选择模型', useGlobalMode: true);
      expect(controller.conversations, isEmpty);
      expect(store.writes, 0);
      controller.messagesForContext(useGlobalMode: false);
      await _submitQuestion(controller, useGlobalMode: true);
      await controller.prepareForAppUpdate();
      expect(controller.conversations, hasLength(1));
      expect(controller.selectedConversationId, drafts.first);
      final snapshot = jsonDecode(store.value!) as Map;
      expect((snapshot['conversations'] as Map).keys, [drafts.first]);
      final writes = store.writes;
      final next = await controller.createConversation(useGlobalMode: true);
      expect(next, isNot(drafts.first));
      expect(await controller.createConversation(useGlobalMode: true), next);
      expect(controller.conversations, hasLength(1));
      expect(store.writes, writes);
      controller.selectConversation(drafts.first);
      expect(await controller.createConversation(useGlobalMode: true), next);
      expect(controller.messagesForContext(useGlobalMode: true), isEmpty);
      await controller.disposeServices();
    },
  );

  test(
    'deletion is durable, keeps failed writes retryable and isolates late deltas',
    () async {
      final store = _usedConversationStore();
      final ai = _DelayedAi();
      final controller = await _controller(store, ai: ai);
      await controller.initialize();
      controller.openGlobalAssistant();
      final first = controller.selectedConversationId!;
      final current = await controller.createConversation(useGlobalMode: true);
      await controller.saveAiApiConfig(
        controller.aiApiConfig.copyWith(model: 'gpt-5.6-luna'),
      );
      store.fail = true;
      await expectLater(controller.deleteConversation(first), throwsStateError);
      expect(controller.conversations.map((item) => item.id), contains(first));
      expect(controller.selectedConversationId, current);
      store.fail = false;
      await controller.deleteConversation(first);
      expect(controller.selectedConversationId, current);
      final response = controller.sendPrompt('测试中途删除', useGlobalMode: true);
      await ai.started.future;
      ai.events.add(const BoardGameAiStreamEvent(delta: '部分内容'));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await controller.deleteConversation(current);
      final fresh = controller.selectedConversationId!;
      expect(fresh, isNot(current));
      expect(controller.conversations, isEmpty);
      expect(controller.selectedConversation!.messages, isEmpty);
      ai.events.add(const BoardGameAiStreamEvent(delta: '已删除请求的迟到内容'));
      await ai.events.close();
      await response;
      await controller.disposeServices();
      controller.dispose();
      final snapshot = jsonDecode(store.value!) as Map<String, dynamic>;
      expect((snapshot['conversations'] as Map), isEmpty);
      final restored = _buildController(store);
      await restored.initialize();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(restored.selectedConversationId, isNull);
      expect(restored.conversations, isEmpty);
      await restored.disposeServices();
      restored.dispose();
    },
  );

  for (final desktop in [false, true]) {
    _uiTest(
      'delete entry confirms, retries and clears deleted drafts desktop=$desktop',
      (tester) async {
        final store = _MemoryStore();
        final controller = await _controller(store);
        addTearDown(controller.dispose);
        controller.openGlobalAssistant();
        await _submitQuestion(controller, useGlobalMode: true);
        final deleted = controller.selectedConversationId!;
        await _mount(
          tester,
          controller,
          desktop ? const Size(1280, 800) : const Size(320, 700),
          desktop: desktop,
        );
        await tester.enterText(
          find.byKey(const ValueKey('assistant-draft')),
          '不能恢复的已删除草稿',
        );
        final drawer = find.byKey(
          const ValueKey('assistant-conversations-trigger'),
        );
        await tester.tap(drawer);
        await tester.pumpAndSettle();
        final remove = find.byKey(
          ValueKey('assistant-delete-conversation-$deleted'),
        );
        await tester.tap(remove);
        await tester.pumpAndSettle();
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(controller.selectedConversationId, deleted);
        store.fail = true;
        await tester.tap(remove);
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('assistant-confirm-delete')),
        );
        await tester.pumpAndSettle();
        expect(find.text('删除失败，会话已保留，请重试。'), findsOneWidget);
        expect(controller.selectedConversationId, deleted);
        store.fail = false;
        await tester.tap(remove);
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('assistant-confirm-delete')),
        );
        await tester.pumpAndSettle();
        expect(remove, findsNothing);
        expect(controller.selectedConversationId, isNot(deleted));
        await _capture(
          tester,
          desktop
              ? 'desktop-delete-conversation'
              : 'compact-delete-conversation',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        controller.openGlobalAssistant();
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('assistant-draft')))
              .controller!
              .text,
          isEmpty,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  _uiTest(
    'desktop answer copies to clipboard and hides unavailable speech',
    (tester) async {
      final ai = _DelayedAi(honorAbort: true);
      final controller = await _controller(_MemoryStore(), ai: ai);
      addTearDown(controller.dispose);
      controller.openGlobalAssistant();
      await controller.saveAiApiConfig(
        controller.aiApiConfig.copyWith(model: 'gpt-5.6-luna'),
      );
      String? clipboard;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await _mount(tester, controller, const Size(1280, 800), desktop: true);
      final response = controller.sendPrompt('验证复制', useGlobalMode: true);
      await ai.started.future;
      ai.events.add(const BoardGameAiStreamEvent(delta: '保留的答案内容'));
      await tester.pump(const Duration(milliseconds: 250));
      await controller.stopGenerating(useGlobalMode: true);
      await tester.pump(const Duration(milliseconds: 250));
      await response;
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.volume_up_rounded), findsNothing);
      await tester.tap(find.text(controller.copy.copyAnswer));
      await tester.pumpAndSettle();
      expect(clipboard, '保留的答案内容');
      expect(find.text(controller.copy.answerCopied), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'AI stop finishes in fake time before delayed provider cleanup',
    (tester) async {
      final cleanup = Completer<void>();
      var cancellations = 0;
      final ai = _DelayedAi(
        onCancel: () {
          cancellations++;
          return cleanup.future;
        },
      );
      final controller = await _controller(_MemoryStore(), ai: ai);
      addTearDown(controller.dispose);
      await controller.saveAiApiConfig(
        controller.aiApiConfig.copyWith(model: 'gpt-5.6-luna'),
      );
      final response = controller.sendPrompt('取消回归', useGlobalMode: true);
      var finished = false;
      response.then((_) => finished = true);
      await ai.started.future;
      ai.events.add(const BoardGameAiStreamEvent(delta: '保留部分内容'));
      await tester.pump(const Duration(milliseconds: 20));
      await controller.stopGenerating(useGlobalMode: true);
      await tester.pump();
      expect(finished, isTrue);
      expect(cancellations, 1);
      expect(cleanup.isCompleted, isFalse);
      expect(controller.isSendingForContext(useGlobalMode: true), isFalse);
      expect(
        controller.messagesForContext(useGlobalMode: true).last.text,
        '保留部分内容',
      );
      ai.events.add(const BoardGameAiStreamEvent(delta: '迟到输出'));
      await tester.pump();
      expect(
        controller.messagesForContext(useGlobalMode: true).last.text,
        '保留部分内容',
      );
      cleanup.complete();
      await tester.pump();
      await response;
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'AI normal stream close finishes without recancelling its source',
    (tester) async {
      var cancellations = 0;
      final ai = _DelayedAi(
        onCancel: () {
          cancellations++;
        },
      );
      final controller = await _controller(_MemoryStore(), ai: ai);
      addTearDown(controller.dispose);
      await controller.saveAiApiConfig(
        controller.aiApiConfig.copyWith(model: 'gpt-5.6-luna'),
      );
      var finished = false;
      final response = controller.sendPrompt('完成回归', useGlobalMode: true);
      response.then((_) => finished = true);
      await ai.started.future;
      ai.events.add(
        BoardGameAiStreamEvent(
          answer: BoardGameAiAnswer(
            text: '完整回答',
            source: AnswerSource.generalAdvice,
          ),
          isDone: true,
        ),
      );
      unawaited(ai.events.close());
      await tester.pump();
      expect(finished, isTrue);
      expect(cancellations, 1);
      expect(
        controller.messagesForContext(useGlobalMode: true).last.text,
        '完整回答',
      );
      await response;
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  _uiTest('phone drawer switches scope and restores drafts at 320px', (
    tester,
  ) async {
    final store = _MemoryStore();
    final controller = await _controller(store);
    addTearDown(controller.dispose);
    controller.openGameAssistant('puerto-rico');
    await _submitQuestion(controller);
    final game = controller.selectedConversationId!;
    controller.openGlobalAssistant();
    await _submitQuestion(controller, useGlobalMode: true);
    await _mount(tester, controller, const Size(320, 700));
    await tester.enterText(find.byType(TextField).first, '通用草稿');
    await tester.tap(
      find.byKey(const ValueKey('assistant-conversations-trigger')),
    );
    await tester.pumpAndSettle();
    final panel = find.byKey(const ValueKey('assistant-conversation-drawer'));
    expect(tester.getRect(panel).left, 12);
    expect(tester.getSize(panel).width, 274);
    await _capture(tester, 'phone-drawer');
    await tester.tap(find.byKey(ValueKey('assistant-conversation-$game')));
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
    expect(controller.selectedConversationIsGlobal, isFalse);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      isEmpty,
    );
    await tester.enterText(find.byType(TextField).first, '桌游草稿');
    await tester.tap(
      find.byKey(const ValueKey('assistant-conversations-trigger')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('assistant-conversation-global')),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      '通用草稿',
    );
    await tester.tap(
      find.byKey(const ValueKey('assistant-conversations-trigger')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('assistant-new-conversation')));
    await tester.pumpAndSettle();
    expect(controller.selectedConversationId, startsWith('conversation:'));
    expect(controller.selectedConversationIsGlobal, isTrue);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      isEmpty,
    );
    expect(controller.conversations, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  _uiTest(
    'unsent workspace needs no record write and escape restores the page',
    (tester) async {
      final store = _MemoryStore();
      final controller = await _controller(store);
      addTearDown(controller.dispose);
      controller.openGlobalAssistant();
      await _mount(tester, controller, const Size(390, 844));
      store.fail = true;
      await tester.tap(
        find.byKey(const ValueKey('assistant-conversations-trigger')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('assistant-new-conversation')),
      );
      await tester.pumpAndSettle();
      expect(find.text(controller.copy.conversationSaveFailed), findsNothing);
      expect(controller.selectedConversationId, 'global');
      expect(controller.conversations, isEmpty);
      await tester.tap(
        find.byKey(const ValueKey('assistant-conversations-trigger')),
      );
      await tester.pumpAndSettle();
      store.fail = false;
      await tester.tap(
        find.byKey(const ValueKey('assistant-new-conversation')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('assistant-conversation-drawer')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const ValueKey('assistant-conversations-trigger')),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('assistant-conversation-drawer')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(720, 700), const Size(1280, 800)]) {
    _uiTest('desktop drawer fits scaled English text at $size', (tester) async {
      final controller = await _controller(_MemoryStore());
      addTearDown(controller.dispose);
      controller.openGlobalAssistant();
      controller.openGameAssistant('puerto-rico');
      await controller.setLanguage(AppLanguage.en);
      await _mount(tester, controller, size, desktop: true);
      expect(
        find.byKey(const ValueKey('assistant-header-share')),
        findsNothing,
      );
      if (size.width == 1280) await _capture(tester, 'assistant-desktop');
      await tester.tap(
        find.byKey(const ValueKey('assistant-conversations-trigger')),
      );
      await tester.pumpAndSettle();
      final panel = find.byKey(const ValueKey('assistant-conversation-drawer'));
      expect(tester.getRect(panel).right, lessThan(size.width));
      expect(tester.getRect(panel).bottom, lessThan(size.height));
      expect(find.text('New chat'), findsOneWidget);
      for (final paragraph in tester.renderObjectList<RenderParagraph>(
        find.descendant(of: panel, matching: find.byType(RichText)),
      )) {
        expect(paragraph.didExceedMaxLines, isFalse);
      }
      if (size.width == 1280) await _capture(tester, 'desktop-drawer');
      await tester.tapAt(Offset(size.width - 18, 100));
      await tester.pumpAndSettle();
      expect(panel, findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final language in [AppLanguage.zhHans, AppLanguage.en]) {
    _uiTest('compact assistant draft and picker adapt in $language', (
      tester,
    ) async {
      final controller = await _controller(_MemoryStore());
      addTearDown(controller.dispose);
      controller.openGlobalAssistant();
      await controller.setLanguage(language);
      await controller.saveAiApiConfig(
        controller.aiApiConfig.copyWith(model: 'gpt-5.6-luna'),
      );
      await _mount(tester, controller, const Size(390, 844));
      await _capture(tester, 'assistant-compact-${language.name}');
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('assistant-prompt-0')),
          matching: find.byType(InkWell),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.selectedConversation!.messages, isEmpty);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('assistant-draft')))
            .controller!
            .text,
        isNotEmpty,
      );
      tester.view.viewInsets = FakeViewPadding(
        bottom: 180 * tester.view.devicePixelRatio,
      );
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('desktop-model-selector')));
      await tester.pumpAndSettle();
      final panel = find.byKey(const ValueKey('desktop-model-picker-panel'));
      expect(panel, findsOneWidget);
      expect(
        find.byKey(const ValueKey('desktop-reasoning-option-none')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('desktop-reasoning-option-automatic')),
        findsNothing,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('desktop-reasoning-option-high')),
      );
      await tester.tap(
        find.byKey(const ValueKey('desktop-reasoning-option-high')),
      );
      await tester.pumpAndSettle();
      expect(controller.aiApiConfig.reasoningEffort, AiReasoningEffort.high);
      await tester.ensureVisible(
        find.byKey(const ValueKey('assistant-service-tier-fast')),
      );
      await tester.tap(
        find.byKey(const ValueKey('assistant-service-tier-fast')),
      );
      await tester.pumpAndSettle();
      expect(controller.aiApiConfig.responseSpeed, AiResponseSpeed.fast);
      tester.view.viewInsets = FakeViewPadding(
        bottom: 300 * tester.view.devicePixelRatio,
      );
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      final rect = tester.getRect(panel);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(390));
      expect(rect.bottom, lessThanOrEqualTo(544));
      await tester.binding.setSurfaceSize(const Size(320, 600));
      await tester.pumpAndSettle();
      expect(tester.getRect(panel).right, lessThanOrEqualTo(320));
      expect(tester.getRect(panel).bottom, lessThanOrEqualTo(300));
      expect(tester.takeException(), isNull);
    });
  }

  _uiTest(
    'shared composer stops a real pending stream and keeps partial text',
    (tester) async {
      final ai = _DelayedAi(honorAbort: true);
      final controller = await _controller(_MemoryStore(), ai: ai);
      addTearDown(controller.dispose);
      controller.openGlobalAssistant();
      await controller.saveAiApiConfig(
        controller.aiApiConfig.copyWith(model: 'gpt-5.6-luna'),
      );
      await _mount(tester, controller, const Size(390, 844));
      await tester.enterText(
        find.byKey(const ValueKey('assistant-draft')),
        '回合顺序是什么？',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('assistant-composer-send')));
      await tester.pump(const Duration(milliseconds: 250));
      expect(ai.started.isCompleted, isTrue);
      expect(controller.isSendingForContext(useGlobalMode: true), isTrue);
      ai.events.add(const BoardGameAiStreamEvent(delta: '这是部分答案'));
      await tester.pump(const Duration(milliseconds: 250));
      await _capture(tester, 'assistant-compact-stream');
      await tester.tap(find.byKey(const ValueKey('assistant-composer-send')));
      await tester.pump(const Duration(milliseconds: 250));
      expect(controller.isSendingForContext(useGlobalMode: true), isFalse);
      expect(
        controller.messagesForContext(useGlobalMode: true).last.text,
        contains('这是部分答案'),
      );
      await ai.events.close();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _mount(
  WidgetTester tester,
  AppController controller,
  Size size, {
  bool desktop = false,
  double textScale = 1.25,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('conversation-capture'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: desktop
            ? buildDesktopTheme()
            : AppTheme.buildTheme(controller.palette),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: desktop
            ? Scaffold(body: DesktopAssistantPane(controller: controller))
            : AssistantChatScreen(controller: controller, useGlobalMode: true),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String name) async {
  final output = Platform.environment['CONVERSATION_UI_CAPTURE_DIR'];
  if (output == null) return;
  final context = tester.element(find.byType(Scaffold).first);
  final providers = tester
      .widgetList<Image>(find.byType(Image))
      .map((image) => image.image)
      .toList();
  await tester.runAsync(() async {
    await Future.wait(
      providers.map((provider) => precacheImage(provider, context)),
    );
  });
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('conversation-capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ImageByteFormat.png);
    await Directory(output).create(recursive: true);
    await File('$output/$name.png').writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

Future<AppController> _controller(_MemoryStore store, {AiService? ai}) async {
  final controller = _buildController(store, ai: ai);
  await controller.reloadGames();
  return controller;
}

Future<void> _submitQuestion(
  AppController controller, {
  bool useGlobalMode = false,
}) async {
  await controller.saveAiApiConfig(
    controller.aiApiConfig.copyWith(model: 'gpt-5.6-luna'),
  );
  await controller.sendPrompt('已发送的问题', useGlobalMode: useGlobalMode);
}

_MemoryStore _usedConversationStore() {
  final now = DateTime.utc(2026);
  final conversation = AiConversation(
    id: 'global',
    title: '已有对话',
    scope: AiConversationScope.global,
    createdAt: now,
    updatedAt: now,
    messages: [
      ChatMessage(
        id: 'existing-user',
        role: ChatRole.user,
        text: '原有问题',
        timestamp: now,
      ),
    ],
  );
  return _MemoryStore()
    ..value = jsonEncode({
      'version': 4,
      'selectedConversationId': 'global',
      'conversations': {'global': conversation.toMap()},
    });
}

AppController _buildController(_MemoryStore store, {AiService? ai}) =>
    AppController(
      preferencesService: PreferencesService(),
      aiService: ai ?? _ImmediateAi(),
      gameManifestService: FixtureGameManifestService(),
      remoteAssetService: _NoNetwork(),
      speechService: SpeechService(),
      ttsService: _SilentTts(),
      conversationStore: store,
    );

class _MemoryStore extends ConversationStore {
  String? value;
  bool fail = false;
  int writes = 0;
  @override
  Future<String?> load() async => value;
  @override
  Future<void> save(String payload) async {
    if (fail) throw StateError('test write failure');
    ++writes;
    value = payload;
    jsonDecode(payload);
  }
}

class _UnusedAi extends Fake implements AiService {
  @override
  void dispose() {}
}

class _ImmediateAi extends _UnusedAi {
  @override
  Stream<BoardGameAiStreamEvent> streamReply({
    required String prompt,
    required AppLanguage language,
    required GameInfo game,
    required AiAnswerMode answerMode,
    required bool useGlobalMode,
    required AiApiConfig config,
    required List<AssetSourceConfig> assetSourceConfigs,
    required RemoteAssetService remoteAssetService,
    required List<ChatMessage> conversationHistory,
    String? conversationId,
    bool useCurrentGameKnowledge = false,
    Future<void>? abortTrigger,
  }) => Stream.value(
    BoardGameAiStreamEvent(
      answer: BoardGameAiAnswer(
        text: '已完成的回答',
        source: AnswerSource.generalAdvice,
      ),
      isDone: true,
    ),
  );
}

class _DelayedAi extends _UnusedAi {
  _DelayedAi({this.honorAbort = false, FutureOr<void> Function()? onCancel})
    : events = StreamController<BoardGameAiStreamEvent>(onCancel: onCancel);
  final bool honorAbort;
  final StreamController<BoardGameAiStreamEvent> events;
  final started = Completer<void>();
  String? requestedConversationId;
  @override
  Stream<BoardGameAiStreamEvent> streamReply({
    required String prompt,
    required AppLanguage language,
    required GameInfo game,
    required AiAnswerMode answerMode,
    required bool useGlobalMode,
    required AiApiConfig config,
    required List<AssetSourceConfig> assetSourceConfigs,
    required RemoteAssetService remoteAssetService,
    required List<ChatMessage> conversationHistory,
    String? conversationId,
    bool useCurrentGameKnowledge = false,
    Future<void>? abortTrigger,
  }) {
    requestedConversationId = conversationId;
    if (honorAbort && abortTrigger != null) {
      unawaited(
        abortTrigger.then((_) async {
          if (!events.isClosed) await events.close();
        }),
      );
    }
    if (!started.isCompleted) started.complete();
    return events.stream;
  }
}

class _SilentTts extends TtsService {
  @override
  bool get isAvailable => false;
  @override
  Future<void> initialize(AppLanguage language) async {}
  @override
  Future<void> setLanguage(AppLanguage language) async {}
  @override
  Future<void> stop() async {}
}

class _NoNetwork extends RemoteAssetService {
  @override
  Future<List<RemoteAssetFile>> listFilesRecursively({
    required List<AssetSourceConfig> sources,
    required String remotePath,
    int maxDepth = 6,
    int maxEntries = 1000,
  }) async => [];
  @override
  Future<File?> cachedFileFor(String path) async => null;
  @override
  Future<CachedAsset?> ensureCached({
    required List<AssetSourceConfig> sources,
    required String remotePath,
    bool forceRefresh = false,
    bool allowCachedFallback = true,
  }) async => null;
  @override
  Future<String?> fetchRemoteText({
    required List<AssetSourceConfig> sources,
    required String remotePath,
  }) async => null;
}
