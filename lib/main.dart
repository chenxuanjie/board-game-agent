import 'dart:async';

import 'package:app_about/app_about.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:app_ai_client/app_ai_client.dart';
import 'package:webdav_settings/webdav_settings.dart';
import 'package:window_manager/window_manager.dart';

import 'features/assistant/services/board_game_ai_service.dart';
import 'features/games/services/game_manifest_service.dart';
import 'features/games/services/game_vote_service.dart';
import 'features/games/services/webdav_game_vote_store.dart';
import 'features/settings/services/preferences_service.dart';
import 'features/library/services/remote_asset_service.dart';
import 'features/settings/services/board_game_update_settings.dart';
import 'features/library/services/board_game_remote_layout.dart';
import 'core/platform/insecure_android_certificate_trust.dart';
import 'features/assistant/services/speech_service.dart';
import 'features/assistant/services/tts_service.dart';
import 'features/assistant/services/realtime_voice_service.dart';
import 'features/assistant/services/responses_compaction_store.dart';
import 'features/assistant/services/ai_run_telemetry.dart';
import 'features/assistant/services/responses_rules_workflow.dart';
import 'app/state/app_controller.dart';
import 'core/localization/app_language.dart';
import 'core/theme/color_scheme_option.dart';
import 'core/theme/app_theme.dart';
import 'ui/mobile/home_screen.dart';
import 'ui/desktop/workspace.dart';
import 'ui/desktop/desktop_responsive.dart';
import 'ui/desktop/theme.dart';

Future<void> main() async {
  enableInsecureAndroidCertificateTrust();
  WidgetsFlutterBinding.ensureInitialized();
  await _configureWindowsWindow();

  final preferencesService = PreferencesService();
  final initialColorScheme = await _loadInitialColorScheme(preferencesService);

  final updateStore = SecureWebDavSettingsStore(appId: 'board_game_agent');
  await _prepareUpdateSettings(updateStore);
  final updateSettingsController = WebDavSettingsController(
    store: updateStore,
    connectionTester: DefaultWebDavConnectionTester(appId: 'board_game_agent'),
  );

  final AppController controller = AppController(
    preferencesService: preferencesService,
    initialColorScheme: initialColorScheme,
    gameVotes: GameVoteService(
      preferences: preferencesService,
      remoteProvider: () =>
          WebDavGameVoteStore.fromSettings(updateSettingsController.saved),
    ),
    aiService: BoardGameAiService(
      aiClient: OpenAiDartAiClient(),
      responsesWorkflow: ResponsesRulesWorkflow(
        responsesClient: OpenAiDartResponsesAiClient(),
        compactionStore: SecureResponsesCompactionStore(),
        telemetrySink: SharedPreferencesAiRunTelemetrySink(),
      ),
    ),
    gameManifestService: GameManifestService(),
    remoteAssetService: RemoteAssetService(
      settingsProvider: () => updateSettingsController.saved,
    ),
    speechService: SpeechService(),
    ttsService: TtsService(),
    realtimeVoiceService: const UnconfiguredRealtimeVoiceService(),
  );

  runApp(
    BoardGameAgentApp(
      controller: controller,
      updateSettingsController: updateSettingsController,
    ),
  );
}

Future<void> _configureWindowsWindow() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return;
  await windowManager.ensureInitialized();
  const WindowOptions options = WindowOptions(
    size: DesktopResponsive.desktopWindowDefaultSize,
    minimumSize: DesktopResponsive.desktopWindowMinimumSize,
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
  );
  windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
}

Future<ColorSchemeOption> _loadInitialColorScheme(
  PreferencesService preferencesService,
) async {
  try {
    return await preferencesService.loadColorScheme();
  } catch (_) {
    // Keep the native launch path usable even if the preference store is
    // temporarily unavailable. The controller will retry during initialize.
    return defaultColorScheme;
  }
}

Future<void> _prepareUpdateSettings(
  SecureWebDavSettingsStore updateStore,
) async {
  final stored = await updateStore.load();
  if (stored != null) {
    final normalized = BoardGameRemoteLayout.normalizeSettings(stored);
    if (normalized.baseUrl != stored.baseUrl) {
      await updateStore.save(normalized);
    }
    return;
  }

  final legacy = await BoardGameUpdateSettingsLoader.load();
  if (!legacy.isComplete) return;
  await updateStore.save(
    BoardGameRemoteLayout.normalizeSettings(
      legacy.copyWith(mode: ExternalStorageMode.webDav),
    ),
  );
}

