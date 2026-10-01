part of '../desktop_workspace_test.dart';

void _registerDesktopLibraryTests(_DesktopWorkspaceTestContext context) {
  testWidgets('rule links show real scoped files without the abstract drawer', (
    tester,
  ) async {
    final first = context.controller.games[0];
    final second = context.controller.games[1];
    DesktopLibraryResource file(GameInfo game, String id) =>
        DesktopLibraryResource(
          id: id,
          gameSlug: game.slug,
          gameTitle: game.title,
          remotePath: game.rulebookAssetPath,
          title: '规则书',
          language: 'cn',
          type: DesktopLibraryResourceType.rulebook,
          format: DesktopLibraryResourceFormat.markdown,
          isRemote: false,
        );
    await tester.runAsync(() async {
      await context.preferences.saveDesktopLibraryResources([
        file(first, 'scoped-first'),
        file(second, 'scoped-second'),
      ]);
      await context.controller.refreshLibraryResources();
    });
    expect(context.controller.libraryResources, isNotEmpty);
    await _mount(tester, context.controller, const Size(1280, 800));
    final search = find.byKey(const ValueKey('desktop-home-search-field'));
    await tester.tap(search);
    await tester.enterText(search, first.title);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('查看规则资料').first);
    await tester.pumpAndSettle();
    final library = tester.widget<DesktopLibraryPane>(
      find.byType(DesktopLibraryPane),
    );
    expect(library.gameSlug, first.slug);
    expect(find.text('条款问答'), findsNothing);
    expect(find.text('规则速览'), findsNothing);
    expect(find.text('规则裁决问答'), findsNothing);
    expect(
      find.byKey(const ValueKey('library-item-scoped-first')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('library-item-scoped-second')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('library-more-scoped-first')));
    await tester.pumpAndSettle();
    expect(find.text(context.controller.copy.desktopOpen), findsWidgets);
    expect(find.text(context.controller.copy.desktopDownload), findsWidgets);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部资料'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DesktopLibraryPane>(find.byType(DesktopLibraryPane))
          .gameSlug,
      isNull,
    );
    expect(
      find.byKey(const ValueKey('library-item-scoped-second')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('favorites page starts empty and links back to the library', (
    tester,
  ) async {
    await _mount(tester, context.controller, const Size(1280, 800));
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

  testWidgets('home shows only backed personal statistics', (tester) async {
    await _mount(tester, context.controller, const Size(1280, 800));
    expect(find.text('我的喜欢'), findsWidgets);
    expect(find.text('AI对话'), findsOneWidget);
    expect(find.text('我的活动'), findsNothing);
    expect(find.text('想玩游戏'), findsNothing);
    expect(find.text('我的投票'), findsNothing);
    expect(find.text('我的收藏'), findsNothing);
  });

  test('favorite state is persisted and can be toggled repeatedly', () async {
    final game = context.controller.games.first;
    expect(await context.controller.toggleFavorite(game), isTrue);
    expect(context.controller.isFavorite(game), isTrue);
    expect(context.controller.favoriteCount, 1);
    final stored = await context.preferences.loadFavoriteGames();
    expect(stored, hasLength(1));
    expect(stored.single.gameSlug, game.slug);
    expect(stored.single.createdAt, isNotNull);
    expect(await context.controller.toggleFavorite(game), isTrue);
    expect(context.controller.isFavorite(game), isFalse);
    expect(context.controller.favoriteCount, 0);
  });

  testWidgets('detail favorite button keeps its size while state crossfades', (
    tester,
  ) async {
    await _mount(tester, context.controller, const Size(1440, 800));
    await _navigate(tester, '游戏库');
    final game = context.controller.games.first;
    await tester.tap(find.byKey(ValueKey<String>('desktop-poster-${game.id}')));
    await tester.pumpAndSettle();

    final button = find.byKey(
      const ValueKey<String>('desktop-detail-favorite-button'),
    );
    expect(button, findsOneWidget);
    expect(tester.getSize(button), const Size(108, 48));
    expect(
      find.descendant(of: button, matching: find.text('喜欢')),
      findsOneWidget,
    );

    await tester.runAsync(() async {
      expect(
        await context.controller.toggleFavorite(context.controller.games.first),
        isTrue,
      );
    });
    await tester.pump();
    await tester.pump();
    expect(tester.getSize(button), const Size(108, 48));
    expect(
      find.descendant(of: button, matching: find.byType(AnimatedSwitcher)),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(tester.getSize(button), const Size(108, 48));
    expect(context.controller.isFavorite(game), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'responsive shell switches between full sidebar, rail and drawer',
    (tester) async {
      await _mount(tester, context.controller, const Size(1280, 800));
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
      expect(tester.getSize(fullSidebar).width, 205);
      final homeIcon = find.byKey(
        const ValueKey<String>('desktop-sidebar-icon-sidebar_home.png'),
      );
      final homeLabel = find.descendant(
        of: fullSidebar,
        matching: find.text('首页'),
      );
      final fullHomeIconRect = tester.getRect(homeIcon);
      expect(fullHomeIconRect.size, const Size.square(28));
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
      expect(
        find.byKey(const ValueKey<String>('desktop-sidebar-art')),
        findsNothing,
      );
      final compactHomeIconRect = tester.getRect(homeIcon);
      expect(compactHomeIconRect.size, fullHomeIconRect.size);
      expect(
        compactHomeIconRect.center.dx,
        closeTo(fullHomeIconRect.center.dx, 0.5),
      );
      expect(compactHomeIconRect.top, closeTo(fullHomeIconRect.top, 0.5));
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
    await _mount(tester, context.controller, const Size(1100, 700));
    await _navigate(tester, '游戏库');
    final game = context.controller.games.length > 1
        ? context.controller.games[1]
        : context.controller.games.first;
    final poster = find.byKey(ValueKey<String>('desktop-poster-${game.id}'));
    expect(poster, findsOneWidget);
    await tester.tap(poster);
    await tester.pumpAndSettle();
    expect(find.byType(DesktopGameDetailPane), findsOneWidget);
    expect(context.controller.selectedGame.id, game.id);
    expect(tester.takeException(), isNull);
  });

  testWidgets('related games open another detail and preserve home return', (
    tester,
  ) async {
    await _mount(tester, context.controller, const Size(1280, 800));
    final source = context.controller.dailyRecommendedGames.first;
    await tester.tap(
      find.byKey(
        ValueKey<String>('desktop-home-recommendation-card-${source.id}'),
      ),
    );
    await tester.pumpAndSettle();
    final relatedSection = find.byKey(
      const ValueKey<String>('desktop-related-games-section'),
    );
    expect(relatedSection, findsOneWidget);
    expect(
      find.descendant(of: relatedSection, matching: find.text('相关游戏')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey<String>('detail-tab-1')));
    await tester.pumpAndSettle();
    expect(relatedSection, findsOneWidget);

    final results = find.byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith('related-game-'),
    );
    expect(results, findsWidgets);
    await tester.ensureVisible(results.first);
    await tester.pumpAndSettle();
    await tester.tap(results.first);
    await tester.pumpAndSettle();
    expect(context.controller.selectedGame.id, isNot(source.id));
    expect(find.byTooltip('返回首页'), findsOneWidget);
    expect(find.byType(DesktopGameDetailPane), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'library posters match legacy proportion and hover preview, then open Desktop details',
    (tester) async {
      await _mount(tester, context.controller, const Size(1440, 800));
      await _navigate(tester, '游戏库');
      final GameInfo game = context.controller.games[1];
      final Finder poster = find.byKey(
        ValueKey<String>('desktop-poster-${game.id}'),
      );
      final Rect posterRect = tester.getRect(poster);
      expect(posterRect.width / posterRect.height, closeTo(1 / 1.49, 0.005));
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
      expect(hoveredPoster.transform!.storage[13], -2);
      expect(hoveredPoster.transform!.storage[6], 0);
      final Finder preview = find.byKey(
        ValueKey<String>('desktop-game-hover-preview-${game.id}'),
      );
      expect(preview, findsOneWidget);
      expect(tester.getSize(preview).width, closeTo(290, 1));

      await mouse.moveTo(Offset.zero);
      await tester.pump(const Duration(milliseconds: 130));
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
    await _mount(tester, context.controller, const Size(720, 700));
    await _navigate(tester, '游戏库');
    expect(find.byType(DesktopGamesPane), findsOneWidget);
    await _navigate(tester, 'AI助手');
    expect(find.byType(DesktopAssistantPane), findsOneWidget);
    await _navigate(tester, '设置');
    expect(find.byType(DesktopSettingsPane), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('desktop-settings-ai-provider')),
      findsOneWidget,
    );
    expect(find.text('详细设置'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
