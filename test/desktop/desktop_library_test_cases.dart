part of '../desktop_workspace_test.dart';

void _registerDesktopLibraryTests(_DesktopWorkspaceTestContext context) {
  testWidgets('rule links show real scoped files without the abstract drawer', (
    tester,
  ) async {
    final first = context.controller.games[0];
    final second = context.controller.games[1];
    await context.controller.refreshLibraryResources();
    final firstResource = context.controller.libraryResources.firstWhere(
      (r) => r.gameSlug == first.slug,
    );
    final secondResource = context.controller.libraryResources.firstWhere(
      (r) => r.gameSlug == second.slug,
    );
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
      find.byKey(ValueKey('library-item-${firstResource.id}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('library-item-${secondResource.id}')),
      findsNothing,
    );
    await tester.tap(find.byKey(ValueKey('library-more-${firstResource.id}')));
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
      context.controller.libraryResources.any((r) => r.id == secondResource.id),
      isTrue,
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

  testWidgets('detail favorite button keeps its size while feedback animates', (
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
    expect(tester.getSize(button), const Size(144, 56));
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
    expect(tester.getSize(button), const Size(144, 56));
    expect(
      find.descendant(of: button, matching: find.byType(FavoriteFeedbackIcon)),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FavoriteFeedbackIcon>(
            find.descendant(
              of: button,
              matching: find.byType(FavoriteFeedbackIcon),
            ),
          )
          .selected,
      isTrue,
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(tester.getSize(button), const Size(144, 56));
    expect(context.controller.isFavorite(game), isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final desktop in [true, false]) {
    for (final fail in [true, false]) {
      testWidgets(
        'favorite intent lights immediately and resolves correctly desktop=$desktop failure=$fail',
        (tester) async {
          final c = context.controller, prefs = context.preferences;
          final game = c.games.first;
          if (desktop) {
            await _mount(tester, c, const Size(1440, 800));
            await _navigate(tester, '游戏库');
            await tester.ensureVisible(
              find.byKey(ValueKey<String>('desktop-poster-${game.id}')),
            );
            await tester.pumpAndSettle();
            await tester.tap(
              find.byKey(ValueKey<String>('desktop-poster-${game.id}')),
            );
            await tester.pumpAndSettle();
          } else {
            await tester.pumpWidget(
              MaterialApp(
                theme: AppTheme.buildTheme(c.palette),
                home: Scaffold(
                  body: Center(
                    child: FavoriteToggleButton(
                      key: const ValueKey('favorite-toggle'),
                      controller: c,
                      game: game,
                    ),
                  ),
                ),
              ),
            );
          }
          final button = find.byKey(
            ValueKey(
              desktop ? 'desktop-detail-favorite-button' : 'favorite-toggle',
            ),
          );
          final writes = prefs.favoriteWrites;
          prefs.favoriteWriteGate = Completer<void>();
          prefs.failFavoriteWrite = fail;
          addTearDown(() {
            if (!prefs.favoriteWriteGate!.isCompleted) {
              prefs.favoriteWriteGate!.complete();
            }
          });
          await tester.tap(button);
          await tester.pump();
          FavoriteFeedbackIcon feedback() =>
              tester.widget<FavoriteFeedbackIcon>(
                find.descendant(
                  of: button,
                  matching: find.byType(FavoriteFeedbackIcon),
                ),
              );
          expect(feedback().selected, isTrue);
          expect(
            find.descendant(
              of: button,
              matching: find.byType(CircularProgressIndicator),
            ),
            findsNothing,
          );
          prefs.favoriteWriteGate!.complete();
          await tester.pump();
          await tester.runAsync(() => Future<void>.delayed(Duration.zero));
          await tester.pumpAndSettle();
          expect(feedback().selected, !fail);
          expect(c.isFavorite(game), !fail);
          expect(prefs.favoriteWrites - writes, 1);
          expect(
            find.byKey(const ValueKey('app-failure-notice')),
            fail ? findsOneWidget : findsNothing,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
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

  testWidgets('detail tabs animate and rapid changes keep the latest panel', (
    tester,
  ) async {
    await _mount(tester, context.controller, const Size(1280, 800));
    final game = context.controller.dailyRecommendedGames.first;
    await tester.tap(
      find.byKey(
        ValueKey<String>('desktop-home-recommendation-card-${game.id}'),
      ),
    );
    await tester.pumpAndSettle();
    final tab0 = find.byKey(const ValueKey<String>('detail-tab-0'));
    final tab1 = find.byKey(const ValueKey<String>('detail-tab-1'));
    final indicator = find.byKey(const ValueKey('detail-tab-indicator'));
    await tester.ensureVisible(tab1);
    await tester.pumpAndSettle();
    final start = tester.getCenter(indicator).dx;
    await tester.tap(tab1);
    await tester.pump();
    final container = find.byKey(const ValueKey('detail-tab-content'));
    final selectedPanel = find.descendant(
      of: container,
      matching: find.byKey(const ValueKey<int>(1)),
    );
    final fade = find
        .ancestor(of: selectedPanel, matching: find.byType(Opacity))
        .first;
    expect(tester.widget<Opacity>(fade).opacity, 0);
    await tester.pump(const Duration(milliseconds: 125));
    final middle = tester.getCenter(indicator).dx;
    expect(middle, greaterThan(start));
    expect(tester.widget<Opacity>(fade).opacity, closeTo(.125, .03));
    await tester.tap(tab0);
    await tester.pump();
    final matchingPanels = find.descendant(
      of: container,
      matching: find.byKey(const ValueKey<int>(0)),
    );
    final activePanels = matchingPanels.evaluate().where((element) {
      final pointer = tester.widget<IgnorePointer>(
        find
            .ancestor(
              of: find.byElementPredicate((candidate) => candidate == element),
              matching: find.byType(IgnorePointer),
            )
            .first,
      );
      return !pointer.ignoring;
    });
    expect(activePanels.length, 1);
    await tester.pumpAndSettle();
    expect(tester.getCenter(indicator).dx, closeTo(start, .1));
    expect(
      find.descendant(
        of: container,
        matching: find.byKey(const ValueKey<int>(0)),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: container,
        matching: find.byKey(const ValueKey<int>(1)),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('detail tabs switch immediately with reduced motion', (
    tester,
  ) async {
    await _mount(
      tester,
      context.controller,
      const Size(1280, 800),
      disableAnimations: true,
    );
    final game = context.controller.dailyRecommendedGames.first;
    await tester.tap(
      find.byKey(
        ValueKey<String>('desktop-home-recommendation-card-${game.id}'),
      ),
    );
    await tester.pumpAndSettle();
    final tab = find.byKey(const ValueKey<String>('detail-tab-1'));
    await tester.ensureVisible(tab);
    await tester.pumpAndSettle();
    await tester.tap(tab);
    await tester.pump();
    await tester.pump();
    final panel = find.byKey(const ValueKey('detail-tab-content'));
    expect(
      find.descendant(of: panel, matching: find.byKey(const ValueKey<int>(1))),
      findsOneWidget,
    );
    expect(
      find.descendant(of: panel, matching: find.byKey(const ValueKey<int>(0))),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('detail panels stay top aligned while their heights change', (
    tester,
  ) async {
    await _mount(tester, context.controller, const Size(1280, 800));
    final game = context.controller.dailyRecommendedGames.first;
    await tester.tap(
      find.byKey(
        ValueKey<String>('desktop-home-recommendation-card-${game.id}'),
      ),
    );
    await tester.pumpAndSettle();
    final tab = find.byKey(const ValueKey<String>('detail-tab-1'));
    await tester.ensureVisible(tab);
    await tester.pumpAndSettle();
    final container = find.byKey(const ValueKey('detail-tab-content'));
    final related = find.byKey(const ValueKey('desktop-related-games-section'));
    for (final index in [1, 0]) {
      await tester.tap(find.byKey(ValueKey<String>('detail-tab-$index')));
      await tester.pump();
      final panel = find.descendant(
        of: container,
        matching: find.byKey(ValueKey<int>(index)),
      );
      final relativeTop = <double>[];
      final relatedTop = <double>[];
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        relativeTop.add(
          tester.getTopLeft(panel).dy - tester.getTopLeft(container).dy,
        );
        relatedTop.add(tester.getTopLeft(related).dy);
      }
      final finalTop = relativeTop.last;
      expect(
        relativeTop.reduce((a, b) => a > b ? a : b) - finalTop,
        lessThanOrEqualTo(9),
      );
      for (var i = 1; i < relatedTop.length; i++) {
        expect((relatedTop[i] - relatedTop[i - 1]).abs(), lessThan(30));
      }
    }
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
