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
          find.byKey(ValueKey('spatial-game-${c.games.first.id}')),
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
      expect(find.byType(MobileSettingsScreen), findsOneWidget);
      expect(find.text('空间影院'), findsOneWidget);
      // Picking another page must not be erased by the removed route callback.
      if (size.width >= 760) {
        await tester.tap(find.byKey(const ValueKey('spatial-menu-games')));
        await tester.pumpAndSettle();
        expect(find.byType(MobileLibraryContent), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('spatial-menu-home')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(ValueKey('spatial-game-${c.games.first.id}')),
        );
        await tester.pumpAndSettle();
        expect(find.byType(GameDetailScreen), findsOneWidget);
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
        expect(tester.takeException(), isNull);
      },
    );
  }
}
