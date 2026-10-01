part of '../desktop_workspace_test.dart';

void _registerDesktopHomeTests(_DesktopWorkspaceTestContext context) {
  testWidgets('quick entries have centered icon and title without subtitles', (
    tester,
  ) async {
    await _mount(tester, context.controller, const Size(1280, 800));
    for (final entry in <(String, String, IconData)>[
      ('home-quick-entry-rules', '规则查询', Icons.menu_book_rounded),
      ('home-quick-entry-ai', 'AI助手', Icons.lightbulb_rounded),
    ]) {
      final card = find.byKey(ValueKey<String>(entry.$1));
      final title = find.descendant(of: card, matching: find.text(entry.$2));
      final icon = find.descendant(of: card, matching: find.byIcon(entry.$3));
      expect(title, findsOneWidget);
      expect(icon, findsOneWidget);
      expect(tester.widget<Text>(title).style?.fontSize, 14);
      final groupCenter =
          (tester.getRect(icon).left + tester.getRect(title).right) / 2;
      expect(groupCenter, closeTo(tester.getRect(card).center.dx, 2));
    }
    expect(find.text('快速查规则'), findsNothing);
    expect(find.text('桌游问题随时问'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home rules query shortcut navigates to the shared library', (
    tester,
  ) async {
    await _mount(tester, context.controller, const Size(1280, 800));
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
    await _mount(tester, context.controller, const Size(1280, 800));
    await tester.tap(
      find.byKey(const ValueKey<String>('home-quick-entry-rules')),
    );
    await tester.pumpAndSettle();

    final allButton = find.widgetWithText(
      TextButton,
      context.controller.copy.desktopAll,
    );
    final faqButton = find.widgetWithText(
      TextButton,
      context.controller.copy.desktopFaq,
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

  testWidgets(
    'desktop library actions match category pills and animate menus',
    (tester) async {
      await _mount(tester, context.controller, const Size(1280, 800));
      await _navigate(tester, '游戏库');

      final category = find.byKey(
        const ValueKey<String>('desktop-library-category-0'),
      );
      final inactiveCategory = find.byKey(
        const ValueKey<String>('desktop-library-category-1'),
      );
      final sort = find.byKey(
        const ValueKey<String>('desktop-library-sort-action'),
      );
      final filter = find.byKey(
        const ValueKey<String>('desktop-library-filter-action'),
      );
      expect(tester.getSize(category).height, 38);
      expect(tester.getSize(sort).height, 38);
      expect(tester.getSize(filter).height, 38);
      expect(
        tester.getTopLeft(sort).dy,
        closeTo(tester.getTopLeft(category).dy, 0.1),
      );
      expect(
        tester.getTopLeft(filter).dy,
        closeTo(tester.getTopLeft(category).dy, 0.1),
      );

      TextStyle toolbarTextStyle(Finder control) => tester
          .widget<Text>(
            find.descendant(of: control, matching: find.byType(Text)),
          )
          .style!;

      final selectedCategoryStyle = toolbarTextStyle(category);
      final inactiveCategoryStyle = toolbarTextStyle(inactiveCategory);
      final sortStyle = toolbarTextStyle(sort);
      final filterStyle = toolbarTextStyle(filter);
      expect(selectedCategoryStyle.fontSize, 13);
      expect(selectedCategoryStyle.height, 1);
      expect(selectedCategoryStyle.fontWeight, FontWeight.w700);
      expect(inactiveCategoryStyle.fontWeight, FontWeight.w500);
      expect(sortStyle.fontSize, inactiveCategoryStyle.fontSize);
      expect(sortStyle.height, inactiveCategoryStyle.height);
      expect(sortStyle.fontWeight, inactiveCategoryStyle.fontWeight);
      expect(filterStyle.fontSize, inactiveCategoryStyle.fontSize);
      expect(filterStyle.height, inactiveCategoryStyle.height);
      expect(filterStyle.fontWeight, inactiveCategoryStyle.fontWeight);

      final sortSurface = tester.widget<AnimatedContainer>(
        find.descendant(of: sort, matching: find.byType(AnimatedContainer)),
      );
      final sortDecoration = sortSurface.decoration! as BoxDecoration;
      expect(sortDecoration.borderRadius, BorderRadius.circular(20));
      expect(sortSurface.duration, const Duration(milliseconds: 180));

      await tester.tap(sort);
      await tester.pump(const Duration(milliseconds: 90));
      expect(find.text('排序方式'), findsOneWidget);
      final activeSortSurface = tester.widget<AnimatedContainer>(
        find.descendant(of: sort, matching: find.byType(AnimatedContainer)),
      );
      expect(
        (activeSortSurface.decoration! as BoxDecoration).gradient,
        isNotNull,
      );
      expect(
        toolbarTextStyle(sort).fontWeight,
        selectedCategoryStyle.fontWeight,
      );
      final arrow = tester.widget<AnimatedRotation>(
        find.descendant(of: sort, matching: find.byType(AnimatedRotation)),
      );
      expect(arrow.turns, 0.5);

      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(
        find.byKey(
          const ValueKey<String>('desktop-library-sort-option-catalog'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('排序方式'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('home search filters catalog data and opens a real game', (
    tester,
  ) async {
    await _mount(tester, context.controller, const Size(1280, 800));
    final GameInfo game = context.controller.games.first;
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
    expect(context.controller.selectedGame.id, game.id);
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
    final GameInfo first = context.controller.games[0];
    final GameInfo second = context.controller.games[1];

    unawaited(context.controller.recordRecentlyViewed(first));
    unawaited(context.controller.recordRecentlyViewed(second));
    unawaited(context.controller.recordRecentlyViewed(first));
    await _mount(
      tester,
      context.controller,
      const Size(1280, 800),
      settle: false,
    );
    await tester.pump();

    expect(
      context.controller.recentlyViewedGames.map((game) => game.slug),
      <String>[first.slug, second.slug],
    );
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
    expect(tester.getSize(firstTile).width, greaterThan(110));
    expect(tester.getSize(firstTile).width, lessThanOrEqualTo(150.1));
    expect(
      tester.getSize(firstThumbnail).width /
          tester.getSize(firstThumbnail).height,
      closeTo(1.46, 0.01),
    );
    final recentTitle = find.descendant(
      of: firstTile,
      matching: find.text(first.title),
    );
    expect(tester.widget<Text>(recentTitle).style?.fontSize, closeTo(13, 0.01));
    expect(tester.widget<Text>(recentTitle).style?.fontWeight, FontWeight.w700);
    final recentTime = find.descendant(
      of: firstTile,
      matching: find.textContaining('上次浏览：'),
    );
    expect(
      tester.widget<Text>(recentTime).style?.fontSize,
      closeTo(10.5, 0.01),
    );
    final recentHeader = find.byKey(
      const ValueKey<String>('desktop-home-recent-header'),
    );
    final recentHeaderTitle = find.descendant(
      of: recentHeader,
      matching: find.text('最近浏览'),
    );
    expect(
      tester.widget<Text>(recentHeaderTitle).style?.fontWeight,
      FontWeight.w700,
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
    expect(context.controller.recentlyViewedGames.first.slug, second.slug);
    expect(find.byTooltip('返回首页'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home recommendation header aligns more action and returns home', (
    tester,
  ) async {
    await _mount(tester, context.controller, const Size(1280, 800));
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

    final recommendationRects = [
      for (final game in context.controller.dailyRecommendedGames.take(5))
        tester.getRect(
          find.byKey(
            ValueKey<String>('desktop-home-recommendation-card-${game.id}'),
          ),
        ),
    ];
    expect(recommendationRects, hasLength(5));
    expect(recommendationRects.map((rect) => rect.top).toSet(), hasLength(1));
    expect(recommendationRects.first.width, closeTo(210, 0.1));
    expect(
      recommendationRects.map((rect) => rect.bottom).toSet(),
      hasLength(1),
    );

    final firstCard = find.byKey(
      ValueKey<String>(
        'desktop-home-recommendation-card-${context.controller.dailyRecommendedGames.first.id}',
      ),
    );
    final title = find.descendant(
      of: firstCard,
      matching: find.text(context.controller.dailyRecommendedGames.first.title),
    );
    final titleStyle = tester.widget<Text>(title).style!;
    expect(titleStyle.fontSize, 15);
    expect(titleStyle.fontWeight, FontWeight.w700);
    expect(titleStyle.height, 1.2);
    final categoryTags = context
        .controller
        .dailyRecommendedGames
        .first
        .categoryLine
        .split('/')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList();
    if (categoryTags.length >= 2) {
      expect(
        find.descendant(of: firstCard, matching: find.text(categoryTags.first)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: firstCard, matching: find.text(categoryTags[1])),
        findsOneWidget,
      );
    }
    final ratingIcon = find.descendant(
      of: firstCard,
      matching: find.byIcon(Icons.star_rounded),
    );
    expect(tester.widget<Icon>(ratingIcon).size, 16);

    final GameInfo game = context.controller.dailyRecommendedGames.first;
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
  });

  testWidgets(
    'home recommendation cards use compact natural height on wide windows',
    (tester) async {
      await _mount(tester, context.controller, const Size(1920, 1080));

      final card = find.byKey(
        ValueKey<String>(
          'desktop-home-recommendation-card-${context.controller.dailyRecommendedGames.first.id}',
        ),
      );
      final rect = tester.getRect(card);
      expect(rect.height, lessThan(rect.width * 280 / 175));
      final tagRow = find.descendant(of: card, matching: find.byType(Wrap));
      final footerText = find.descendant(
        of: card,
        matching: find.text(
          GameMetadataText.playTime(
            context.controller.dailyRecommendedGames.first.playTime,
          ),
        ),
      );
      expect(
        tester.getRect(footerText).top - tester.getRect(tagRow).bottom,
        inInclusiveRange(14, 60),
      );

      final title = find.descendant(
        of: card,
        matching: find.text(
          context.controller.dailyRecommendedGames.first.title,
        ),
      );
      expect(tester.widget<Text>(title).style!.fontSize, closeTo(16.2, 0.01));
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in <Size>[
    const Size(720, 700),
    const Size(1280, 800),
    const Size(1920, 1080),
  ]) {
    testWidgets('recommendation facts share one line at $size', (tester) async {
      await _mount(tester, context.controller, size);
      final game = context.controller.dailyRecommendedGames.first;
      final card = find.byKey(
        ValueKey<String>('desktop-home-recommendation-card-${game.id}'),
      );
      final cardWidth = tester.getRect(card).width;
      final metrics = DesktopMetricsScope.of(tester.element(card));
      final players = find.descendant(
        of: card,
        matching: find.text(
          cardWidth - metrics.px(20) >= metrics.px(230)
              ? GameMetadataText.players(game.playerCount)
              : GameMetadataText.cardPlayers(game.playerCount),
        ),
      );
      final duration = find.descendant(
        of: card,
        matching: find.text(GameMetadataText.playTime(game.playTime)),
      );
      expect(players, findsOneWidget);
      expect(duration, findsOneWidget);
      expect(
        tester.getRect(duration).center.dy,
        closeTo(tester.getRect(players).center.dy, 1),
      );
      expect(
        tester.getRect(duration).left,
        greaterThan(tester.getRect(players).right),
      );
      expect(
        tester.getRect(duration).right,
        lessThanOrEqualTo(tester.getRect(card).right),
      );
      expect(
        tester.widget<Text>(duration).overflow,
        isNot(TextOverflow.ellipsis),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('English recommendation cards keep full facts', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.runAsync(() => context.controller.setLanguage(AppLanguage.en));
    await _mount(tester, context.controller, const Size(1280, 800));
    final game = context.controller.dailyRecommendedGames.first;
    final card = find.byKey(
      ValueKey<String>('desktop-home-recommendation-card-${game.id}'),
    );
    expect(
      find.descendant(
        of: card,
        matching: find.text(GameMetadataText.playTime(game.playTime)),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('home search handles empty results without inline clear action', (
    tester,
  ) async {
    await _mount(tester, context.controller, const Size(1280, 800));
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
    await _mount(tester, context.controller, const Size(1280, 800));
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
      await _mount(tester, context.controller, size);
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
      await context.controller.refreshLibraryResources();
      expect(context.controller.libraryLoadError, isNotNull);
      expect(
        context.controller.activities.any(
          (activity) => activity.kind == AppActivityKind.libraryLoadFailed,
        ),
        isTrue,
      );

      await _mount(tester, context.controller, const Size(1995, 1248));
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
    await _mount(tester, context.controller, const Size(1280, 800));
    await _navigate(tester, '游戏库');
    expect(
      context.controller.games.where(
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
    await tester.tap(find.text('5+'));
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();

    expect(find.text('暂无符合条件的游戏'), findsNothing);
    expect(find.text('请选择游戏'), findsNothing);
    expect(find.text('暂无游戏，请在资料库检查资源。'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home hero hover arrows fade, wrap and pause automatic rotation', (
    tester,
  ) async {
    await _mount(tester, context.controller, const Size(1280, 800));
    final frame = find.byKey(const ValueKey('home-hero-frame'));
    final previous = find.byKey(const ValueKey('home-hero-previous'));
    final next = find.byKey(const ValueKey('home-hero-next'));
    final visibility = find.byKey(const ValueKey('home-hero-next-visibility'));
    final carousel = tester.widget<PageView>(
      find.byKey(const ValueKey('home-hero-carousel')),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1279, 799));
    addTearDown(mouse.removePointer);
    expect(tester.widget<AnimatedOpacity>(visibility).opacity, 0);
    await mouse.moveTo(tester.getCenter(frame));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    final fade = find.descendant(
      of: visibility,
      matching: find.byType(FadeTransition),
    );
    expect(tester.widget<FadeTransition>(fade).opacity.value, greaterThan(0));
    expect(tester.widget<FadeTransition>(fade).opacity.value, lessThan(1));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(previous).left,
      closeTo(tester.getRect(frame).left, .1),
    );
    expect(
      tester.getRect(next).right,
      closeTo(tester.getRect(frame).right, .1),
    );
    expect(tester.getSize(next), const Size(38, 72));
    if (Platform.environment['DESKTOP_UI_CAPTURE_DIR'] != null) {
      final bannerContext = tester.element(frame);
      await tester.runAsync(
        () => precacheImage(
          const AssetImage('assets/desktop/home/banner_tonight.png'),
          bannerContext,
        ),
      );
      await tester.pumpAndSettle();
      await _captureDesktopTypography(tester, 'banner-arrows');
    }
    await tester.tap(previous);
    await tester.pumpAndSettle();
    expect(carousel.controller!.page, 2);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(carousel.controller!.page, 0);
    // Repeated clicks should advance from the requested slide, not stale state.
    await tester.tap(next);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(carousel.controller!.page, 2);
    await tester.pump(const Duration(seconds: 6));
    expect(carousel.controller!.page, 2);
    await mouse.moveTo(const Offset(1279, 799));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 75));
    expect(tester.widget<FadeTransition>(fade).opacity.value, greaterThan(0));
    expect(tester.widget<FadeTransition>(fade).opacity.value, lessThan(1));
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedOpacity>(visibility).opacity, 0);
    await tester.pump(const Duration(seconds: 4));
    expect(carousel.controller!.page, 2);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(carousel.controller!.page, 0);
    expect(find.byType(DesktopHomePane), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home hero keyboard arrows reveal controls and preserve focus', (
    tester,
  ) async {
    await _mount(tester, context.controller, const Size(1280, 800));
    final next = find.byKey(const ValueKey('home-hero-next'));
    final icon = find.descendant(of: next, matching: find.byType(Icon));
    Focus.of(tester.element(icon)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    final carousel = tester.widget<PageView>(
      find.byKey(const ValueKey('home-hero-carousel')),
    );
    expect(carousel.controller!.page, 1);
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(const ValueKey('home-hero-next-visibility')),
          )
          .opacity,
      1,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(carousel.controller!.page, 0);
    await tester.pump(const Duration(seconds: 6));
    expect(carousel.controller!.page, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home hero respects reduced motion for controls and navigation', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _mount(tester, context.controller, const Size(1280, 800));
    final frame = find.byKey(const ValueKey('home-hero-frame'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1279, 799));
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(frame));
    await tester.pump();
    final visible = tester.widget<AnimatedOpacity>(
      find.byKey(const ValueKey('home-hero-next-visibility')),
    );
    expect(visible.duration, Duration.zero);
    expect(visible.opacity, 1);
    await tester.tap(find.byKey(const ValueKey('home-hero-next')));
    await tester.pump();
    final carousel = tester.widget<PageView>(
      find.byKey(const ValueKey('home-hero-carousel')),
    );
    expect(carousel.controller!.page, 1);
    await tester.tap(find.byKey(const ValueKey('home-hero-next')));
    await tester.pump();
    expect(carousel.controller!.page, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home hero exposes three available carousel pages', (
    tester,
  ) async {
    await _mount(tester, context.controller, const Size(1280, 800));
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
    expect(
      tester
          .widget<Image>(
            find.byWidgetPredicate(
              (widget) => widget is Image && widget.semanticLabel == '国庆桌游聚会清单',
            ),
          )
          .image,
      const AssetImage('assets/desktop/home/banner_gathering.png'),
    );
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
    expect(sidebarArt.fit, BoxFit.fitWidth);
    expect(sidebarArt.alignment, Alignment.bottomCenter);
    final sidebarRect = tester.getRect(
      find.byKey(const ValueKey<String>('desktop-sidebar-full')),
    );
    final sidebarArtRect = tester.getRect(
      find.byKey(const ValueKey<String>('desktop-sidebar-art')),
    );
    final settingsItemRect = tester.getRect(
      find.byKey(
        const ValueKey<String>('desktop-sidebar-item-sidebar_settings.png'),
      ),
    );
    expect(sidebarArtRect.left, closeTo(sidebarRect.left, 0.1));
    expect(sidebarArtRect.right, closeTo(sidebarRect.right - 1, 0.1));
    expect(sidebarArtRect.bottom, closeTo(sidebarRect.bottom, 0.1));
    expect(settingsItemRect.bottom, lessThanOrEqualTo(sidebarArtRect.top));
    expect(
      sidebarArtRect.width / sidebarArtRect.height,
      closeTo(971 / 1619, 0.005),
    );
    for (final asset in [
      'sidebar_home.png',
      'sidebar_library.png',
      'sidebar_ai.png',
      'sidebar_likes.png',
      'sidebar_settings.png',
    ]) {
      final icon = find.byKey(ValueKey<String>('desktop-sidebar-icon-$asset'));
      expect(icon, findsOneWidget);
      expect(tester.getSize(icon), const Size(28, 28));
    }
    await tester.tap(find.byKey(const ValueKey<String>('home-hero-dot-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('home-hero-page-1')));
    await tester.pumpAndSettle();
    expect(find.byType(DesktopNationalDayPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in const [
    Size(1280, 800),
    Size(1100, 700),
    Size(720, 700),
    Size(600, 700),
  ]) {
    testWidgets('V5 game detail opens with real data at $size', (tester) async {
      await _mount(tester, context.controller, size);
      await _navigate(tester, '游戏库');
      final game = context.controller.games.first;
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
        find.byKey(const ValueKey<String>('detail-tab-1')),
      );
      await tester.tap(find.byKey(const ValueKey<String>('detail-tab-1')));
      await tester.pumpAndSettle();
      expect(find.text('规则摘要'), findsWidgets);
      expect(find.byKey(const ValueKey<String>('detail-tab-2')), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.byTooltip('返回游戏库'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('返回游戏库'));
      await tester.pumpAndSettle();
      expect(find.byType(DesktopGamesPane), findsOneWidget);
      expect(find.byType(DesktopGameDetailPane), findsNothing);
    });
  }
}
