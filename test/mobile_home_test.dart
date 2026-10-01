import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:board_game_agent/features/assistant/services/ai_service.dart';
import 'package:board_game_agent/features/assistant/models/ai_api_config.dart';
import 'package:board_game_agent/features/library/models/asset_source_config.dart';
import 'package:board_game_agent/features/library/models/cached_asset.dart';
import 'package:board_game_agent/features/games/services/game_manifest_service.dart';
import 'package:board_game_agent/features/games/services/related_game_recommender.dart';
import 'package:board_game_agent/features/settings/services/preferences_service.dart';
import 'package:board_game_agent/features/library/services/remote_asset_service.dart';
import 'package:board_game_agent/features/assistant/services/speech_service.dart';
import 'package:board_game_agent/features/assistant/services/tts_service.dart';
import 'package:board_game_agent/app/state/app_controller.dart';
import 'package:board_game_agent/core/theme/app_theme.dart';
import 'package:board_game_agent/ui/mobile/home_screen.dart';
import 'package:board_game_agent/ui/mobile/assistant_chat_screen.dart';
import 'package:board_game_agent/ui/mobile/game_search_screen.dart';
import 'package:board_game_agent/ui/mobile/game_detail_screen.dart';
import 'package:board_game_agent/ui/mobile/rule_materials_screen.dart';
import 'package:board_game_agent/ui/mobile/settings_screen.dart';
import 'package:board_game_agent/ui/mobile/game_cover.dart';
import 'package:board_game_agent/ui/shared/game_cover_motion.dart';
import 'package:board_game_agent/ui/mobile/national_day_screen.dart';
import 'package:board_game_agent/ui/desktop/national_day_page.dart';
import 'package:board_game_agent/core/localization/app_language.dart';
import 'package:board_game_agent/core/theme/color_scheme_option.dart';

