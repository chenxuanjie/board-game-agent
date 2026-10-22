import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:board_game_agent/app/state/app_controller.dart';
import 'package:board_game_agent/core/theme/app_theme.dart';
import 'package:board_game_agent/features/settings/services/preferences_service.dart';
import 'package:board_game_agent/features/games/services/game_manifest_service.dart';
import 'package:board_game_agent/features/assistant/services/ai_service.dart';
import 'package:board_game_agent/features/assistant/services/speech_service.dart';
import 'package:board_game_agent/features/assistant/services/tts_service.dart';
import 'package:board_game_agent/features/library/services/remote_asset_service.dart';
import 'package:board_game_agent/features/library/models/asset_source_config.dart';
import 'package:board_game_agent/features/library/models/cached_asset.dart';
import 'package:board_game_agent/ui/mobile/home_screen.dart';
import 'package:board_game_agent/ui/shared/game_ranking_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('mine exposes working ranking navigation on small phones', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final controller = _controller();
    addTearDown(controller.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await controller.reloadGames();
    for (final width in [320.0, 390.0]) {
      await tester.binding.setSurfaceSize(Size(width, 800));
      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          theme: AppTheme.buildTheme(controller.palette),
          routes: {
            GameRankingScreen.routeName: (_) =>
                GameRankingScreen(controller: controller, onOpenGame: (_) {}),
          },
          home: HomeScreen(controller: controller, onOpenAbout: () {}),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mobile-tab-mine')));
      await tester.pumpAndSettle();
      final entry = find.byKey(const ValueKey('mobile-mine-service-2'));
      await tester.scrollUntilVisible(
        entry,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(entry);
      await tester.pumpAndSettle();
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.byType(GameRankingScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(GameRankingScreen), findsNothing);
    }
  });
}

AppController _controller() => AppController(
  preferencesService: PreferencesService(),
  aiService: _Ai(),
  gameManifestService: GameManifestService(),
  remoteAssetService: _Assets(),
  speechService: SpeechService(),
  ttsService: TtsService(),
);

class _Ai extends Fake implements AiService {}

class _Assets extends RemoteAssetService {
  @override
  Future<File?> cachedFileFor(String path) async => null;
  @override
  Future<CachedAsset?> ensureCached({
    required List<AssetSourceConfig> sources,
    required String remotePath,
    bool forceRefresh = false,
    bool allowCachedFallback = true,
  }) async => null;
}
