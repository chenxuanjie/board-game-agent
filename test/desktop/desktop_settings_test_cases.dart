part of '../desktop_workspace_test.dart';

class _DesktopSettingsTestContext {
  const _DesktopSettingsTestContext({
    required AppController Function() controller,
    required _InMemoryPreferencesService Function() preferences,
  }) : _controller = controller,
       _preferences = preferences;

  final AppController Function() _controller;
  final _InMemoryPreferencesService Function() _preferences;

  AppController get controller => _controller();
  _InMemoryPreferencesService get preferences => _preferences();
}

void _registerDesktopSettingsTests(_DesktopSettingsTestContext context) {
  testWidgets('settings keeps AI configuration inline and invokes About', (
    tester,
  ) async {
    var aboutCalls = 0;
    await _mount(
      tester,
      context.controller,
      const Size(1280, 800),
      onOpenAbout: () => aboutCalls++,
    );
    await _navigate(tester, '设置');
    await tester.ensureVisible(find.text('关于应用'));
    await tester.tap(find.text('关于应用'));
    await tester.pumpAndSettle();
    expect(aboutCalls, 1);
    expect(find.byType(DesktopSettingsPane), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('desktop-settings-ai-save-check')),
      findsOneWidget,
    );
    expect(find.text('详细设置'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'settings controls reflect real state and disable unsupported actions',
    (tester) async {
      await context.controller.saveAiApiConfig(
        context.controller.aiApiConfig.copyWith(
          apiKey: 'test-secret-key',
          model: 'gpt-5.6-sol',
        ),
      );
      expect(context.preferences._aiApiConfig?.apiKey, 'test-secret-key');
      await _mount(tester, context.controller, const Size(1280, 800));
      await _navigate(tester, '设置');

      final Finder apiKeyField = find.byKey(
        const ValueKey<String>('desktop-settings-ai-api-key'),
      );
      expect(tester.widget<TextField>(apiKeyField).obscureText, isTrue);
      await tester.tap(find.byTooltip('显示 API Key'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(apiKeyField).obscureText, isFalse);
      expect(
        tester.widget<TextField>(apiKeyField).controller?.text,
        'test-secret-key',
      );

      final Finder updateSwitchRow = find.byKey(
        const ValueKey<String>('desktop-settings-startup-update-check'),
      );
      final Switch updateSwitch = tester.widget<Switch>(
        find.descendant(of: updateSwitchRow, matching: find.byType(Switch)),
      );
      expect(updateSwitch.onChanged, isNotNull);
      await tester.tap(
        find.descendant(of: updateSwitchRow, matching: find.byType(Switch)),
      );
      await tester.pumpAndSettle();
      expect(context.controller.checkForUpdates, isFalse);
      expect(context.preferences._checkForUpdates, isFalse);

      final Finder voiceSwitchRow = find.byKey(
        const ValueKey<String>('desktop-settings-voice-reply'),
      );
      final Switch voiceSwitch = tester.widget<Switch>(
        find.descendant(of: voiceSwitchRow, matching: find.byType(Switch)),
      );
      expect(voiceSwitch.onChanged, isNull);

      final Finder nightTheme = find.byKey(
        ValueKey<String>(
          'desktop-settings-theme-${ColorSchemeOption.classic.code}',
        ),
      );
      await tester.tap(nightTheme);
      await tester.pumpAndSettle();
      expect(context.preferences._colorScheme, ColorSchemeOption.classic);

      final Finder warmwoodTheme = find.byKey(
        ValueKey<String>(
          'desktop-settings-theme-${ColorSchemeOption.warmwoodStudy.code}',
        ),
      );
      await tester.tap(warmwoodTheme);
      await tester.pumpAndSettle();
      expect(context.controller.colorScheme, ColorSchemeOption.warmwoodStudy);
      expect(context.preferences._colorScheme, ColorSchemeOption.warmwoodStudy);

      expect(find.byType(Slider), findsNothing);
      expect(find.text('立即同步'), findsNothing);
      expect(find.text('恢复默认设置'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('desktop AI card exposes provider and discovered-model menus', (
    tester,
  ) async {
    await _mount(tester, context.controller, const Size(1280, 800));
    await _navigate(tester, '设置');

    for (final key in <String>[
      'desktop-settings-ai-provider',
      'desktop-settings-ai-model',
    ]) {
      final field = find.descendant(
        of: find.byKey(ValueKey<String>(key)),
        matching: find.byType(DropdownButtonFormField<String>),
      );
      expect(field, findsOneWidget);
      final dropdown = find.descendant(
        of: field,
        matching: find.byType(DropdownButton<String>),
      );
      expect(
        tester.widget<DropdownButton<String>>(dropdown).borderRadius,
        BorderRadius.circular(12),
      );
    }
    await tester.enterText(
      find.byKey(const ValueKey<String>('desktop-settings-ai-api-key')),
      'desktop-secret',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('desktop-settings-ai-base-url')),
      'https://desktop.example/v1',
    );
    expect(
      find.byKey(const ValueKey<String>('desktop-settings-ai-save-check')),
      findsOneWidget,
    );
    expect(find.text('详细设置'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop WebDAV settings save into the shared backend', (
    tester,
  ) async {
    final _MemoryWebDavSettingsStore store = _MemoryWebDavSettingsStore(
      const WebDavSettings(
        mode: ExternalStorageMode.webDav,
        baseUrl: 'https://old.example.com/friend/',
        username: 'old-user',
        password: 'old-password',
      ),
    );
    final WebDavSettingsController webDav = WebDavSettingsController(
      store: store,
      connectionTester: const _SuccessfulWebDavConnectionTester(),
    );
    await webDav.load();
    addTearDown(webDav.dispose);

    await _mount(
      tester,
      context.controller,
      const Size(1280, 800),
      webDavSettingsController: webDav,
    );
    await _navigate(tester, '设置');

    final Finder saveButton = find.byKey(
      const ValueKey<String>('desktop-settings-check-resource-sources'),
    );
    await tester.ensureVisible(saveButton);
    await tester.enterText(
      find.byKey(const ValueKey<String>('desktop-settings-webdav-url')),
      'https://dav.example.com/friend/',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('desktop-settings-webdav-username')),
      'desktop-user',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('desktop-settings-webdav-password')),
      'desktop-password',
    );
    await tester.tap(saveButton);
    await tester.pump();
    for (
      int attempt = 0;
      attempt < 20 &&
          find
              .byKey(const ValueKey<String>('desktop-settings-webdav-feedback'))
              .evaluate()
              .isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(store.value?.baseUrl, 'https://dav.example.com/friend/');
    expect(store.value?.username, 'desktop-user');
    expect(store.value?.password, 'desktop-password');
    expect(context.controller.assetSourceConfigs, hasLength(1));
    expect(
      context.controller.assetSourceConfigs.single.testUrl,
      'https://dav.example.com/friend/',
    );
  });

  test(
    'desktop AI settings service persists and checks all card fields',
    () async {
      final List<DesktopAiCheckStep> steps = <DesktopAiCheckStep>[];
      final DesktopAiSettingsResult result =
          await DesktopAiSettingsService(context.controller).saveAndCheck(
            const DesktopAiSettingsDraft(
              provider: 'Desktop Provider',
              model: 'gpt-5.6-sol',
              apiKey: 'desktop-secret',
              baseUrl: 'https://desktop.example/v1',
              reasoningEffort: AiReasoningEffort.high,
              responseSpeed: AiResponseSpeed.fast,
            ),
            onProgress: steps.add,
          );

      expect(result.connected, isTrue);
      expect(context.controller.aiApiConfig.name, 'Desktop Provider');
      expect(context.controller.aiApiConfig.model, 'gpt-5.6-sol');
      expect(context.controller.aiApiConfig.apiKey, 'desktop-secret');
      expect(
        context.controller.aiApiConfig.reasoningEffort,
        AiReasoningEffort.high,
      );
      expect(
        context.controller.aiApiConfig.responseSpeed,
        AiResponseSpeed.fast,
      );
      expect(steps, <DesktopAiCheckStep>[
        DesktopAiCheckStep.saving,
        DesktopAiCheckStep.loadingModels,
        DesktopAiCheckStep.probingChat,
      ]);
      expect(
        context.controller.aiApiConfig.baseUrl,
        'https://desktop.example/v1',
      );
      expect(context.preferences._aiApiConfig?.name, 'Desktop Provider');
      expect(
        context.controller.aiConnectivityStatus.state,
        ConnectivityState.success,
      );
    },
  );

  testWidgets('desktop AI card shows model-specific effort and Fast controls', (
    tester,
  ) async {
    await context.controller.saveAiApiConfig(
      context.controller.aiApiConfig.copyWith(model: 'gpt-6-astra'),
    );
    await _mount(tester, context.controller, const Size(1280, 800));
    await _navigate(tester, '设置');

    final Finder effort = find.descendant(
      of: find.byKey(const ValueKey<String>('desktop-settings-ai-reasoning')),
      matching: find.byType(DropdownButtonFormField<AiReasoningEffort>),
    );
    final Finder speed = find.descendant(
      of: find.byKey(const ValueKey<String>('desktop-settings-ai-speed')),
      matching: find.byType(DropdownButtonFormField<AiResponseSpeed>),
    );
    expect(effort, findsOneWidget);
    expect(speed, findsOneWidget);
    await tester.ensureVisible(effort);
    await tester.tap(effort);
    await tester.pumpAndSettle();
    expect(find.text('无'), findsNothing);
    expect(find.text('最高'), findsWidgets);
    await tester.tap(find.text('最高').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('配置已修改，请保存并检测'), findsOneWidget);
    expect(find.textContaining('请求值：'), findsNothing);

    await tester.ensureVisible(speed);
    await tester.tap(speed);
    await tester.pumpAndSettle();
    final selectedOption = find
        .ancestor(of: find.text('自动').last, matching: find.byType(Container))
        .first;
    final selectedDecoration =
        tester.widget<Container>(selectedOption).decoration as BoxDecoration?;
    expect(selectedDecoration?.borderRadius, BorderRadius.circular(8));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    final focusedOption = find
        .ancestor(
          of: find.text('快速（Fast）').last,
          matching: find.byType(Container),
        )
        .first;
    final focusedDecoration =
        tester.widget<Container>(focusedOption).decoration as BoxDecoration?;
    expect(focusedDecoration?.color, DesktopColors.soft);
    await tester.tap(find.text('快速（Fast）').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Fast 可能额外计费'), findsOneWidget);
    expect(find.textContaining('service_tier='), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop AI check reports model and chat probe stages', (
    tester,
  ) async {
    final _GatedDesktopAiService aiService = _GatedDesktopAiService();
    final AppController local = AppController(
      preferencesService: _InMemoryPreferencesService(),
      aiService: aiService,
      gameManifestService: GameManifestService(),
      remoteAssetService: _NoNetworkAssetService(),
      speechService: SpeechService(),
      ttsService: _UnavailableTtsService(),
    );
    addTearDown(local.dispose);
    await local.saveAiApiConfig(
      local.aiApiConfig.copyWith(model: 'gpt-5.6-sol', apiKey: 'test-key'),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDesktopTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: DesktopSettingsPane(controller: local, onOpenAbout: () {}),
          ),
        ),
      ),
    );

    final Finder button = find.byKey(
      const ValueKey<String>('desktop-settings-ai-save-check'),
    );
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    expect(find.textContaining('正在获取 /models'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('desktop-settings-ai-status')),
      findsOneWidget,
    );

    aiService.models.complete(const <AiModel>[AiModel(id: 'gpt-5.6-sol')]);
    await tester.pump();
    expect(find.textContaining('正在探测 Chat Completions'), findsOneWidget);

    aiService.health.complete(
      const AiHealthResult(
        success: true,
        message: 'ok',
        latency: Duration.zero,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('强度与 Fast 尚未验证'), findsOneWidget);
    expect(find.textContaining('连接正常：已保存'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('desktop-settings-ai-feedback')),
      findsNothing,
    );

    final Finder speed = find.descendant(
      of: find.byKey(const ValueKey<String>('desktop-settings-ai-speed')),
      matching: find.byType(DropdownButtonFormField<AiResponseSpeed>),
    );
    await tester.ensureVisible(speed);
    await tester.tap(speed);
    await tester.pumpAndSettle();
    await tester.tap(find.text('快速（Fast）').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('配置已修改，请保存并检测'), findsOneWidget);
    expect(find.textContaining('连接正常：'), findsNothing);
  });

  test('desktop AI settings discovers models before one is selected', () async {
    final DesktopAiSettingsResult result =
        await DesktopAiSettingsService(context.controller).saveAndCheck(
          const DesktopAiSettingsDraft(
            provider: 'Desktop Provider',
            model: '',
            apiKey: 'desktop-secret',
            baseUrl: 'https://desktop.example/v1',
          ),
        );

    expect(result.connected, isFalse);
    expect(result.modelCount, 1);
    expect(context.controller.availableAiModels.single.id, 'gpt-5.6-sol');
    expect(context.controller.aiApiConfig.model, isEmpty);
    expect(
      context.controller.aiConnectivityStatus.state,
      ConnectivityState.warning,
    );
  });

  test(
    'discovery filters old models without deleting a saved selection',
    () async {
      await context.controller.saveAiApiConfig(
        context.controller.aiApiConfig.copyWith(
          model: 'gpt-5.5',
          reasoningEffort: AiReasoningEffort.high,
        ),
      );

      final List<AiModel> visible = await context.controller.refreshAiModels();

      expect(visible.map((AiModel model) => model.id), <String>['gpt-5.6-sol']);
      expect(context.controller.aiApiConfig.model, 'gpt-5.5');
      expect(context.controller.selectedAiModelResolution.isUsable, isFalse);
      await context.controller.setAiReasoningEffort(
        AiReasoningEffort.automatic,
      );
      expect(
        context.controller.aiApiConfig.reasoningEffort,
        AiReasoningEffort.automatic,
      );
    },
  );

  test(
    'changing reasoning keeps discovery and resets unsupported effort',
    () async {
      await context.controller.saveAiApiConfig(
        context.controller.aiApiConfig.copyWith(model: 'gpt-5.6-sol'),
      );
      await context.controller.refreshAiModels();
      await context.controller.setAiReasoningEffort(AiReasoningEffort.none);

      expect(context.controller.availableAiModels, hasLength(1));
      await context.controller.setAiModel('gpt-6-astra');
      expect(
        context.controller.aiApiConfig.reasoningEffort,
        AiReasoningEffort.automatic,
      );
      expect(context.controller.availableAiModels, hasLength(1));
    },
  );

  testWidgets('switching to English updates the desktop settings shell', (
    tester,
  ) async {
    await _mount(tester, context.controller, const Size(1280, 800));
    await _navigate(tester, '设置');

    await tester.tap(
      find.byKey(const ValueKey<String>('desktop-settings-language')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('English').last);
    for (int attempt = 0; attempt < 30; attempt++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('App preferences and services').evaluate().isNotEmpty) {
        break;
      }
    }

    expect(context.controller.language, AppLanguage.en);
    expect(find.text('App preferences and services'), findsOneWidget);
    expect(find.text('General'), findsOneWidget);
    expect(find.text('AI Service'), findsOneWidget);
    expect(find.text('Appearance & Theme'), findsOneWidget);
    expect(find.text('Notification Settings'), findsNothing);
    expect(find.text('Sync & Backup'), findsOneWidget);
    expect(find.text('About & Updates'), findsOneWidget);
    expect(find.text('应用偏好与服务'), findsNothing);
    expect(find.text('通知设置'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _GatedDesktopAiService extends _FakeAiService {
  final Completer<List<AiModel>> models = Completer<List<AiModel>>();
  final Completer<AiHealthResult> health = Completer<AiHealthResult>();

  @override
  Future<List<AiModel>> listModels(AiApiConfig config) => models.future;

  @override
  Future<AiHealthResult> checkConnection(AiApiConfig config) => health.future;
}
