part of '../desktop_workspace_test.dart';

Future<void> _mountSpatial(
  WidgetTester tester,
  AppController c,
  Size size, {
  double scale = 1,
  bool native = false,
}) async {
  await tester.binding.setSurfaceSize(size);
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('spatial-capture'),
      child: AnimatedBuilder(
        animation: c,
        builder: (_, _) => MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.buildTheme(c.palette),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(size: size, textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: native
              ? DesktopWindowFrame(
                  spatial: true,
                  child: SpatialWorkspace(controller: c, onOpenAbout: () {}),
                )
              : SpatialWorkspace(controller: c, onOpenAbout: () {}),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _registerSpatialTests(_DesktopWorkspaceTestContext context) {
  for (final size in [const Size(1440, 1000), const Size(390, 844)]) {
    testWidgets('Spatial sidebar removes only topic at $size', (tester) async {
      final c = context.controller;
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await c.setColorScheme(ColorSchemeOption.spatialCinema);
      await _mountSpatial(tester, c, size);
      if (size.width < 760) {
        await tester.tap(find.byKey(const ValueKey('spatial-open-navigation')));
        await tester.pumpAndSettle();
      }
      final sidebar = find.byKey(const ValueKey('spatial-sidebar'));
      final titles = <Key?, String>{};
      void collectButtons() {
        for (final button in tester.widgetList<SpatialSidebarButton>(
          find.descendant(
            of: sidebar,
            matching: find.byType(SpatialSidebarButton),
          ),
        )) {
          titles.putIfAbsent(button.key, () => button.title);
        }
      }

      collectButtons();
      expect(find.text('HOME'), findsOneWidget);
      expect(find.text('MY COLLECTION'), findsOneWidget);
      if (size.width < 760) {
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('spatial-menu-settings')),
          160,
          scrollable: find
              .descendant(of: sidebar, matching: find.byType(Scrollable))
              .first,
        );
        await tester.pumpAndSettle();
        collectButtons();
      }
      expect(titles.values.toList(), [
        '首页',
        '桌游库',
        '排行榜',
        '我的喜欢',
        'AI 助手',
        '最近浏览',
        '资料下载',
        '账户',
        '设置',
      ]);
      expect(find.byKey(const ValueKey('spatial-menu-topic')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  for (final size in [const Size(1440, 1000), const Size(390, 844)]) {
    testWidgets('Spatial account menu stays on home at $size', (tester) async {
      final c = context.controller;
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await c.setColorScheme(ColorSchemeOption.spatialCinema);
      await _mountSpatial(tester, c, size);
      expect(find.byKey(const ValueKey('account-menu-button')), findsOneWidget);
      expect(find.byIcon(Icons.notifications_none), findsNothing);
      await tester.tap(find.byKey(const ValueKey('account-menu-button')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('account-menu-notifications')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DesktopActivityPopup), findsOneWidget);
      expect(c.unreadActivityCount, 0);
      await tester.tap(find.byTooltip(c.copy.dialogClose));
      await tester.pumpAndSettle();
      if (size.width < 760) {
        await tester.tap(find.byKey(const ValueKey('spatial-open-navigation')));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const ValueKey('spatial-menu-games')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('account-menu-button')), findsNothing);
      expect(
        find.byKey(const ValueKey('mobile-library-profile')),
        findsNothing,
      );
      if (size.width < 760) {
        Navigator.of(tester.element(find.byType(MobileLibraryContent))).pop();
      } else {
        await tester.tap(find.byKey(const ValueKey('spatial-menu-home')));
      }
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('account-menu-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('account-menu-account')));
      await tester.pumpAndSettle();
      expect(find.byType(AccountScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  for (final size in [const Size(1440, 1000), const Size(900, 800)]) {
    testWidgets('Spatial wide business pages use desktop content at $size', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final c = context.controller;
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await c.setColorScheme(ColorSchemeOption.spatialCinema);
      await tester.runAsync(() async {
        await c.toggleFavorite(c.games.first);
        await c.recordRecentlyViewed(c.games.first);
      });
      await _mountSpatial(tester, c, size);
      for (final (page, type) in <(String, Type)>[
        ('games', DesktopGamesPane),
        ('favorites', DesktopGamesPane),
        ('recent', DesktopGamesPane),
        ('assistant', DesktopAssistantPane),
        ('downloads', DesktopLibraryPane),
        ('account', AccountScreen),
        ('settings', DesktopSettingsPane),
      ]) {
        final menu = find.byKey(ValueKey('spatial-menu-$page'));
        await tester.ensureVisible(menu);
        await tester.tap(menu);
        await tester.pumpAndSettle();
        expect(find.byType(type), findsOneWidget, reason: page);
        expect(find.byType(MobileLibraryContent), findsNothing);
        expect(find.byType(MobileSettingsScreen), findsNothing);
        expect(tester.takeException(), isNull, reason: page);
      }
    });
  }
  testWidgets(
    'Spatial library uses available width, desktop filters and restores query across layouts',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final c = context.controller;
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await c.setColorScheme(ColorSchemeOption.spatialCinema);
      await _mountSpatial(tester, c, const Size(1440, 1000));
      await tester.tap(find.byKey(const ValueKey('spatial-menu-games')));
      await tester.pumpAndSettle();
      final grid = find.byKey(const ValueKey('desktop-library-posters'));
      expect(tester.getSize(grid).width, greaterThan(850));
      expect(
        find.byKey(const ValueKey('desktop-library-sort-action')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('desktop-library-filter-action')),
        findsOneWidget,
      );
      final category = find.descendant(
        of: find.byKey(const ValueKey('desktop-library-category-1')),
        matching: find.byType(Text),
      );
      expect(tester.widget<Text>(category).style!.color, c.palette.textPrimary);
      expect(find.byKey(const ValueKey('mobile-library-search')), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('spatial-search')),
        '卡卡',
      );
      await tester.pumpAndSettle();
      expect(c.browseSession.library.query, '卡卡');
      await _mountSpatial(tester, c, const Size(390, 844));
      expect(find.byType(MobileLibraryContent), findsOneWidget);
      final search = find.byKey(const ValueKey('mobile-library-search'));
      expect(tester.widget<TextField>(search).controller!.text, '卡卡');
      await tester.enterText(search, '波多');
      await tester.pumpAndSettle();
      await _mountSpatial(tester, c, const Size(1440, 1000));
      expect(find.byType(DesktopGamesPane), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('spatial-search')))
            .controller!
            .text,
        '波多',
      );
      expect(c.browseSession.library.query, '波多');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Spatial native library adds complete columns on large windows', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final c = context.controller;
    addTearDown(() => tester.binding.setSurfaceSize(null));
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await c.setColorScheme(ColorSchemeOption.spatialCinema);
      await _mountSpatial(tester, c, const Size(1920, 1000));
      await tester.tap(find.byKey(const ValueKey('spatial-menu-games')));
      await tester.pumpAndSettle();
      final grid = tester.getRect(
        find.byKey(const ValueKey('desktop-library-posters')),
      );
      final cards = find.descendant(
        of: find.byType(DesktopGamesPane),
        matching: find.byType(SpatialGamePoster),
      );
      final rects = tester
          .widgetList(cards)
          .map((widget) => tester.getRect(find.byWidget(widget)))
          .toList();
      final firstRow = rects
          .where((r) => (r.top - rects.first.top).abs() < 1)
          .toList();
      expect(firstRow.length, greaterThanOrEqualTo(7));
      expect(firstRow.last.right, closeTo(grid.right, 1));
      expect(
        firstRow.every((r) => r.left >= grid.left && r.right <= grid.right + 1),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
  testWidgets('Spatial desktop sort and scroll survive detail roundtrip', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final c = context.controller;
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await c.setColorScheme(ColorSchemeOption.spatialCinema);
    await _mountSpatial(tester, c, const Size(1440, 1000));
    await tester.tap(find.byKey(const ValueKey('spatial-menu-games')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('desktop-library-sort-action')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('desktop-library-sort-option-score')),
    );
    await tester.pumpAndSettle();
    expect(c.browseSession.library.sort, 'score');
    final scroll = find.byKey(
      const PageStorageKey('spatial-desktop-scroll-games'),
    );
    await tester.drag(scroll, const Offset(0, -500));
    await tester.pumpAndSettle();
    final position = tester
        .widget<SingleChildScrollView>(scroll)
        .controller!
        .offset;
    expect(position, greaterThan(100));
    final viewport = tester.getRect(scroll);
    final posters = find.descendant(
      of: find.byType(DesktopGamesPane),
      matching: find.byType(SpatialGamePoster),
    );
    final visible = posters.evaluate().firstWhere(
      (element) =>
          viewport.contains(tester.getCenter(find.byWidget(element.widget))),
    );
    await tester.tap(find.byWidget(visible.widget));
    await tester.pumpAndSettle();
    expect(find.byType(DesktopGameDetailPane), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(c.browseSession.library.sort, 'score');
    expect(
      tester.widget<SingleChildScrollView>(scroll).controller!.offset,
      closeTo(position, 1),
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Spatial Windows fills the window with the solid panel and integrated controls',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final c = context.controller;
      const channel = MethodChannel('window_manager');
      final methods = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            methods.add(call.method);
            if (call.method == 'isMaximized') return false;
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      addTearDown(() => tester.binding.setSurfaceSize(null));
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        await c.setColorScheme(ColorSchemeOption.spatialCinema);
        await _mountSpatial(tester, c, const Size(1440, 1000), native: true);
        expect(find.byType(SpatialScene), findsNothing);
        expect(find.byType(SpatialCapsule), findsNothing);
        expect(find.byType(BackdropFilter), findsNothing);
        // Sample the actual rendered seam, including the sidebar: identical
        // gradient constants in two restarted surfaces would fail this check.
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('spatial-capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          try {
            final bytes = (await image.toByteData(
              format: ImageByteFormat.rawRgba,
            ))!;
            for (final x in [40, 400, 1100]) {
              for (var channel = 0; channel < 3; channel++) {
                final above = bytes.getUint8(
                  (47 * image.width + x) * 4 + channel,
                );
                final below = bytes.getUint8(
                  (48 * image.width + x) * 4 + channel,
                );
                expect((above - below).abs(), lessThanOrEqualTo(1));
              }
            }
          } finally {
            image.dispose();
          }
        });
        expect(
          tester
              .widget<Scaffold>(find.byKey(const ValueKey('spatial-workspace')))
              .backgroundColor,
          Colors.transparent,
        );
        expect(
          tester
              .widget<Container>(find.byKey(const ValueKey('spatial-sidebar')))
              .decoration,
          isA<BoxDecoration>().having(
            (d) => d.gradient,
            'native sidebar has no restarted tint',
            isNull,
          ),
        );
        final posterSize = tester.getSize(
          find.byKey(
            ValueKey('spatial-game-${c.personalizedRecommendedGames.first.id}'),
          ),
        );
        expect(posterSize.width / posterSize.height, closeTo(141 / 216, .001));
        expect(
          tester.getSize(find.byKey(const ValueKey('spatial-glass-window'))),
          const Size(1440, 952),
        );
        expect(
          find.byKey(const ValueKey('spatial-window-titlebar')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('desktop-window-titlebar')),
          findsNothing,
        );
        await tester.tap(find.byTooltip('最小化'));
        await tester.pump();
        await tester.tap(find.byTooltip('最大化'));
        await tester.pump();
        await tester.tap(find.byTooltip('关闭'));
        await tester.pump();
        expect(methods, containsAll(['minimize', 'maximize', 'close']));
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  for (final size in [
    const Size(1440, 1000),
    const Size(1280, 720),
    const Size(900, 800),
    const Size(390, 844),
  ]) {
    testWidgets('Spatial independent shell preserves navigation at $size', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final c = context.controller;
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await c.setColorScheme(ColorSchemeOption.spatialCinema);
      await _mountSpatial(tester, c, size);
      expect(find.byType(DesktopWorkspace), findsNothing);
      expect(find.byType(CinemaHomeContent), findsNothing);
      expect(find.byType(SpatialGlass), findsOneWidget);
      expect(find.byType(SpatialPoster), findsWidgets);
      if (size.width >= 1020) {
        expect(
          tester.getSize(find.byKey(const ValueKey('spatial-glass-window'))),
          Size(1160, size.height >= 774 ? 710 : size.height - 64),
        );
        expect(
          find.byKey(const ValueKey('spatial-movie-wednesday')),
          findsOneWidget,
        );
      }
      if (size.width < 760) {
        await tester.tap(find.byKey(const ValueKey('spatial-open-navigation')));
        await tester.pumpAndSettle();
      }
      if (size.width < 760) {
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('spatial-menu-settings')),
          200,
          scrollable: find
              .descendant(
                of: find.byKey(const ValueKey('spatial-sidebar')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
      }
      await tester.tap(find.byKey(const ValueKey('spatial-menu-settings')));
      await tester.pumpAndSettle();
      expect(
        find.byType(
          size.width >= 760 ? DesktopSettingsPane : MobileSettingsScreen,
        ),
        findsOneWidget,
      );
      expect(find.text('空间影院'), findsOneWidget);
      // Picking another page must not be erased by the removed route callback.
      if (size.width >= 760) {
        await tester.tap(find.byKey(const ValueKey('spatial-menu-games')));
        await tester.pumpAndSettle();
        expect(find.byType(DesktopGamesPane), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('spatial-menu-home')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(
            ValueKey('spatial-game-${c.personalizedRecommendedGames.first.id}'),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byType(
            size.width >= 760 ? DesktopGameDetailPane : GameDetailScreen,
          ),
          findsOneWidget,
        );
        await tester.tap(find.byTooltip('返回'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('spatial-game-shelf')),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
    });
  }
  for (final size in [
    const Size(1440, 1000),
    const Size(900, 800),
    const Size(390, 844),
  ]) {
    testWidgets(
      'Spatial recommendation preview fits whole cards and arrow opens ten games at $size',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final c = context.controller;
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await c.setColorScheme(ColorSchemeOption.spatialCinema);
        await _mountSpatial(tester, c, size);
        final shelf = find.byKey(const ValueKey('spatial-game-shelf'));
        expect(
          find.descendant(of: shelf, matching: find.byType(Scrollable)),
          findsNothing,
        );
        final posters = find.descendant(
          of: shelf,
          matching: find.byType(SpatialGamePoster),
        );
        expect(
          posters,
          findsNWidgets(
            size.width >= 1020
                ? 6
                : size.width >= 760
                ? 4
                : 2,
          ),
        );
        final shelfRect = tester.getRect(shelf);
        for (final element in posters.evaluate()) {
          final rect = tester.getRect(find.byWidget(element.widget));
          expect(rect.left, greaterThanOrEqualTo(shelfRect.left - .01));
          expect(rect.right, lessThanOrEqualTo(shelfRect.right + .01));
        }
        await tester.tap(
          find.byKey(const ValueKey('spatial-more-recommendations')),
        );
        await tester.pumpAndSettle();
        expect(find.byType(SpatialRecommendationsPage), findsOneWidget);
        expect(find.byType(MobileLibraryContent), findsNothing);
        final grid = tester.widget<SliverGrid>(find.byType(SliverGrid));
        expect(grid.delegate.estimatedChildCount, 10);
        final first = c.personalizedRecommendedGames.first;
        await tester.tap(find.byKey(ValueKey('spatial-game-${first.id}')));
        await tester.pumpAndSettle();
        expect(
          find.byType(
            size.width >= 760 ? DesktopGameDetailPane : GameDetailScreen,
          ),
          findsOneWidget,
        );
        await tester.tap(find.byTooltip('返回'));
        await tester.pumpAndSettle();
        expect(find.byType(SpatialRecommendationsPage), findsOneWidget);
        await tester.tap(find.byTooltip('返回'));
        await tester.pumpAndSettle();
        expect(shelf, findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  test(
    'Spatial slate reacts to favorites and preserves its cache across unrelated reads',
    () async {
      SharedPreferences.setMockInitialValues({});
      final c = context.controller;
      final slate = c.personalizedRecommendedGames;
      expect(identical(c.personalizedRecommendedGames, slate), isTrue);
      final liked = slate.first;
      expect(await c.toggleFavorite(liked), isTrue);
      final personalized = c.personalizedRecommendedGames;
      expect(personalized, hasLength(10));
      expect(personalized.any((g) => g.slug == liked.slug), isFalse);
      expect(identical(personalized, slate), isFalse);
    },
  );
  testWidgets(
    'Spatial source material and searchable real catalog are independent of Cinema',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final c = context.controller;
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await c.setColorScheme(ColorSchemeOption.spatialCinema);
      await _mountSpatial(tester, c, const Size(1440, 1000));
      final glass = find.byType(SpatialGlass);
      final clip = tester.widget<ClipRRect>(
        find.descendant(of: glass, matching: find.byType(ClipRRect)).first,
      );
      expect(clip.borderRadius, BorderRadius.circular(32));
      await tester.enterText(
        find.byKey(const ValueKey('spatial-search')),
        '卡卡颂',
      );
      await tester.pumpAndSettle();
      final carca = c.games.firstWhere((game) => game.title.contains('卡卡颂'));
      expect(find.byKey(ValueKey('spatial-game-${carca.id}')), findsOneWidget);
      expect(find.textContaining('卡卡颂'), findsWidgets);
      expect(
        find.byKey(const ValueKey('spatial-game-puerto-rico')),
        findsNothing,
      );
      expect(find.text('NIGHT AGENT'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Spatial layout remains usable at 200 percent text', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final c = context.controller;
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await c.setColorScheme(ColorSchemeOption.spatialCinema);
    await _mountSpatial(tester, c, const Size(1280, 800), scale: 2);
    await tester.tap(find.byKey(const ValueKey('spatial-menu-settings')));
    await tester.pumpAndSettle();
    expect(find.text('空间影院'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  if (const bool.fromEnvironment('RENDER_SPATIAL')) {
    testWidgets(
      'Spatial screenshot uses source geometry and real bundled artwork',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final c = await tester.runAsync(
          () => _createController(
            ttsService: _UnavailableTtsService(),
            remoteAssetService: _LocalCinemaAssets(),
          ),
        );
        addTearDown(c!.dispose);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await c.setColorScheme(ColorSchemeOption.spatialCinema);
        final cache = PaintingBinding.instance.imageCache.maximumSizeBytes;
        PaintingBinding.instance.imageCache.maximumSizeBytes =
            512 * 1024 * 1024;
        addTearDown(
          () => PaintingBinding.instance.imageCache.maximumSizeBytes = cache,
        );
        await _warmCinemaPictures(tester, c);
        await _mountSpatial(tester, c, const Size(1440, 1000));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)),
        );
        await tester.pumpAndSettle();
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('spatial-capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          try {
            final bytes = await image.toByteData(format: ImageByteFormat.png);
            await File(
              'tmp/spatial-home.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
        for (final page in ['games', 'settings']) {
          await tester.ensureVisible(
            find.byKey(ValueKey('spatial-menu-$page')),
          );
          await tester.tap(find.byKey(ValueKey('spatial-menu-$page')));
          await tester.pumpAndSettle();
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1);
            try {
              final bytes = await image.toByteData(format: ImageByteFormat.png);
              await File(
                'build/diagnostics/spatial-wide-$page.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
            } finally {
              image.dispose();
            }
          });
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
