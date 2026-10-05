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
import 'features/games/models/game_vote_record.dart';
import 'features/settings/services/preferences_service.dart';
import 'features/settings/services/settings_transfer_service.dart';
import 'features/library/services/remote_asset_service.dart';
import 'features/settings/services/board_game_update_settings.dart';
import 'features/settings/services/windows_update_service.dart';
import 'features/library/services/board_game_remote_layout.dart';
import 'features/assistant/services/speech_service.dart';
import 'features/assistant/services/tts_service.dart';
import 'features/assistant/services/realtime_voice_service.dart';
import 'features/assistant/services/responses_compaction_store.dart';
import 'features/assistant/services/ai_run_telemetry.dart';
import 'features/assistant/services/responses_rules_workflow.dart';
import 'features/identity/services/account_service.dart';
import 'app/state/app_controller.dart';
import 'core/localization/app_language.dart';
import 'core/theme/color_scheme_option.dart';
import 'core/theme/app_theme.dart';
import 'ui/mobile/home_screen.dart';
import 'ui/mobile/settings_screen.dart';
import 'ui/mobile/game_detail_screen.dart';
import 'ui/shared/game_ranking_screen.dart';
import 'ui/shared/account_scope.dart';
import 'ui/desktop/workspace.dart';
import 'ui/desktop/desktop_responsive.dart';
import 'ui/desktop/theme.dart';

Future<void> main() async {
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

  late final AccountService accountService;
  final AppController controller = AppController(
    preferencesService: preferencesService,
    initialColorScheme: initialColorScheme,
    gameVotes: GameVoteService(
      preferences: preferencesService,
      remoteProvider: () =>
          WebDavGameVoteStore.fromSettings(updateSettingsController.saved),
    ),
    favoriteRemoteProvider: () => WebDavGameVoteStore.fromSettings(
      updateSettingsController.saved,
      namespace: GameVoteBallot.favoritesNamespace,
    ),
    favoriteScopeProvider: () => WebDavGameVoteStore.scopeFor(
      updateSettingsController.saved,
      namespace: GameVoteBallot.favoritesNamespace,
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
      resourceSettingsProvider: (target) =>
          accountService.settingsForResource(target),
    ),
    speechService: SpeechService(),
    ttsService: TtsService(),
    realtimeVoiceService: const UnconfiguredRealtimeVoiceService(),
  );

  accountService = AccountService(
    controller: controller,
    webDav: updateSettingsController,
  );
  runApp(
    BoardGameAgentApp(
      controller: controller,
      updateSettingsController: updateSettingsController,
      accountService: accountService,
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
    final normalized = BoardGameRemoteLayout.migrateLegacySettings(stored);
    if (normalized.baseUrl != stored.baseUrl) {
      await updateStore.save(normalized);
    }
    return;
  }

  final legacy = await BoardGameUpdateSettingsLoader.load(
    sources: await PreferencesService().loadAssetSourceConfigs(),
  );
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
    this.accountService,
  });

  final AppController controller;
  final WebDavSettingsController updateSettingsController;
  final AccountService? accountService;

  @override
  State<BoardGameAgentApp> createState() => _BoardGameAgentAppState();
}

