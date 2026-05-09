import 'package:flutter/material.dart';

import 'services/mimo_ai_service.dart';
import 'services/game_manifest_service.dart';
import 'services/preferences_service.dart';
import 'services/remote_asset_service.dart';
import 'services/speech_service.dart';
import 'services/tts_service.dart';
import 'state/app_controller.dart';
import 'theme/app_theme.dart';
import 'ui/screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final AppController controller = AppController(
    preferencesService: PreferencesService(),
    aiService: MimoAiService(),
    gameManifestService: GameManifestService(),
    remoteAssetService: RemoteAssetService(),
    speechService: SpeechService(),
    ttsService: TtsService(),
  );

  runApp(BoardGameAgentApp(controller: controller));
}

class BoardGameAgentApp extends StatefulWidget {
  const BoardGameAgentApp({
    super.key,
    required this.controller,
  });

  final AppController controller;

  @override
  State<BoardGameAgentApp> createState() => _BoardGameAgentAppState();
}

class _BoardGameAgentAppState extends State<BoardGameAgentApp> {
  late Future<void> _initialization;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChange);
    _initialization = widget.controller.initialize();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChange);
    widget.controller.disposeServices();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
                  _initialization = widget.controller.initialize();
                });
              },
              error: snapshot.error,
            );
          }

          return HomeScreen(controller: widget.controller);
        },
      ),
    );
  }

  void _handleControllerChange() {
    if (mounted) {
      setState(() {});
    }
  }
}

class _StartupScreen extends StatelessWidget {
  const _StartupScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0F172A),
      body: Center(
        child: CircularProgressIndicator(
          color: Color(0xFF23D2D8),
        ),
      ),
    );
  }
}

class _StartupErrorScreen extends StatelessWidget {
  const _StartupErrorScreen({
    required this.onRetry,
    required this.error,
  });

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
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                    ),
              ),
              const SizedBox(height: 10),
              Text(
                '$error',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white70,
                    ),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: onRetry,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
