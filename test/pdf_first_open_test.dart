import 'dart:async';

import 'package:board_game_agent/app/state/app_controller.dart';
import 'package:board_game_agent/core/theme/app_theme.dart';
import 'package:board_game_agent/features/assistant/services/ai_service.dart';
import 'package:board_game_agent/features/assistant/services/speech_service.dart';
import 'package:board_game_agent/features/assistant/services/tts_service.dart';
import 'package:board_game_agent/features/games/services/game_manifest_service.dart';
import 'package:board_game_agent/features/library/models/asset_source_config.dart';
import 'package:board_game_agent/features/library/models/cached_asset.dart';
import 'package:board_game_agent/features/library/services/remote_asset_service.dart';
import 'package:board_game_agent/features/settings/services/preferences_service.dart';
import 'package:board_game_agent/ui/shared/documents/pdf_document_screen.dart';
import 'package:board_game_agent/ui/shared/documents/document_failure_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('first downloaded PDF keeps its reference during a rebuild', (
    tester,
  ) async {
    final cache = Completer<CachedAsset?>();
    final pathProvider = Completer<String>();
    Pdfrx.cacheDirectoryPath = null;
    final originalEngine = PdfrxEntryFunctions.instance;
    final engine = _PdfEngine();
    PdfrxEntryFunctions.instance = engine;
    addTearDown(() => PdfrxEntryFunctions.instance = originalEngine);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => pathProvider.future,
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      );
    });
    final controller = AppController(
      preferencesService: PreferencesService(),
      aiService: _NoAi(),
      gameManifestService: GameManifestService(),
      remoteAssetService: _PendingAsset(cache),
      speechService: SpeechService(),
      ttsService: TtsService(),
    );
    addTearDown(controller.dispose);
    Widget screen(String title) => MaterialApp(
      theme: AppTheme.buildTheme(controller.palette),
      home: PdfDocumentScreen(
        controller: controller,
        remotePath: 'rules.pdf',
        title: title,
      ),
    );
    await tester.pumpWidget(screen('规则书'));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    cache.complete(
      const CachedAsset(
        remotePath: 'rules.pdf',
        localPath: 'cached-rules.pdf',
        exists: true,
        fromRemote: true,
      ),
    );
    await tester.pump();
    await tester.pump();
    final before = tester.widget<PdfViewer>(find.byType(PdfViewer));
    expect(before.params.loadingBannerBuilder, isNotNull);
    await tester.pumpWidget(screen('规则书标题'));
    final after = tester.widget<PdfViewer>(find.byType(PdfViewer));
    expect(identical(before.documentRef, after.documentRef), isTrue);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pathProvider.complete('test-cache-directory');
    for (var attempt = 0; attempt < 15 && engine.openCalls == 0; attempt++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(engine.openCalls, 1);
    await tester.pump();
    expect(find.byType(DocumentFailureView), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}

class _NoAi extends Fake implements AiService {}

class _PendingAsset extends RemoteAssetService {
  _PendingAsset(this.cache);
  final Completer<CachedAsset?> cache;
  @override
  Future<CachedAsset?> ensureCached({
    required List<AssetSourceConfig> sources,
    required String remotePath,
    bool forceRefresh = false,
    bool allowCachedFallback = true,
  }) => cache.future;
}

class _PdfEngine extends Fake implements PdfrxEntryFunctions {
  int openCalls = 0;
  @override
  Future<void> init() async {}
  @override
  Future<PdfDocument> openFile(
    String filePath, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
  }) async {
    openCalls++;
    throw StateError('Simulated PDF renderer failure');
  }
}