class _BoardGameAgentAppState extends State<BoardGameAgentApp> {
  late final SettingsTransferService _transferService = SettingsTransferService(
    controller: widget.controller,
    webDav: widget.updateSettingsController,
    account: widget.accountService,
  );
  late Future<void> _initialization;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  bool _startupUpdateCheckScheduled = false;
  String? _lastAccountKey;
  String? _lastResourceConnection;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChange);
    widget.accountService?.addListener(_handleAccountChange);
    _initialization = _initialize();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChange);
    widget.accountService?.removeListener(_handleAccountChange);
    widget.accountService?.dispose();
    widget.controller.disposeServices();
    widget.updateSettingsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = _buildApplication(context);
    final accounts = widget.accountService;
    return accounts == null ? app : AccountScope(service: accounts, child: app);
  }

  Widget _buildApplication(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Theme and workspace must use the same decision, including after a
        // browser resize. Otherwise desktop menus inherit the mobile theme.
        final bool desktopLayout =
            (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) ||
            (kIsWeb &&
                DesktopResponsive.supportsDesktopViewport(constraints.biggest));
        return MaterialApp(
          builder: (context, child) {
            final accounts = widget.accountService;
            if (accounts == null || accounts.dataScopeReady) {
              return child ?? const SizedBox.shrink();
            }
            // Remove the prior account's UI from the tree while its writes drain.
            return Scaffold(
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (accounts.error == null)
                      const CircularProgressIndicator()
                    else ...[
                      const Text('账号数据切换未完成'),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => unawaited(accounts.restore()),
                        child: const Text('重试'),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
          routes: {
            GameRankingScreen.routeName: (context) => desktopLayout
                ? DesktopWorkspace(
                    controller: widget.controller,
                    webDavSettingsController: widget.updateSettingsController,
                    transferService: _transferService,
                    initialPage: 'rankings',
                    onOpenAbout: _openAbout,
                  )
                : GameRankingScreen(
                    controller: widget.controller,
                    onOpenGame: (game) {
                      unawaited(widget.controller.recordRecentlyViewed(game));
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => GameDetailScreen(
                            controller: widget.controller,
                            game: game,
                          ),
                        ),
                      );
                    },
                  ),
            '/settings/ai': (_) => MobileSettingsScreen(
              controller: widget.controller,
              transferService: _transferService,
              focusAiSettings: true,
              onOpenAbout: _openAbout,
            ),
          },
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
                  key: ValueKey(widget.accountService?.nicknameKey),
                  controller: widget.controller,
                  webDavSettingsController: widget.updateSettingsController,
                  transferService: _transferService,
                  onOpenAbout: _openAbout,
                );
              }
              return HomeScreen(
                key: ValueKey(widget.accountService?.nicknameKey),
                controller: widget.controller,
                transferService: _transferService,
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
      await _transferService.recover();
      await widget.controller.initialize();
      await widget.accountService?.initialize();
      // Publish existing favorites too, even while the ranking entry is hidden.
      unawaited(widget.controller.refreshFavoriteRankings());
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
            updateCheckSubtitle: '检查应用新版本',
          ),
          updateService: _createUpdateService(),
        ),
      ),
    );
  }

  AppUpdateService _createUpdateService() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      return createWindowsUpdateService(
        settingsProvider: () => widget.updateSettingsController.saved,
        beforeInstall: () async {
          if (_transferService.isBusy) {
            throw StateError('设置正在保存，请完成后重试');
          }
          await widget.controller.prepareForAppUpdate();
        },
        onInstallerLaunched: () => windowManager.destroy(),
      );
    }
    return createWebDavAndroidUpdateService(
      settingsProvider: () => widget.updateSettingsController.saved,
      config: const WebDavAndroidUpdateConfig(
        appId: 'board_game_agent',
        manifestPath: BoardGameRemoteLayout.updateManifestPath,
        fallbackVersion: '1.0.0',
        fallbackBuild: 7,
        directoryName: 'board_game_agent_updates',
      ),
    );
  }

  void _handleControllerChange() {
    if (mounted) {
      setState(() {});
    }
  }

  void _handleAccountChange() {
    if (!mounted) return;
    final key = widget.accountService?.nicknameKey;
    if (_lastAccountKey != null && key != _lastAccountKey) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _navigatorKey.currentState?.popUntil((route) => route.isFirst);
        }
      });
    }
    _lastAccountKey = key;
    final account = widget.accountService;
    if (account != null &&
        !account.isBusy &&
        account.resourceCredentialsReady) {
      final connection =
          '${account.nicknameKey}|${account.configuration!.resourceSources.map((s) => s.testUrl).join('|')}';
      if (_lastResourceConnection != connection) {
        _lastResourceConnection = connection;
        unawaited(widget.controller.refreshLibraryResources(force: true));
      }
    } else if (account?.isSignedIn == false) {
      _lastResourceConnection = null;
    }
    setState(() {});
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
