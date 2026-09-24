import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:board_game_agent/features/assistant/services/ai_service.dart';
import 'package:board_game_agent/features/library/models/asset_source_config.dart';
import 'package:board_game_agent/features/library/models/cached_asset.dart';
import 'package:board_game_agent/features/games/services/game_manifest_service.dart';
import 'package:board_game_agent/features/settings/services/preferences_service.dart';
import 'package:board_game_agent/features/library/services/remote_asset_service.dart';
import 'package:board_game_agent/features/assistant/services/speech_service.dart';
import 'package:board_game_agent/features/assistant/services/tts_service.dart';
import 'package:board_game_agent/app/state/app_controller.dart';
import 'package:board_game_agent/core/theme/app_theme.dart';
import 'package:board_game_agent/ui/mobile/home_screen.dart';
import 'package:board_game_agent/ui/mobile/game_search_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('mobile V4 home fits phone sizes and searches real games', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final controller = _controller();
    addTearDown(controller.dispose);
    await controller.reloadGames();
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final size in [const Size(390, 844), const Size(320, 640)]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.buildTheme(controller.palette),
          home: HomeScreen(controller: controller, onOpenAbout: () {}),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('mobile-home-root')), findsOneWidget);
      expect(find.text('桌游伙伴'), findsOneWidget);
      expect(find.text('继续游玩'), findsOneWidget);
      expect(find.text('推荐桌游'), findsOneWidget);
      expect(find.byKey(const ValueKey('mobile-tab-home')), findsOneWidget);
      expect(find.byKey(const ValueKey('mobile-tab-library')), findsOneWidget);
      expect(find.byKey(const ValueKey('mobile-tab-ai')), findsOneWidget);
      expect(find.byKey(const ValueKey('mobile-tab-mine')), findsOneWidget);
      expect(find.text('社区'), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const ValueKey('mobile-tab-library')));
      await tester.pumpAndSettle();
      expect(find.text('新版页面暂未开放'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mobile-tab-home')));
      await tester.pumpAndSettle();
      expect(find.text('继续游玩'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mobile-tab-mine')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mobile-mine-profile')), findsOneWidget);
      expect(find.text('${controller.favoriteCount}'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('我的服务'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('我的服务'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mobile-tab-home')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.byKey(const ValueKey('mobile-home-search')));
    await tester.pumpAndSettle();
    expect(find.byType(MobileGameSearchScreen), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('mobile-game-query')),
      controller.games.first.title,
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey('mobile-search-game-${controller.games.first.id}')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

AppController _controller() => AppController(
  preferencesService: PreferencesService(),
  aiService: _UnusedAiService(),
  gameManifestService: GameManifestService(),
  remoteAssetService: _NoNetworkAssetService(),
  speechService: SpeechService(),
  ttsService: TtsService(),
);

class _UnusedAiService extends Fake implements AiService {}

class _NoNetworkAssetService extends RemoteAssetService {
  @override
  Future<File?> cachedFileFor(String remotePath) async => null;

  @override
  Future<CachedAsset?> ensureCached({
    required List<AssetSourceConfig> sources,
    required String remotePath,
    bool forceRefresh = false,
    bool allowCachedFallback = true,
  }) async => null;
}
