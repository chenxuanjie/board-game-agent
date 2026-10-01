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
import 'package:board_game_agent/features/assistant/services/ai_service.dart';
import 'package:board_game_agent/features/assistant/services/conversation_store.dart';
import 'package:board_game_agent/features/assistant/services/speech_service.dart';
import 'package:board_game_agent/features/assistant/services/tts_service.dart';
import 'package:board_game_agent/features/games/models/game_info.dart';
import 'package:board_game_agent/features/games/services/game_manifest_service.dart';
import 'package:board_game_agent/features/library/models/asset_source_config.dart';
import 'package:board_game_agent/features/library/models/cached_asset.dart';
import 'package:board_game_agent/features/library/models/remote_asset_file.dart';
import 'package:board_game_agent/features/library/services/remote_asset_service.dart';
import 'package:board_game_agent/features/settings/services/preferences_service.dart';
import 'package:board_game_agent/ui/desktop/business_panes.dart';
import 'package:board_game_agent/ui/desktop/theme.dart';
import 'package:board_game_agent/ui/mobile/assistant_chat_screen.dart';
import 'package:board_game_agent/ui/shared/assistant/assistant_motion.dart';

void _uiTest(String name, WidgetTesterCallback body) {
  testWidgets(name, (tester) async {
    final before = debugDisableShadows;
    try {
      debugDisableShadows = false;
      await body(tester);
    } finally {
      debugDisableShadows = before;
    }
  });
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
      expect(controller.selectedConversation!.title, '建筑如何计分？');
      expect(
        controller
            .messagesForContext(useGlobalMode: false)
            .map((m) => m.text)
            .join(),
        isNot(contains('迟到')),
      );
      controller.selectConversation(legacy);
      expect(controller.messagesForContext(useGlobalMode: false), isEmpty);
      controller.selectConversation(second);
      await controller.disposeServices();
      controller.dispose();
      final restored = _buildController(store);
      await restored.initialize();
      // Let the startup warm-up finish before disposing its controller.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(restored.selectedConversationId, second);
      expect(
        restored.conversations.map((c) => c.id),
        containsAll([legacy, first, second]),
      );
      restored.selectConversation(first);
      expect(restored.selectedConversation!.messages.first.text, '建筑如何计分？');
      await restored.disposeServices();
      restored.dispose();
    },
  );

  _uiTest('phone drawer switches scope and restores drafts at 320px', (
    tester,
  ) async {
    final store = _MemoryStore();
    final controller = await _controller(store);
    addTearDown(controller.dispose);
    controller.openGameAssistant('puerto-rico');
    final game = controller.selectedConversationId!;
    controller.openGlobalAssistant();
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
    expect(controller.conversations, hasLength(3));
    expect(tester.takeException(), isNull);
  });

  _uiTest('save failure stays retryable and escape restores the page', (
    tester,
  ) async {
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
    await tester.tap(find.byKey(const ValueKey('assistant-new-conversation')));
    await tester.pumpAndSettle();
    expect(find.text(controller.copy.conversationSaveFailed), findsOneWidget);
    expect(controller.selectedConversationId, 'global');
    expect(controller.conversations, hasLength(1));
    store.fail = false;
    await tester.tap(find.byKey(const ValueKey('assistant-new-conversation')));
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
  });

  for (final size in [const Size(720, 700), const Size(1280, 800)]) {
    _uiTest('desktop drawer fits scaled English text at $size', (tester) async {
      final controller = await _controller(_MemoryStore());
      addTearDown(controller.dispose);
      controller.openGlobalAssistant();
      controller.openGameAssistant('puerto-rico');
      await controller.setLanguage(AppLanguage.en);
      await _mount(tester, controller, size, desktop: true);
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
      await tester.tap(find.byKey(const ValueKey('assistant-prompt-0')));
      await tester.pumpAndSettle();
      expect(controller.selectedConversation!.messages, isEmpty);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('assistant-draft')))
            .controller!
            .text,
        isNotEmpty,
      );
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
          ).copyWith(textScaler: const TextScaler.linear(1.25)),
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

AppController _buildController(_MemoryStore store, {AiService? ai}) =>
    AppController(
      preferencesService: PreferencesService(),
      aiService: ai ?? _UnusedAi(),
      gameManifestService: GameManifestService(),
      remoteAssetService: _NoNetwork(),
      speechService: SpeechService(),
      ttsService: _SilentTts(),
      conversationStore: store,
    );

class _MemoryStore extends ConversationStore {
  String? value;
  bool fail = false;
  @override
  Future<String?> load() async => value;
  @override
  Future<void> save(String payload) async {
    if (fail) throw StateError('test write failure');
    value = payload;
    jsonDecode(payload);
  }
}

class _UnusedAi extends Fake implements AiService {
  @override
  void dispose() {}
}

class _DelayedAi extends _UnusedAi {
  _DelayedAi({this.honorAbort = false});
  final bool honorAbort;
  final events = StreamController<BoardGameAiStreamEvent>();
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