part 'mobile/mobile_national_day_test_cases.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('mobile home and settings fit phone sizes', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final controller = _controller(ttsService: _UnavailableTtsService());
    addTearDown(controller.dispose);
    await controller.reloadGames();
    final squareGame = controller.games.firstWhere(
      (game) => game.id == 'exploding-kittens',
    );
    final portraitGame = controller.games.firstWhere(
      (game) => game.id == 'castles_of_burgundy_2019',
    );
    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        home: Scaffold(
          body: SizedBox(
            height: 154,
            child: Row(
              children: [
                ConstrainedBox(
                  key: const ValueKey('square-cover'),
                  constraints: const BoxConstraints(
                    maxWidth: 124,
                    maxHeight: 124,
                  ),
                  child: MobileGameCover(
                    controller: controller,
                    game: squareGame,
                    fit: BoxFit.contain,
                  ),
                ),
                ConstrainedBox(
                  key: const ValueKey('portrait-cover'),
                  constraints: const BoxConstraints(
                    maxWidth: 124,
                    maxHeight: 124,
                  ),
                  child: MobileGameCover(
                    controller: controller,
                    game: portraitGame,
                    fit: BoxFit.contain,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future.wait([
        precacheImage(
          AssetImage(squareGame.coverAssetPath),
          tester.element(find.byKey(const ValueKey('square-cover'))),
        ),
        precacheImage(
          AssetImage(portraitGame.coverAssetPath),
          tester.element(find.byKey(const ValueKey('portrait-cover'))),
        ),
      ]),
    );
    await tester.pumpAndSettle();
    final squareSize = tester.getSize(
      find.descendant(
        of: find.byKey(const ValueKey('square-cover')),
        matching: find.byType(Image),
      ),
    );
    final portraitSize = tester.getSize(
      find.descendant(
        of: find.byKey(const ValueKey('portrait-cover')),
        matching: find.byType(Image),
      ),
    );
    expect(squareSize.width, closeTo(124, 1));
    expect(squareSize.height, closeTo(124, 1));
    expect(portraitSize.width, closeTo(124 * 3 / 4, 1));
    expect(portraitSize.height, closeTo(124, 1));
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
      expect(find.text('最近AI对话'), findsOneWidget);
      expect(find.text('查看更多'), findsNothing);
      expect(find.text('向 AI 提一个问题'), findsOneWidget);
      if (size.width == 390) {
        expect(find.text('推荐桌游'), findsOneWidget);
        expect(find.text('快速找到心仪桌游'), findsNothing);
        expect(find.text('图文视频一应俱全'), findsNothing);
      }
      expect(find.byKey(const ValueKey('mobile-tab-home')), findsOneWidget);
      expect(find.byKey(const ValueKey('mobile-tab-library')), findsOneWidget);
      expect(find.byKey(const ValueKey('mobile-tab-ai')), findsOneWidget);
      expect(find.byKey(const ValueKey('mobile-tab-mine')), findsOneWidget);
      expect(find.text('社区'), findsNothing);
      expect(tester.takeException(), isNull);

      if (size.width == 390) {
        await tester.tap(find.text('规则资料库'));
        await tester.pumpAndSettle();
        expect(find.byType(MobileRuleMaterialsScreen), findsOneWidget);
        expect(
          find.byKey(const ValueKey('mobile-rule-materials-root')),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(ValueKey('mobile-rule-game-${controller.games.first.id}')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(
            const ValueKey(
              'mobile-rule-document-assets/games/puerto_rico/docs/official/rules/rulebook_en.pdf',
            ),
          ),
          findsOneWidget,
        );
        await tester.pageBack();
        await tester.pumpAndSettle();
      }

      await tester.tap(find.byKey(const ValueKey('mobile-tab-library')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mobile-library-grid')), findsOneWidget);
      expect(
        find.byKey(
          ValueKey('mobile-library-game-${controller.games.first.id}'),
        ),
        findsOneWidget,
      );
      if (size.width == 390) {
        await tester.tap(
          find.byKey(
            ValueKey('mobile-library-favorite-${controller.games.first.id}'),
          ),
        );
        await tester.pumpAndSettle();
        expect(controller.isFavorite(controller.games.first), isTrue);
        await tester.enterText(
          find.byKey(const ValueKey('mobile-library-search')),
          'no-such-game-123',
        );
        await tester.pumpAndSettle();
        expect(find.text('没有找到桌游'), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('mobile-library-search')),
          '',
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('mobile-library-category-3')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(
            ValueKey('mobile-library-game-${controller.games.first.id}'),
          ),
          findsNothing,
        );
        await tester.tap(
          find.byKey(const ValueKey('mobile-library-category-0')),
        );
        await tester.pumpAndSettle();
      }
      await tester.tap(
        find.byKey(
          ValueKey('mobile-library-game-${controller.games.first.id}'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(GameDetailScreen), findsOneWidget);
      final related = const RelatedGameRecommender().recommend(
        source: controller.games.first,
        catalog: controller.games,
      );
      expect(related, isNotEmpty);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('mobile-related-games-section')),
        300,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('mobile-game-detail-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('相关游戏'), findsOneWidget);
      final relatedCard = find.byKey(
        ValueKey('mobile-related-game-${related.first.game.id}'),
      );
      await tester.ensureVisible(relatedCard);
      await tester.pumpAndSettle();
      await tester.tap(relatedCard);
      await tester.pumpAndSettle();
      expect(controller.selectedGame.id, related.first.game.id);
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(controller.selectedGame.id, controller.games.first.id);
      expect(find.text('让好游戏，连接更多人'), findsNothing);
      expect(find.byKey(const ValueKey('mobile-detail-rules')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('mobile-detail-ask-ai')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('mobile-detail-wishlist')),
        findsNothing,
      );
      expect(find.text('FAQ'), findsNothing);
      expect(find.text('加入想玩'), findsNothing);
      expect(find.text('展开全部'), findsNothing);
      if (controller.games.first.mentorPitch.trim().isNotEmpty) {
        expect(find.text(controller.games.first.mentorPitch), findsNothing);
      }
      final favoriteBefore = controller.isFavorite(controller.games.first);
      await tester.tap(
        find.byKey(
          ValueKey('mobile-detail-favorite-${controller.games.first.id}'),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.isFavorite(controller.games.first), !favoriteBefore);
      await tester.tap(find.byKey(const ValueKey('mobile-detail-ask-ai')));
      await tester.pumpAndSettle();
      expect(find.byType(AssistantChatScreen), findsOneWidget);
      expect(
        controller.selectedConversation?.gameId,
        controller.games.first.id,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mobile-tab-home')));
      await tester.pumpAndSettle();
      expect(find.text('最近AI对话'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mobile-tab-ai')));
      await tester.pumpAndSettle();
      expect(find.byType(AssistantChatScreen), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
      expect(
        find.byKey(const ValueKey('assistant-conversations-trigger')),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);
      expect(find.byIcon(Icons.delete_sweep_rounded), findsNothing);
      expect(find.text('语音已准备好'), findsNothing);
      expect(controller.selectedConversation?.isGlobal, isTrue);
      expect(find.text('打开现有 AI 助手'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('mobile-tab-mine')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mobile-mine-profile')), findsOneWidget);
      expect(find.text('${controller.favoriteCount}'), findsOneWidget);
      expect(find.text('好桌游，让平凡的日子闪闪发光！'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('我的服务'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('我的服务'), findsOneWidget);
      expect(find.text('我的桌游'), findsNothing);
      expect(find.text('活动、评论、系统消息等'), findsOneWidget);
      expect(find.text('语言、偏好设置'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mobile-tab-home')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    var aboutOpened = false;
    await tester.binding.setSurfaceSize(const Size(720, 844));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.buildTheme(controller.palette),
        home: HomeScreen(
          controller: controller,
          onOpenAbout: () => aboutOpened = true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('mobile-home-scroll'))).width,
      kIsWeb ? 720 : 560,
    );
    if (kIsWeb && controller.dailyRecommendedGames.isNotEmpty) {
      final firstRecommendation = controller.dailyRecommendedGames.first;
      final recommendationWidth = tester
          .getSize(
            find.byKey(
              ValueKey('mobile-recommendation-${firstRecommendation.id}'),
            ),
          )
          .width;
      expect(recommendationWidth, greaterThanOrEqualTo((720 - 32 - 20) / 3));
      expect(recommendationWidth, lessThanOrEqualTo(280));
      final attributes = tester.widget<Text>(
        find.byKey(
          ValueKey(
            'mobile-recommendation-attributes-${firstRecommendation.id}',
          ),
        ),
      );
      expect(attributes.data!.split(' / '), hasLength(lessThanOrEqualTo(2)));
      expect(attributes.overflow, TextOverflow.clip);
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
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.binding.setSurfaceSize(const Size(320, 640));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mobile-tab-mine')));
    await tester.pumpAndSettle();
    final settingsEntry = find.byKey(const ValueKey('mobile-mine-service-1'));
    await tester.scrollUntilVisible(
      settingsEntry,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(
      find.byKey(const ValueKey('mobile-mine-scroll')),
      const Offset(0, -180),
    );
    await tester.pumpAndSettle();
    await tester.tap(settingsEntry);
    await tester.pumpAndSettle();
    expect(find.byType(MobileSettingsScreen), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile-settings-screen')),
      findsOneWidget,
    );
    expect(find.byType(BottomSheet), findsNothing);
    await tester.binding.setSurfaceSize(const Size(720, 1080));
    await tester.pumpAndSettle();
    final appBarBottom = tester.getBottomLeft(find.byType(AppBar)).dy;
    final languageTop = tester
        .getTopLeft(find.byKey(const ValueKey('mobile-settings-language')))
        .dy;
    expect(languageTop - appBarBottom, lessThan(100));
    await tester.binding.setSurfaceSize(const Size(320, 640));
    await tester.pumpAndSettle();

    final languageChanged = Completer<void>();
    void onLanguageChanged() {
      if (controller.language == AppLanguage.en &&
          !languageChanged.isCompleted) {
        languageChanged.complete();
      }
    }

    controller.addListener(onLanguageChanged);
    await tester.tap(find.text('English'));
    await tester.runAsync(
      () => languageChanged.future.timeout(const Duration(seconds: 5)),
    );
    controller.removeListener(onLanguageChanged);
    await tester.pumpAndSettle();
    expect(controller.language, AppLanguage.en);
    expect(find.byType(MobileSettingsScreen), findsOneWidget);
    await tester.tap(find.text('Midnight Table'));
    await tester.pumpAndSettle();
    expect(controller.colorScheme, ColorSchemeOption.classic);

    final aiSection = find.byKey(const ValueKey('mobile-settings-ai'));
    await tester.ensureVisible(aiSection);
    await tester.tap(aiSection);
    await tester.pumpAndSettle();
    expect(find.text(controller.copy.aiApiPresetLabel), findsOneWidget);
    final reasoningDropdown = tester.widget<DropdownButton<AiReasoningEffort>>(
      find.byType(DropdownButton<AiReasoningEffort>),
    );
    expect(
      reasoningDropdown.items!.map((item) => item.value),
      isNot(contains(AiReasoningEffort.automatic)),
    );
    expect(
      reasoningDropdown.items!.map((item) => item.value),
      isNot(contains(AiReasoningEffort.none)),
    );

    final speedDropdown = tester.widget<DropdownButton<AiResponseSpeed>>(
      find.byType(DropdownButton<AiResponseSpeed>),
    );
    expect(speedDropdown.value, AiResponseSpeed.standard);
    expect(speedDropdown.items!.map((item) => item.value), [
      AiResponseSpeed.standard,
      AiResponseSpeed.fast,
    ]);
    expect(find.text(controller.copy.aiApiResponseSpeedHint), findsNothing);
    expect(find.textContaining('请求值：'), findsNothing);
    final speedField = find.byType(DropdownButton<AiResponseSpeed>);
    await tester.ensureVisible(speedField);
    await tester.tap(speedField);
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .text(controller.copy.aiApiResponseSpeedName(AiResponseSpeed.fast))
          .last,
    );
    await tester.pumpAndSettle();
    expect(find.text(controller.copy.aiApiResponseSpeedHint), findsOneWidget);

    final aboutEntry = find.byKey(const ValueKey('mobile-settings-about'));
    await tester.ensureVisible(aboutEntry);
    await tester.tap(aboutEntry);
    expect(aboutOpened, isTrue);
    expect(tester.takeException(), isNull);
  });
  _registerMobileNationalDayTests();
  testWidgets(
    'compact cover uses the same Hero into detail and returns safely',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final controller = _controller(ttsService: _UnavailableTtsService());
      addTearDown(controller.dispose);
      rootBundle.clear();
      await tester.runAsync(controller.reloadGames);
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.buildTheme(controller.palette),
          home: HomeScreen(controller: controller, onOpenAbout: () {}),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mobile-tab-library')));
      await tester.pumpAndSettle();
      final card = find.byKey(
        ValueKey('mobile-library-game-${controller.games.first.id}'),
      );
      final source = find.descendant(
        of: card,
        matching: find.byType(GameCoverSource),
      );
      final sourceHero = tester.widget<Hero>(
        find.descendant(of: source, matching: find.byType(Hero)),
      );
      await tester.tap(source);
      await tester.pumpAndSettle();
      final detail = tester.widget<GameDetailScreen>(
        find.byType(GameDetailScreen),
      );
      expect(detail.coverOrigin?.tag, sourceHero.tag);
      expect(detail.coverOrigin?.path, controller.games.first.coverAssetPath);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Hero && widget.tag == sourceHero.tag,
        ),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(card, findsOneWidget);
      expect(find.byType(GameDetailScreen), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

AppController _controller({
  TtsService? ttsService,
  PreferencesService? preferences,
}) => AppController(
  preferencesService: preferences ?? PreferencesService(),
  aiService: _UnusedAiService(),
  gameManifestService: GameManifestService(),
  remoteAssetService: _NoNetworkAssetService(),
  speechService: SpeechService(),
  ttsService: ttsService ?? TtsService(),
);

class _UnavailableTtsService extends TtsService {
  @override
  bool get isAvailable => false;
}

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
