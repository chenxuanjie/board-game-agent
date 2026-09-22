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
          model: 'test-model',
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

      final Finder warmwoodTheme = find.byKey(
        ValueKey<String>(
          'desktop-settings-theme-${ColorSchemeOption.warmwoodStudy.code}',
        ),
      );
      await tester.tap(warmwoodTheme);
      await tester.pumpAndSettle();
      expect(context.controller.colorScheme, ColorSchemeOption.warmwoodStudy);
      expect(context.preferences._colorScheme, ColorSchemeOption.warmwoodStudy);

      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
      expect(
        tester
            .widget<OutlinedButton>(
              find.descendant(
                of: find.byKey(
                  const ValueKey<String>('desktop-settings-sync-disabled'),
                ),
                matching: find.byType(OutlinedButton),
              ),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(
                const ValueKey<String>('desktop-settings-restore-defaults'),
              ),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('desktop AI card exposes provider and discovered-model menus', (
    tester,
  ) async {
    await _mount(tester, context.controller, const Size(1280, 800));
    await _navigate(tester, '设置');

    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('desktop-settings-ai-provider')),
        matching: find.byType(DropdownButtonFormField<String>),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('desktop-settings-ai-model')),
        matching: find.byType(DropdownButtonFormField<String>),
      ),
      findsOneWidget,
    );
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
      final DesktopAiSettingsResult result =
          await DesktopAiSettingsService(context.controller).saveAndCheck(
            const DesktopAiSettingsDraft(
              provider: 'Desktop Provider',
              model: 'desktop-model',
              apiKey: 'desktop-secret',
              baseUrl: 'https://desktop.example/v1',
            ),
          );

      expect(result.connected, isTrue);
      expect(context.controller.aiApiConfig.name, 'Desktop Provider');
      expect(context.controller.aiApiConfig.model, 'desktop-model');
      expect(context.controller.aiApiConfig.apiKey, 'desktop-secret');
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
    expect(context.controller.availableAiModels.single.id, 'desktop-model');
    expect(context.controller.aiApiConfig.model, isEmpty);
    expect(
      context.controller.aiConnectivityStatus.state,
      ConnectivityState.warning,
    );
  });

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
    expect(find.text('Notification Settings'), findsOneWidget);
    expect(find.text('Sync & Backup'), findsOneWidget);
    expect(find.text('About & Updates'), findsOneWidget);
    expect(find.text('应用偏好与服务'), findsNothing);
    expect(find.text('通知设置'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
