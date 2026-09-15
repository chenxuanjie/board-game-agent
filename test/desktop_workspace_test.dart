import 'dart:async';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/foundation.dart';

import 'package:app_ai_client/app_ai_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:board_game_agent/models/ai_answer_mode.dart';
import 'package:board_game_agent/models/ai_api_config.dart';
import 'package:board_game_agent/models/answer_source.dart';
import 'package:board_game_agent/models/app_activity.dart';
import 'package:board_game_agent/models/asset_source_config.dart';
import 'package:board_game_agent/models/app_language.dart';
import 'package:board_game_agent/models/board_game_ai_answer.dart';
import 'package:board_game_agent/models/cached_asset.dart';
import 'package:board_game_agent/models/chat_message.dart';
import 'package:board_game_agent/models/color_scheme_option.dart';
import 'package:board_game_agent/models/favorite_game_record.dart';
import 'package:board_game_agent/models/game_info.dart';
import 'package:board_game_agent/models/remote_asset_file.dart';
import 'package:board_game_agent/models/recent_game_record.dart';
import 'package:board_game_agent/models/search_history_record.dart';
import 'package:board_game_agent/services/ai_service.dart';
import 'package:board_game_agent/services/game_manifest_service.dart';
import 'package:board_game_agent/services/preferences_service.dart';
import 'package:board_game_agent/services/remote_asset_service.dart';
import 'package:board_game_agent/services/speech_service.dart';
import 'package:board_game_agent/services/tts_service.dart';
import 'package:board_game_agent/state/app_controller.dart';
import 'package:board_game_agent/theme/app_palette.dart';
import 'package:board_game_agent/ui/desktop/business_panes.dart';
import 'package:board_game_agent/ui/desktop/workspace.dart';
import 'package:board_game_agent/ui/desktop/theme.dart';
import 'package:board_game_agent/ui/desktop/sidebar.dart';
import 'package:board_game_agent/ui/desktop/home_pane.dart';
import 'package:board_game_agent/ui/desktop/games_pane.dart';
import 'package:board_game_agent/ui/desktop/favorites_pane.dart';
import 'package:board_game_agent/ui/desktop/game_detail_pane.dart';
import 'package:board_game_agent/ui/desktop/settings_pane.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppController controller;
  late _InMemoryPreferencesService preferences;

  setUp(() async {
    preferences = _InMemoryPreferencesService();
    controller = await _createController(preferencesService: preferences);
    controller.selectGame('puerto-rico');
  });
  tearDown(() {
    controller.dispose();
  });

  test('Desktop theme keeps the host platform and shared content', () {
    final theme = buildDesktopTheme();
    expect(theme.platform, defaultTargetPlatform);
    expect(theme.brightness, Brightness.light);
    expect(theme.useMaterial3, isTrue);
    expect(theme.scaffoldBackgroundColor, DesktopColors.background);
    expect(theme.extensions, isNotEmpty);
  });

  for (final size in const [
    Size(1280, 800),
    Size(1100, 700),
    Size(720, 700),
    Size(1920, 1080),
  ]) {
    testWidgets('home, games and settings navigate without overflow at $size', (
      tester,
    ) async {
      await _mount(tester, controller, size);
      expect(find.byType(DesktopHomePane), findsOneWidget);
      final home = find.byType(DesktopHomePane);
      expect(controller.games, isNotEmpty);
      for (final game in controller.games.take(5)) {
        expect(
          find.descendant(of: home, matching: find.text(game.title)),
          findsWidgets,
        );
      }
      expect(tester.takeException(), isNull);
      await _navigate(tester, '游戏库');
      expect(find.byType(DesktopGamesPane), findsOneWidget);
      expect(find.byType(DesktopHomePane), findsNothing);
      expect(find.text('当前桌游'), findsNothing);
      expect(find.text('桌游爱好者'), findsNothing);
      expect(find.text('收藏总数'), findsNothing);
      for (final game in controller.games) {
        expect(
          find.byKey(ValueKey('desktop-poster-${game.id}')),
          findsOneWidget,
        );
      }
      // These titles occur in the reference mock data, not the bundled manifest.
      for (final title in ['卡坦岛', '璀璨王国']) {
        expect(controller.games.where((game) => game.title == title), isEmpty);
        expect(find.text(title), findsNothing);
      }
      expect(tester.takeException(), isNull);
      await _navigate(tester, '设置');
      expect(find.byType(DesktopSettingsPane), findsOneWidget);
      expect(find.text('语言设置'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('完整设置'));
      await tester.pumpAndSettle();
      expect(find.text('完整设置').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _navigate(tester, '首页');
      expect(find.byType(DesktopHomePane), findsOneWidget);
      expect(find.byType(DesktopSettingsPane), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('hidden and unsupported desktop routes stay unavailable', (
    tester,
  ) async {
    await _mount(tester, controller, const Size(1280, 800));
    expect(
      find.descendant(
        of: find.byType(DesktopSidebar),
        matching: find.text('排行榜'),
      ),
      findsNothing,
    );
    for (final label in ['社区']) {
      await _navigate(tester, label);
      expect(find.byType(DesktopHomePane), findsNothing);
      final title = find.text(label).evaluate().where((element) {
        return element.findAncestorWidgetOfExactType<DesktopSidebar>() == null;
      });
      expect(title, hasLength(1));
      final body = find
          .ancestor(of: find.text(label).last, matching: find.byType(Column))
          .first;
      expect(
        find.descendant(of: body, matching: find.text('未开放')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('favorites page starts empty and links back to the library', (
    tester,
  ) async {
    await _mount(tester, controller, const Size(1280, 800));
    await _navigate(tester, '我的喜欢');
    expect(find.byType(DesktopFavoritesPane), findsOneWidget);
    expect(find.text('还没有喜欢的桌游'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('desktop-favorites-open-library')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DesktopGamesPane), findsOneWidget);
    expect(find.byType(DesktopFavoritesPane), findsNothing);
  });

  testWidgets('home uses likes and activity terminology', (tester) async {
    await _mount(tester, controller, const Size(1280, 800));
    expect(find.text('我的喜欢'), findsWidgets);
    expect(find.text('我的活动'), findsOneWidget);
    expect(find.text('我的投票'), findsNothing);
    expect(find.text('我的收藏'), findsNothing);
  });

  test('favorite state is persisted and can be toggled repeatedly', () async {
    final game = controller.games.first;
    expect(await controller.toggleFavorite(game), isTrue);
    expect(controller.isFavorite(game), isTrue);
    expect(controller.favoriteCount, 1);
    final stored = await preferences.loadFavoriteGames();
    expect(stored, hasLength(1));
    expect(stored.single.gameSlug, game.slug);
    expect(stored.single.createdAt, isNotNull);
    expect(await controller.toggleFavorite(game), isTrue);
    expect(controller.isFavorite(game), isFalse);
    expect(controller.favoriteCount, 0);
  });

  testWidgets('favorite button keeps its size while state crossfades', (
    tester,
  ) async {
    await _mount(tester, controller, const Size(1440, 800));
    await _navigate(tester, '游戏库');

    final button = find.byKey(
      const ValueKey<String>('desktop-preview-favorite-button'),
    );
    expect(button, findsOneWidget);
    expect(tester.getSize(button), const Size(104, 40));
    expect(
      find.descendant(of: button, matching: find.text('喜欢')),
      findsOneWidget,
    );

    await tester.runAsync(() async {
      expect(await controller.toggleFavorite(controller.games.first), isTrue);
    });
    await tester.pump();
    await tester.pump();
    expect(tester.getSize(button), const Size(104, 40));
    expect(
      find.descendant(of: button, matching: find.byType(AnimatedSwitcher)),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(tester.getSize(button), const Size(104, 40));
    expect(controller.isFavorite(controller.games.first), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'responsive shell switches between full sidebar, rail and drawer',
    (tester) async {
      await _mount(tester, controller, const Size(1280, 800));
      expect(
        find.byKey(const ValueKey<String>('desktop-sidebar-full')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('desktop-sidebar-rail')),
        findsNothing,
      );
      final fullSidebar = find.byKey(
        const ValueKey<String>('desktop-sidebar-full'),
      );
      final homeIcon = find.byKey(
        const ValueKey<String>('desktop-sidebar-icon-sidebar_home.png'),
      );
      final homeLabel = find.descendant(
        of: fullSidebar,
        matching: find.text('首页'),
      );
      expect(tester.getSize(homeIcon), const Size.square(24));
      expect(
        tester.getTopLeft(homeLabel).dx - tester.getTopRight(homeIcon).dx,
        closeTo(10, 0.1),
      );

      await tester.binding.setSurfaceSize(const Size(1100, 700));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('desktop-sidebar-rail')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await tester.binding.setSurfaceSize(const Size(720, 700));
      await tester.pumpAndSettle();
      expect(find.byType(DesktopSidebar), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('desktop-open-navigation')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('desktop-open-navigation')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('desktop-sidebar-full')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('compact library opens a card directly and hides preview', (
    tester,
  ) async {
    await _mount(tester, controller, const Size(1100, 700));
    await _navigate(tester, '游戏库');
    final game = controller.games.length > 1
        ? controller.games[1]
        : controller.games.first;
    final poster = find.byKey(ValueKey<String>('desktop-poster-${game.id}'));
    expect(poster, findsOneWidget);
    await tester.tap(poster);
    await tester.pumpAndSettle();
    expect(find.byType(DesktopGameDetailPane), findsOneWidget);
    expect(controller.selectedGame.id, game.id);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'library posters match legacy proportion and hover preview, then open Desktop details',
    (tester) async {
      await _mount(tester, controller, const Size(1440, 800));
      await _navigate(tester, '游戏库');
      final GameInfo game = controller.games[1];
      final Finder poster = find.byKey(
        ValueKey<String>('desktop-poster-${game.id}'),
      );
      final Rect posterRect = tester.getRect(poster);
      expect(posterRect.width / posterRect.height, closeTo(2 / 3, 0.005));
      expect(
        find.descendant(of: poster, matching: find.byType(AnimatedOpacity)),
        findsNothing,
      );

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(posterRect.center);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 420));
      final AnimatedContainer hoveredPoster = tester.widget<AnimatedContainer>(
        poster,
      );
      expect(hoveredPoster.transform!.storage[6].abs(), greaterThan(0));
      final Finder preview = find.byKey(
        ValueKey<String>('desktop-game-hover-preview-${game.id}'),
      );
      expect(preview, findsOneWidget);
      expect(tester.getSize(preview).width, closeTo(290, 1));

      await mouse.moveTo(Offset.zero);
      await tester.pump(const Duration(milliseconds: 130));
      await tester.tap(poster);
      await tester.pumpAndSettle();
      expect(find.byType(DesktopGameDetailPane), findsNothing);
      await tester.tap(poster);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('desktop-game-detail')),
        findsOneWidget,
      );
      expect(find.byType(DesktopGameDetailPane), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('narrow drawer reaches every migrated workspace', (tester) async {
    await _mount(tester, controller, const Size(720, 700));
    await _navigate(tester, '游戏库');
    expect(find.byType(DesktopGamesPane), findsOneWidget);
    await _navigate(tester, 'AI助手');
    expect(find.byType(DesktopAssistantPane), findsOneWidget);
    await _navigate(tester, '设置');
    expect(find.byType(DesktopSettingsPane), findsOneWidget);
    await tester.ensureVisible(find.text('完整设置'));
    await tester.tap(find.text('完整设置'));
    await tester.pumpAndSettle();
    expect(find.byType(DesktopAdvancedSettingsPane), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home rules query shortcut navigates to the shared library', (
    tester,
  ) async {
    await _mount(tester, controller, const Size(1280, 800));
    await tester.tap(
      find.byKey(const ValueKey<String>('home-quick-entry-rules')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DesktopGamesPane), findsNothing);
    expect(find.byType(DesktopHomePane), findsNothing);
    expect(find.byType(DesktopLibraryPane), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('library filter tabs update the selected state', (tester) async {
    await _mount(tester, controller, const Size(1280, 800));
    await tester.tap(
      find.byKey(const ValueKey<String>('home-quick-entry-rules')),
    );
    await tester.pumpAndSettle();

    final allButton = find.widgetWithText(
      TextButton,
      controller.copy.desktopAll,
    );
    final faqButton = find.widgetWithText(
      TextButton,
      controller.copy.desktopFaq,
    );
    expect(allButton, findsOneWidget);
    expect(faqButton, findsOneWidget);
    expect(
      tester
          .widget<TextButton>(allButton)
          .style
          ?.backgroundColor
          ?.resolve(<WidgetState>{}),
      isNotNull,
    );
    expect(
      tester
          .widget<TextButton>(faqButton)
          .style
          ?.backgroundColor
          ?.resolve(<WidgetState>{}),
      isNull,
    );

    await tester.tap(faqButton);
    await tester.pump();

    expect(
      tester
          .widget<TextButton>(allButton)
          .style
          ?.backgroundColor
          ?.resolve(<WidgetState>{}),
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(faqButton)
          .style
          ?.backgroundColor
          ?.resolve(<WidgetState>{}),
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('home search filters catalog data and opens a real game', (
    tester,
  ) async {
    await _mount(tester, controller, const Size(1280, 800));
    final GameInfo game = controller.games.first;
    final String query = game.title.substring(0, 2);
    final Finder searchField = find.byKey(
      const ValueKey<String>('desktop-home-search-field'),
    );

    await tester.tap(searchField);
    await tester.enterText(searchField, query);
    await tester.pumpAndSettle();

    expect(
      find.byKey(ValueKey<String>('desktop-search-result-${game.id}')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(
      find.byKey(ValueKey<String>('desktop-search-result-${game.id}')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DesktopGameDetailPane), findsOneWidget);
    expect(controller.selectedGame.id, game.id);
    expect(
      find.byKey(const ValueKey<String>('desktop-home-search-overlay')),
      findsNothing,
    );
    await tester.tap(find.byTooltip('返回首页'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(searchField).controller!.text, isEmpty);
    await tester.tap(searchField);
    await tester.pumpAndSettle();
    expect(find.text('最近搜索'), findsOneWidget);
    expect(find.widgetWithText(InputChip, query), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('recently viewed games are shown on home and deduplicated', (
    tester,
  ) async {
    final GameInfo first = controller.games[0];
    final GameInfo second = controller.games[1];

    unawaited(controller.recordRecentlyViewed(first));
    unawaited(controller.recordRecentlyViewed(second));
    unawaited(controller.recordRecentlyViewed(first));
    await _mount(tester, controller, const Size(1280, 800), settle: false);
    await tester.pump();

    expect(controller.recentlyViewedGames.map((game) => game.slug), <String>[
      first.slug,
      second.slug,
    ]);
    expect(
      find.byKey(ValueKey<String>('desktop-recent-game-${first.id}')),
      findsOneWidget,
    );
    final firstTile = find.byKey(
      ValueKey<String>('desktop-recent-game-${first.id}'),
    );
    final firstThumbnail = find.byKey(
      ValueKey<String>('desktop-recent-thumbnail-${first.id}'),
    );
    expect(tester.getSize(firstTile).width, lessThanOrEqualTo(126.1));
    expect(
      tester.getSize(firstThumbnail).width /
          tester.getSize(firstThumbnail).height,
      closeTo(16 / 9, 0.01),
    );
    expect(find.textContaining('上次浏览：'), findsNWidgets(2));
    final recentPanel = find.byKey(
      const ValueKey<String>('desktop-home-recent-panel'),
    );
    expect(
      find.descendant(of: recentPanel, matching: find.text('未开放')),
      findsNothing,
    );

    final secondTile = find.byKey(
      ValueKey<String>('desktop-recent-game-${second.id}'),
    );
    await tester.ensureVisible(secondTile);
    await tester.tap(secondTile);
    await tester.pump();
    expect(find.byType(DesktopGameDetailPane), findsOneWidget);
    expect(controller.recentlyViewedGames.first.slug, second.slug);
    expect(find.byTooltip('返回首页'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'home recommendation header aligns more action and returns home',
    (tester) async {
      await _mount(tester, controller, const Size(1280, 800));
      final Finder home = find.byType(DesktopHomePane);
      final Finder header = find.byKey(
        const ValueKey<String>('desktop-home-recommendation-header'),
      );
      final Finder moreText = find.descendant(
        of: header,
        matching: find.text('查看更多'),
      );
      final Finder moreAction = find
          .ancestor(of: moreText, matching: find.byType(InkWell))
          .first;

      expect(
        find.descendant(of: home, matching: find.text('今日推荐')),
        findsOneWidget,
      );
      expect(
        tester.getRect(header).right - tester.getRect(moreAction).right,
        lessThan(1),
      );

      final GameInfo game = controller.games.first;
      await tester.tap(
        find.descendant(of: home, matching: find.text(game.title)).first,
      );
      await tester.pumpAndSettle();
      expect(find.byType(DesktopGameDetailPane), findsOneWidget);
      expect(find.byTooltip('返回首页'), findsOneWidget);

      await tester.tap(find.byTooltip('返回首页'));
      await tester.pumpAndSettle();
      expect(find.byType(DesktopHomePane), findsOneWidget);
      expect(find.byType(DesktopGameDetailPane), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('home search handles empty results without inline clear action', (
    tester,
  ) async {
    await _mount(tester, controller, const Size(1280, 800));
    final Finder searchField = find.byKey(
      const ValueKey<String>('desktop-home-search-field'),
    );
    await tester.tap(searchField);
    await tester.enterText(searchField, '肯定不存在的桌游关键字');
    await tester.pumpAndSettle();

    expect(find.textContaining('没有找到'), findsOneWidget);
    expect(find.text('清空关键词'), findsNothing);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('清空搜索'));
    await tester.pumpAndSettle();
    expect(find.textContaining('没有找到'), findsNothing);
    expect(find.text('最近搜索'), findsOneWidget);
    expect(find.text('肯定不存在的桌游关键字'), findsOneWidget);
    await tester.tap(find.text('清空记录'));
    await tester.pumpAndSettle();
    expect(find.text('暂无最近搜索'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('desktop-home-search-overlay')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty search results do not show a game library action', (
    tester,
  ) async {
    await _mount(tester, controller, const Size(1280, 800));
    final Finder searchField = find.byKey(
      const ValueKey<String>('desktop-home-search-field'),
    );
    await tester.tap(searchField);
    await tester.enterText(searchField, '肯定不存在的桌游关键字');
    await tester.pumpAndSettle();

    expect(find.text('没有找到“肯定不存在的桌游关键字”'), findsOneWidget);
    expect(find.text('打开游戏库'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final Size size in const <Size>[
    Size(1280, 800),
    Size(720, 700),
    Size(600, 700),
  ]) {
    testWidgets('home search panel fits the workspace at $size', (
      tester,
    ) async {
      await _mount(tester, controller, size);
      await tester.tap(
        find.byKey(const ValueKey<String>('desktop-home-search-field')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('desktop-home-search-overlay')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'home library load failures are shown in notifications, not inline',
    (tester) async {
      await controller.refreshLibraryResources();
      expect(controller.libraryLoadError, isNotNull);
      expect(
        controller.activities.any(
          (activity) => activity.kind == AppActivityKind.libraryLoadFailed,
        ),
        isTrue,
      );

      await _mount(tester, controller, const Size(1995, 1248));
      expect(find.text('资料加载失败，请在资料库重试。'), findsNothing);
      expect(find.text('打开资料库'), findsNothing);

      await tester.tap(find.byTooltip('通知').hitTestable());
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('desktop-activity-popup')),
        findsOneWidget,
      );
      expect(find.text('资料加载失败'), findsOneWidget);
      expect(find.textContaining('打开资料库可重试'), findsOneWidget);

      await tester.tap(find.text('资料加载失败'));
      await tester.pumpAndSettle();
      expect(find.byType(DesktopLibraryPane), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('empty game filters do not insert an empty-state panel', (
    tester,
  ) async {
    await _mount(tester, controller, const Size(1280, 800));
    await _navigate(tester, '游戏库');
    expect(
      controller.games.where(
        (game) =>
            '${game.categoryLine} ${game.keywords.join(' ')}'.contains('合作') &&
            game.supportedPlayers.any((players) => players >= 5),
      ),
      isEmpty,
    );

    await tester.tap(
      find.descendant(
        of: find.byType(DesktopGamesPane),
        matching: find.text('合作'),
      ),
    );
    await tester.tap(find.text('筛选'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('5+')),
    );
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();

    expect(find.text('暂无符合条件的游戏'), findsNothing);
    expect(find.text('请选择游戏'), findsNothing);
    expect(find.text('暂无游戏，请在资料库检查资源。'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home hero exposes three manually selectable carousel pages', (
    tester,
  ) async {
    await _mount(tester, controller, const Size(1280, 800));
    final frame = find.byKey(const ValueKey<String>('home-hero-frame'));
    final initialFrame = tester.getRect(frame);
    expect(
      initialFrame.width / initialFrame.height,
      closeTo(2169 / 725, 0.005),
    );
    expect(
      find.byKey(const ValueKey<String>('home-hero-carousel')),
      findsOneWidget,
    );
    for (var index = 0; index < 3; index++) {
      expect(
        find.byKey(ValueKey<String>('home-hero-dot-$index')),
        findsOneWidget,
      );
    }
    await tester.tap(find.byKey(const ValueKey<String>('home-hero-dot-1')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('home-hero-page-1')),
      findsOneWidget,
    );
    expect(tester.getRect(frame), initialFrame);
    await tester.tap(find.byKey(const ValueKey<String>('home-hero-dot-2')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('home-hero-page-2')),
      findsOneWidget,
    );
    expect(tester.getRect(frame), initialFrame);
    expect(
      find.byKey(const ValueKey<String>('desktop-home-library-flame')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('desktop-sidebar-logo')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('desktop-sidebar-art')),
      findsOneWidget,
    );
    final sidebarArt = tester.widget<Image>(
      find.byKey(const ValueKey<String>('desktop-sidebar-art')),
    );
    expect(sidebarArt.fit, BoxFit.contain);
    expect(sidebarArt.alignment, Alignment.bottomCenter);
    for (final asset in [
      'sidebar_home.png',
      'sidebar_library.png',
      'sidebar_ai.png',
      'sidebar_likes.png',
      'sidebar_community.png',
      'sidebar_settings.png',
    ]) {
      final icon = find.byKey(ValueKey<String>('desktop-sidebar-icon-$asset'));
      expect(icon, findsOneWidget);
      expect(tester.getSize(icon), const Size(24, 24));
    }
    expect(tester.takeException(), isNull);
  });

  for (final size in const [
    Size(1280, 800),
    Size(1100, 700),
    Size(720, 700),
    Size(600, 700),
  ]) {
    testWidgets('V5 game detail opens with real data at $size', (tester) async {
      await _mount(tester, controller, size);
      await _navigate(tester, '游戏库');
      final game = controller.games.first;
      final poster = find.byKey(ValueKey<String>('desktop-poster-${game.id}'));
      expect(poster, findsOneWidget);
      await tester.tap(poster);
      await tester.pumpAndSettle();
      expect(find.byType(DesktopGameDetailPane), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('desktop-game-detail')),
        findsOneWidget,
      );
      expect(find.text(game.title), findsWidgets);
      expect(find.text(game.subtitle), findsWidgets);
      expect(find.text('询问 AI'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('detail-tab-2')),
      );
      await tester.tap(find.byKey(const ValueKey<String>('detail-tab-2')));
      await tester.pumpAndSettle();
      expect(find.text('玩家评价'), findsWidgets);
      expect(find.text('未开放'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.byTooltip('返回游戏库'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('返回游戏库'));
      await tester.pumpAndSettle();
      expect(find.byType(DesktopGamesPane), findsOneWidget);
      expect(find.byType(DesktopGameDetailPane), findsNothing);
    });
  }

  testWidgets('AI hero banner opens a visible assistant on a wide desktop', (
    tester,
  ) async {
    await _mount(tester, controller, const Size(1995, 1248));
    await tester.tap(find.byKey(const ValueKey<String>('home-hero-dot-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('home-hero-page-2')));
    await tester.pumpAndSettle();

    expect(find.byType(DesktopAssistantPane), findsOneWidget);
    final composer = find.byKey(const ValueKey<String>('desktop-composer-box'));
    expect(composer, findsOneWidget);
    expect(composer.hitTestable(), findsOneWidget);
    expect(tester.getSize(composer).width, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('assistant runs inside the Warmwood Study Desktop shell', (
    tester,
  ) async {
    await _mount(tester, controller, const Size(1280, 800));
    await _navigate(tester, 'AI助手');
    expect(find.byType(DesktopAssistantPane), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('desktop-composer-box')),
      findsOneWidget,
    );
    final context = tester.element(
      find.byKey(const ValueKey<String>('desktop-composer-box')),
    );
    expect(AppPalette.of(context).scheme, ColorSchemeOption.warmwoodStudy);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'settings opens existing advanced configuration and invokes About',
    (tester) async {
      var aboutCalls = 0;
      await _mount(
        tester,
        controller,
        const Size(1280, 800),
        onOpenAbout: () => aboutCalls++,
      );
      await _navigate(tester, '设置');
      await tester.ensureVisible(find.text('关于'));
      await tester.tap(find.text('关于'));
      await tester.pumpAndSettle();
      expect(aboutCalls, 1);
      await tester.ensureVisible(find.text('完整设置'));
      await tester.tap(find.text('完整设置'));
      await tester.pumpAndSettle();
      expect(find.byType(DesktopSettingsPane), findsNothing);
      expect(find.byType(DesktopAdvancedSettingsPane), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _mount(
  WidgetTester tester,
  AppController controller,
  Size size, {
  VoidCallback? onOpenAbout,
  bool settle = true,
}) async {
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.binding.setSurfaceSize(size);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildDesktopTheme(),
      home: DesktopWorkspace(
        controller: controller,
        onOpenAbout: onOpenAbout ?? () {},
        enableNativeWindowControls: false,
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 500));
  }
}

Future<void> _navigate(WidgetTester tester, String label) async {
  if (find.byType(DesktopSidebar).evaluate().isEmpty) {
    await tester.tap(
      find.byKey(const ValueKey<String>('desktop-open-navigation')),
    );
    await tester.pumpAndSettle();
  }
  final textItem = find.descendant(
    of: find.byType(DesktopSidebar),
    matching: find.text(label),
  );
  if (textItem.evaluate().isNotEmpty) {
    await tester.tap(textItem);
  } else {
    await tester.tap(find.byTooltip(label));
  }
  await tester.pumpAndSettle();
}

Future<AppController> _createController({
  PreferencesService? preferencesService,
}) async {
  if (preferencesService == null) {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  }
  final AppController controller = AppController(
    preferencesService: preferencesService ?? PreferencesService(),
    aiService: _FakeAiService(),
    gameManifestService: GameManifestService(),
    remoteAssetService: _NoNetworkAssetService(),
    speechService: SpeechService(),
    ttsService: TtsService(),
  );
  await controller.reloadGames();
  return controller;
}

class _InMemoryPreferencesService extends PreferencesService {
  Map<String, DateTime> _favoriteGames = <String, DateTime>{};
  List<SearchHistoryRecord> _searchHistory = <SearchHistoryRecord>[];
  List<RecentGameRecord> _recentGames = <RecentGameRecord>[];

  @override
  Future<void> clearSelectedConversationId() async {}

  @override
  Future<void> saveSelectedConversationId(String conversationId) async {}

  @override
  Future<List<FavoriteGameRecord>> loadFavoriteGames() async => _favoriteGames
      .entries
      .map(
        (entry) =>
            FavoriteGameRecord(gameSlug: entry.key, createdAt: entry.value),
      )
      .toList(growable: false);

  @override
  Future<void> saveFavoriteGames(Iterable<FavoriteGameRecord> records) async {
    _favoriteGames = <String, DateTime>{
      for (final record in records) record.gameSlug: record.createdAt,
    };
  }

  @override
  Future<List<RecentGameRecord>> loadRecentGames() async =>
      List<RecentGameRecord>.unmodifiable(_recentGames);

  @override
  Future<void> saveRecentGames(Iterable<RecentGameRecord> records) {
    _recentGames = List<RecentGameRecord>.from(records);
    return Future<void>.value();
  }

  @override
  Future<List<SearchHistoryRecord>> loadSearchHistory() async =>
      const <SearchHistoryRecord>[];

  @override
  Future<void> saveSearchHistory(Iterable<SearchHistoryRecord> records) async {
    _searchHistory = List<SearchHistoryRecord>.from(records);
  }

  @override
  Future<List<String>> loadRecentSearches() async =>
      _searchHistory.map((record) => record.query).toList(growable: false);

  @override
  Future<void> saveRecentSearches(Iterable<String> queries) async {
    final now = DateTime.now().toUtc();
    _searchHistory = queries
        .map((query) => SearchHistoryRecord(query: query, searchedAt: now))
        .toList(growable: false);
  }
}

class _NoNetworkAssetService extends RemoteAssetService {
  _NoNetworkAssetService() : super(client: _NoopHttpClient());

  @override
  Future<File?> cachedFileFor(String remotePath) async => null;

  @override
  Future<CachedAsset?> ensureCached({
    required List<AssetSourceConfig> sources,
    required String remotePath,
    bool forceRefresh = false,
    bool allowCachedFallback = true,
  }) async => null;

  @override
  Future<String?> fetchRemoteText({
    required List<AssetSourceConfig> sources,
    required String remotePath,
  }) async => null;

  @override
  Future<List<RemoteAssetFile>> listFilesRecursively({
    required List<AssetSourceConfig> sources,
    required String remotePath,
    int maxDepth = 6,
    int maxEntries = 1000,
  }) async => const <RemoteAssetFile>[];

  @override
  Future<bool> hasRemoteChanged({
    required List<AssetSourceConfig> sources,
    required String remotePath,
  }) async => false;
}

class _NoopHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return Future<http.StreamedResponse>.error(
      StateError('network disabled for widget test'),
    );
  }
}

class _FakeAiService implements AiService {
  @override
  Future<List<AiModel>> listModels(AiApiConfig config) async {
    return const <AiModel>[];
  }

  @override
  Future<BoardGameAiAnswer> generateReply({
    required String prompt,
    required AppLanguage language,
    required GameInfo game,
    required AiAnswerMode answerMode,
    required bool useGlobalMode,
    required AiApiConfig config,
    required List<AssetSourceConfig> assetSourceConfigs,
    required RemoteAssetService remoteAssetService,
    required List<ChatMessage> conversationHistory,
    bool useCurrentGameKnowledge = false,
  }) async {
    return BoardGameAiAnswer(text: 'test', source: AnswerSource.generalAdvice);
  }

  @override
  Stream<BoardGameAiStreamEvent> streamReply({
    required String prompt,
    required AppLanguage language,
    required GameInfo game,
    required AiAnswerMode answerMode,
    required bool useGlobalMode,
    required AiApiConfig config,
    required List<AssetSourceConfig> assetSourceConfigs,
    required RemoteAssetService remoteAssetService,
    required List<ChatMessage> conversationHistory,
    bool useCurrentGameKnowledge = false,
    Future<void>? abortTrigger,
  }) async* {}

  @override
  Future<AiHealthResult> checkConnection(AiApiConfig config) async {
    return const AiHealthResult(
      success: true,
      message: 'test',
      latency: Duration.zero,
      model: '',
    );
  }

  @override
  void dispose() {}
}
