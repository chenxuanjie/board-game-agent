part of '../desktop_workspace_test.dart';

Future<void> _mountCinema(
  WidgetTester tester,
  AppController controller,
  Size size, {
  double scale = 1,
}) async {
  await tester.binding.setSurfaceSize(size);
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('cinema-capture'),
      child: AnimatedBuilder(
        animation: controller,
        builder: (_, _) => MaterialApp(
          theme: buildDesktopTheme(
            activePalette: controller.palette,
            cinemaGlassEnabled: controller.cinemaGlassEnabled,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(size: size, textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: DesktopWorkspace(controller: controller, onOpenAbout: () {}),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _registerCinemaTests(_DesktopWorkspaceTestContext context) {
  if (const bool.fromEnvironment('RENDER_CINEMA')) {
    testWidgets('Cinema renders real bundled game pictures', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final c = await tester.runAsync(
        () => _createController(
          ttsService: _UnavailableTtsService(),
          remoteAssetService: _LocalCinemaAssets(),
        ),
      );
      addTearDown(c!.dispose);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await c.setColorScheme(ColorSchemeOption.cinema);
      final cacheBytes = PaintingBinding.instance.imageCache.maximumSizeBytes;
      PaintingBinding.instance.imageCache.maximumSizeBytes = 512 * 1024 * 1024;
      addTearDown(
        () => PaintingBinding.instance.imageCache.maximumSizeBytes = cacheBytes,
      );
      await _warmCinemaPictures(tester, c);
      await _mountCinema(tester, c, const Size(1280, 800));
      await _captureCinema(tester, 'home');
      await _navigate(tester, '游戏库');
      await _captureCinema(tester, 'library');
      await _navigate(tester, '设置');
      await _captureCinema(tester, 'settings');
      c.browseSession.destination = 'home';
      const size = Size(390, 844);
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('cinema-capture'),
          child: MaterialApp(
            theme: AppTheme.buildTheme(c.palette),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(size: size),
              child: child!,
            ),
            home: HomeScreen(controller: c, onOpenAbout: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _captureCinema(tester, 'mobile');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'Cinema settings replaces the third theme and updates existing surfaces',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final c = context.controller;
      await c.setCinemaGlassEnabled(true);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _mountCinema(tester, c, const Size(1280, 800));
      await _navigate(tester, '设置');
      expect(find.text('晚霞海岸'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('desktop-settings-theme-cinema')),
      );
      await tester.pumpAndSettle();
      expect(c.colorScheme, ColorSchemeOption.cinema);
      final settingsContext = tester.element(find.byType(DesktopSettingsPane));
      expect(isCinema(settingsContext), isTrue);
      expect(
        AppPalette.of(settingsContext).pageBackground,
        PaletteRegistry.cinema.pageBackground,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('cinema-glass-setting')),
      );
      await tester.tap(find.byKey(const ValueKey('cinema-glass-setting')));
      await tester.pumpAndSettle();
      expect(c.cinemaGlassEnabled, isFalse);
      expect(
        Theme.of(
          settingsContext,
        ).extension<CinemaMaterialTheme>()!.glassEnabled,
        isFalse,
      );
      await _navigate(tester, '首页');
      expect(find.byType(CinemaHomeContent), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('cinema-hero-details')),
      );
      expect(find.byKey(const ValueKey('desktop-sidebar-art')), findsNothing);
      expect(find.byType(BackdropFilter), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [
    const Size(1100, 800),
    const Size(1280, 720),
    const Size(1920, 1080),
  ]) {
    testWidgets('Cinema home, grid, details and settings work at $size', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final c = context.controller;
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await c.setColorScheme(ColorSchemeOption.cinema);
      await _mountCinema(tester, c, size);
      expect(find.byType(CinemaHomeContent), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('cinema-hero-details')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('desktop-game-detail')), findsOneWidget);
      await tester.tap(find.byTooltip('返回首页'));
      await tester.pumpAndSettle();
      await _navigate(tester, '游戏库');
      expect(
        find.byKey(const ValueKey('desktop-library-posters')),
        findsOneWidget,
      );
      await _navigate(tester, '设置');
      expect(find.text('影院'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'Cinema retains navigation and readable controls at 200 percent text',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final c = context.controller;
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await c.setColorScheme(ColorSchemeOption.cinema);
      await _mountCinema(tester, c, const Size(1280, 800), scale: 2);
      await tester.ensureVisible(
        find.byKey(const ValueKey('cinema-hero-details')),
      );
      await tester.tap(find.byKey(const ValueKey('cinema-hero-details')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('返回首页'));
      await tester.pumpAndSettle();
      await _navigate(tester, '设置');
      await tester.ensureVisible(
        find.byKey(const ValueKey('cinema-glass-setting')),
      );
      expect(tester.takeException(), isNull);
    },
  );
}

// Local file fixture exercises the production cache/image path without NAS access.
class _LocalCinemaAssets extends _NoNetworkAssetService {
  @override
  Future<CachedAsset?> ensureCached({
    required List<AssetSourceConfig> sources,
    required String remotePath,
    bool forceRefresh = false,
    bool allowCachedFallback = true,
  }) async {
    final file = File(remotePath);
    if (!file.existsSync()) return null;
    return CachedAsset(
      remotePath: remotePath,
      localPath: file.absolute.path,
      exists: true,
      fromRemote: false,
    );
  }
}

Future<void> _captureCinema(WidgetTester tester, String name) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 600)),
  );
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 600)),
  );
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('cinema-capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ImageByteFormat.png);
      if (bytes == null) throw StateError('Unable to capture cinema');
      await File(
        'tmp/v5-cinema-$name.png',
      ).writeAsBytes(bytes.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

Future<void> _warmCinemaPictures(WidgetTester tester, AppController c) async {
  await tester.runAsync(() async {
    final paths = c.games
        .expand((g) => [g.coverAssetPath, g.bannerAssetPath])
        .toSet();
    for (final path in paths) {
      final file = File(path);
      if (!file.existsSync()) continue;
      final stream = FileImage(file.absolute).resolve(ImageConfiguration.empty);
      final ready = Completer<void>();
      late ImageStreamListener listener;
      listener = ImageStreamListener(
        (info, _) {
          info.dispose();
          if (!ready.isCompleted) ready.complete();
        },
        onError: (Object error, StackTrace? stack) {
          if (!ready.isCompleted) ready.completeError(error, stack);
        },
      );
      stream.addListener(listener);
      try {
        await ready.future.timeout(const Duration(seconds: 8));
      } finally {
        stream.removeListener(listener);
      }
    }
  });
}
