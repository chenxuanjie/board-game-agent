part of '../mobile_home_test.dart';

void _registerMobileNationalDayTests() {
  Future<AppController> controller(
    WidgetTester tester, {
    PreferencesService? preferences,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final value = _controller(preferences: preferences);
    addTearDown(value.dispose);
    addTearDown(() {
      value.gameVotes.dispose();
      value.nationalDayList.dispose();
    });
    rootBundle.clear();
    await tester.runAsync(value.reloadGames);
    return value;
  }

  Future<void> mount(
    WidgetTester tester,
    AppController controller,
    Size size, {
    double textScale = 1,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.buildTheme(controller.palette),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale), size: size),
          child: child!,
        ),
        home: RepaintBoundary(
          key: const ValueKey('mobile-national-day-capture'),
          child: MobileNationalDayScreen(
            controller: controller,
            onOpenGame: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final size in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(430, 932),
    const Size(844, 390),
  ]) {
    testWidgets('mobile National Day layout fits $size and enlarged text', (
      tester,
    ) async {
      final value = await controller(tester);
      await mount(tester, value, size, textScale: size.width == 320 ? 1.25 : 1);
      expect(find.text('国庆想玩'), findsOneWidget);
      expect(find.text('本次想玩'), findsOneWidget);
      expect(find.byIcon(Icons.favorite_rounded), findsNothing);
      final first = value.nationalDayGames.first;
      final rect = tester.getRect(
        find.byKey(ValueKey('mobile-national-day-open-${first.slug}')),
      );
      expect(rect.width, greaterThan(90));
      expect(rect.height, lessThan(250));
      expect(rect.left, greaterThanOrEqualTo(16));
      expect(rect.right, lessThan(size.width));
      await tester.ensureVisible(
        find.byKey(const ValueKey('mobile-national-day-add')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'mobile seasonal voting and list changes are shared with desktop and survive restart',
    (tester) async {
      final value = await controller(tester);
      await mount(tester, value, const Size(390, 844));
      final first = value.nationalDayGames.first;
      final vote = find.byKey(
        ValueKey('mobile-national-day-vote-${first.slug}'),
      );
      final favorites = value.favoriteCount;
      await tester.tap(vote);
      await tester.pumpAndSettle();
      expect(value.gameVotes.hasVoted(first.slug), isTrue);
      expect(value.gameVotes.count(first.slug), 1);
      expect(value.favoriteCount, favorites);
      expect(
        await PreferencesService().loadGameVoteCache(),
        contains(first.slug),
      );
      await tester.tap(vote);
      await tester.pumpAndSettle();
      expect(value.gameVotes.count(first.slug), 0);
      await tester.tap(vote);
      await tester.pumpAndSettle();

      final extra = value.games.firstWhere(
        (game) => !value.nationalDayList.slugs.contains(game.slug),
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('mobile-national-day-add')),
      );
      await tester.tap(find.byKey(const ValueKey('mobile-national-day-add')));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(ValueKey('national-day-pick-${first.slug}')),
        findsNothing,
      );
      await tester.enterText(
        find.byKey(const ValueKey('national-day-picker-search')),
        extra.title,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('national-day-pick-${extra.slug}')));
      await tester.pumpAndSettle();
      expect(value.nationalDayList.slugs, contains(extra.slug));
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(ValueKey('mobile-national-day-remove-${first.slug}')),
      );
      await tester.tap(
        find.byKey(ValueKey('mobile-national-day-remove-${first.slug}')),
      );
      await tester.pumpAndSettle();
      expect(value.nationalDayList.slugs, isNot(contains(first.slug)));
      expect(value.gameVotes.hasVoted(first.slug), isTrue);

      await tester.binding.setSurfaceSize(const Size(1448, 1086));
      await tester.pumpWidget(
        MaterialApp(
          home: DesktopNationalDayPage(controller: value, onOpenGame: (_) {}),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('national-day-game-${extra.slug}')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('national-day-game-${first.slug}')),
        findsNothing,
      );
      final reopened = _controller();
      addTearDown(reopened.dispose);
      addTearDown(() {
        reopened.gameVotes.dispose();
        reopened.nationalDayList.dispose();
      });
      await tester.runAsync(reopened.reloadGames);
      await reopened.nationalDayList.load();
      await reopened.gameVotes.load();
      expect(reopened.nationalDayList.slugs, value.nationalDayList.slugs);
      expect(reopened.gameVotes.hasVoted(first.slug), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'mobile National Day handles failed reads, failed writes and an empty list',
    (tester) async {
      final preferences = _SeasonalPreferences()..failRead = true;
      final value = await controller(tester, preferences: preferences);
      await mount(tester, value, const Size(320, 640));
      expect(find.text('清单读取失败'), findsOneWidget);
      preferences.failRead = false;
      await tester.tap(find.text('重新加载'));
      await tester.pumpAndSettle();
      final first = value.nationalDayGames.first;
      preferences.failSave = true;
      await tester.ensureVisible(
        find.byKey(ValueKey('mobile-national-day-remove-${first.slug}')),
      );
      await tester.tap(
        find.byKey(ValueKey('mobile-national-day-remove-${first.slug}')),
      );
      await tester.pumpAndSettle();
      expect(value.nationalDayList.slugs, contains(first.slug));
      expect(find.text('清单保存失败，请重试'), findsOneWidget);
      preferences.failSave = false;
      for (final slug in List.of(value.nationalDayList.slugs)) {
        final remove = find.byKey(ValueKey('mobile-national-day-remove-$slug'));
        await tester.ensureVisible(remove);
        await tester.tap(remove);
        await tester.pumpAndSettle();
      }
      expect(value.nationalDayGames, isEmpty);
      expect(await preferences.loadNationalDayGameSlugs(), isEmpty);
      await tester.pumpWidget(const SizedBox());
      await mount(tester, value, const Size(320, 640));
      expect(find.text('添加一款桌游，邀请朋友一起投票'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'second mobile banner opens seasonal route, shares real data and returns from game detail',
    (tester) async {
      final value = await controller(tester);
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      String? sharedText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            sharedText = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.buildTheme(value.palette),
          home: HomeScreen(controller: value, onOpenAbout: () {}),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mobile-home-banner-dot-1')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('mobile-home-national-day-banner')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MobileNationalDayScreen), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mobile-national-day-share')));
      await tester.pumpAndSettle();
      expect(sharedText, value.nationalDayShareText);
      final first = value.nationalDayGames.first;
      await tester.tap(
        find.byKey(ValueKey('mobile-national-day-open-${first.slug}')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(GameDetailScreen), findsOneWidget);
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(find.byType(MobileNationalDayScreen), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mobile-national-day-back')));
      await tester.pumpAndSettle();
      expect(find.byType(MobileNationalDayScreen), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('mobile National Day renders actual fonts and background', (
    tester,
  ) async {
    final directory = Platform.environment['MOBILE_UI_CAPTURE_DIR'];
    if (directory == null || directory.isEmpty) return;
    final value = await controller(tester);
    await tester.runAsync(() async {
      for (final entry in {
        'Noto Sans SC': 'assets/fonts/NotoSansSC-Variable.ttf',
        'National Day Display': 'assets/fonts/NationalDayDisplay.ttf',
        'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
      }.entries) {
        final loader = FontLoader(entry.key)
          ..addFont(rootBundle.load(entry.value));
        await loader.load();
      }
    });
    await mount(tester, value, const Size(390, 844));
    final context = tester.element(find.byType(MobileNationalDayScreen));
    await tester.runAsync(
      () => Future.wait([
        precacheImage(
          const AssetImage('assets/mobile/national_day/background.png'),
          context,
        ),
        for (final game in value.nationalDayGames) ...[
          precacheImage(AssetImage(game.coverAssetPath), context),
          if (game.bannerAssetPath.isNotEmpty)
            precacheImage(AssetImage(game.bannerAssetPath), context),
        ],
      ]),
    );
    await tester.pumpAndSettle();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('mobile-national-day-capture')),
    );
    await tester.runAsync(() async {
      final rendered = await boundary.toImage(pixelRatio: 2);
      try {
        final bytes = await rendered.toByteData(format: ImageByteFormat.png);
        await Directory(directory).create(recursive: true);
        await File(
          '$directory/national-day-mobile.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
      } finally {
        rendered.dispose();
      }
    });
    expect(tester.takeException(), isNull);
  });
}

class _SeasonalPreferences extends PreferencesService {
  bool failRead = false;
  bool failSave = false;
  @override
  Future<List<String>?> loadNationalDayGameSlugs() {
    if (failRead) throw StateError('read failed');
    return super.loadNationalDayGameSlugs();
  }

  @override
  Future<void> saveNationalDayGameSlugs(Iterable<String> slugs) {
    if (failSave) throw StateError('write failed');
    return super.saveNationalDayGameSlugs(slugs);
  }
}
