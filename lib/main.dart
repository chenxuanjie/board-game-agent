import 'dart:async';

import 'package:app_about/app_about.dart';
import 'package:flutter/material.dart';
import 'package:app_ai_client/app_ai_client.dart';
import 'package:webdav_settings/webdav_settings.dart';

import 'services/mimo_ai_service.dart';
import 'services/game_manifest_service.dart';
import 'services/preferences_service.dart';
import 'services/remote_asset_service.dart';
import 'services/board_game_update_settings.dart';
import 'services/speech_service.dart';
import 'services/tts_service.dart';
import 'state/app_controller.dart';
import 'theme/app_theme.dart';
import 'ui/screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final updateSettings = await BoardGameUpdateSettingsLoader.load();
  final updateSettingsController = WebDavSettingsController(
    store: SecureWebDavSettingsStore(appId: 'board_game_agent'),
    connectionTester: DefaultWebDavConnectionTester(appId: 'board_game_agent'),
    legacySettings: updateSettings,
  );

  final AppController controller = AppController(
    preferencesService: PreferencesService(),
    aiService: MimoAiService(aiClient: OpenAiDartAiClient()),
    gameManifestService: GameManifestService(),
    remoteAssetService: RemoteAssetService(),
    speechService: SpeechService(),
    ttsService: TtsService(),
  );

  runApp(
    BoardGameAgentApp(
      controller: controller,
      updateSettingsController: updateSettingsController,
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
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: widget.controller.copy.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.buildTheme(widget.controller.palette),
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
              error: snapshot.error,
            );
          }

          _scheduleStartupUpdateCheck();
          return HomeScreen(
            controller: widget.controller,
            onOpenAbout: _openAbout,
          );
        },
      ),
    );
  }

  Future<void> _initialize() async {
    await widget.updateSettingsController.load();
    if (widget.updateSettingsController.hasLegacyConfiguration) {
      await widget.updateSettingsController.store.save(
        widget.updateSettingsController.draft.copyWith(
          mode: ExternalStorageMode.webDav,
        ),
      );
    }
    await widget.controller.initialize();
  }

  void _scheduleStartupUpdateCheck() {
    if (_startupUpdateCheckScheduled || !widget.controller.checkForUpdates) {
      return;
    }
    _startupUpdateCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final navigatorContext = _navigatorKey.currentContext;
      if (navigatorContext == null) return;
      unawaited(
        checkForUpdateOnStartup(
          context: navigatorContext,
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
            fallbackBuild: '3',
          ),
          updateService: _createUpdateService(),
        ),
      ),
    );
  }

  AppUpdateService _createUpdateService() => createWebDavAndroidUpdateService(
    settingsProvider: _currentUpdateSettings,
    config: const WebDavAndroidUpdateConfig(
      appId: 'board_game_agent',
      manifestPath: 'apps/board_game_agent/updates/manifest.json',
      fallbackVersion: '1.0.0',
      fallbackBuild: 3,
      directoryName: 'board_game_agent_updates',
    ),
  );

  WebDavSettings _currentUpdateSettings() {
    final saved = widget.updateSettingsController.saved;
    if (saved.isComplete) return saved;
    return widget.updateSettingsController.draft;
  }

  void _handleControllerChange() {
    if (mounted) {
      setState(() {});
    }
  }
}

class _BoardGameAppMark extends StatelessWidget {
  const _BoardGameAppMark();

  @override
  Widget build(BuildContext context) => Container(
    width: 88,
    height: 88,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary,
      borderRadius: const BorderRadius.all(Radius.circular(22)),
    ),
    child: const Icon(Icons.casino_rounded, color: Colors.white, size: 50),
  );
}

class _StartupScreen extends StatelessWidget {
  const _StartupScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0F172A),
      body: Center(child: CircularProgressIndicator(color: Color(0xFF23D2D8))),
    );
  }
}

class _StartupErrorScreen extends StatelessWidget {
  const _StartupErrorScreen({required this.onRetry, required this.error});

  final VoidCallback onRetry;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.error_outline_rounded,
                color: Colors.white,
                size: 44,
              ),
              const SizedBox(height: 14),
              Text(
                '启动失败',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 10),
              Text(
                '$error',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
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