class BoardGameAgentApp extends StatefulWidget {
  const BoardGameAgentApp({
    super.key,
    required this.controller,
    required this.updateSettingsController,
  });

  final AppController controller;
  final WebDavSettingsController updateSettingsController;

  @override
  State<BoardGameAgentApp> createState() => _BoardGameAgentAppState();
}

class _BoardGameAgentAppState extends State<BoardGameAgentApp> {
  late Future<void> _initialization;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  bool _startupUpdateCheckScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChange);
    _initialization = _initialize();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChange);
    widget.controller.disposeServices();
    widget.updateSettingsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Theme and workspace must use the same decision, including after a
        // browser resize. Otherwise desktop menus inherit the mobile theme.
        final bool desktopLayout =
            (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) ||
            (kIsWeb &&
                DesktopResponsive.supportsDesktopViewport(constraints.biggest));
        return MaterialApp(
          navigatorKey: _navigatorKey,
          title: widget.controller.copy.appTitle,
          debugShowCheckedModeBanner: false,
          locale: widget.controller.language == AppLanguage.en
              ? const Locale('en')
              : const Locale.fromSubtags(
                  languageCode: 'zh',
                  scriptCode: 'Hans',
                ),
          supportedLocales: const <Locale>[
            Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
            Locale('en'),
          ],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: desktopLayout
              ? buildDesktopTheme()
              : AppTheme.buildTheme(widget.controller.palette),
          home: FutureBuilder<void>(
            future: _initialization,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const _StartupScreen();
              }

              if (snapshot.hasError) {
                return _StartupErrorScreen(
                  onRetry: () {
                    setState(() {
                      _initialization = _initialize();
                    });
                  },
                  message: widget.controller.copy.startupDataUnavailable,
                );
              }

              _scheduleStartupUpdateCheck(context);
              if (desktopLayout) {
                return DesktopWorkspace(
                  controller: widget.controller,
                  webDavSettingsController: widget.updateSettingsController,
                  onOpenAbout: _openAbout,
                );
              }
              return HomeScreen(
                controller: widget.controller,
                onOpenAbout: _openAbout,
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _initialize() async {
    try {
      await widget.updateSettingsController.load();
      await widget.controller.initialize();
    } catch (error, stackTrace) {
      debugPrint('[startup] initialization failed: $error');
      debugPrint('$stackTrace');
      rethrow;
    }
  }

  void _scheduleStartupUpdateCheck(BuildContext context) {
    if (_startupUpdateCheckScheduled || !widget.controller.checkForUpdates) {
      return;
    }
    _startupUpdateCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !context.mounted) return;
      unawaited(
        checkForUpdateOnStartup(
          context: context,
          appId: 'board_game_agent',
          updateService: _createUpdateService(),
        ),
      );
    });
  }

  Future<void> _openAbout() async {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    await navigator.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => AppAboutPage(
          config: const AppAboutConfig(
            appName: '桌游导师',
            subtitle: '桌游入口与统一 AI 助手',
            appIcon: _BoardGameAppMark(),
            fallbackVersion: '1.0.0',
            fallbackBuild: '7',
          ),
          updateService: _createUpdateService(),
        ),
      ),
    );
  }

  AppUpdateService _createUpdateService() => createWebDavAndroidUpdateService(
    settingsProvider: () => widget.updateSettingsController.saved,
    config: const WebDavAndroidUpdateConfig(
      appId: 'board_game_agent',
      manifestPath: BoardGameRemoteLayout.updateManifestPath,
      fallbackVersion: '1.0.0',
      fallbackBuild: 7,
      directoryName: 'board_game_agent_updates',
    ),
  );

  void _handleControllerChange() {
    if (mounted) {
      setState(() {});
    }
  }
}

class _BoardGameAppMark extends StatelessWidget {
  const _BoardGameAppMark();

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(22),
    child: Image.asset(
      'branding/app_icon.png',
      width: 88,
      height: 88,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.high,
      semanticLabel: '桌游导师应用图标',
    ),
  );
}

class _StartupScreen extends StatelessWidget {
  const _StartupScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class _StartupErrorScreen extends StatelessWidget {
  const _StartupErrorScreen({required this.onRetry, required this.message});

  final VoidCallback onRetry;
  final String message;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.error_outline_rounded, size: 44),
              const SizedBox(height: 14),
              Text('启动失败', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton(onPressed: onRetry, child: const Text('重试')),
            ],
          ),
        ),
      ),
    );
  }
}
