part of '../desktop_workspace_test.dart';

void _registerDesktopNationalDayTests(_DesktopWorkspaceTestContext context) {
  Future<void> open(
    WidgetTester tester,
    Size size, {
    TextScaler textScaler = TextScaler.noScaling,
  }) async {
    await _mount(tester, context.controller, size, textScaler: textScaler);
    await tester.tap(find.byKey(const ValueKey('home-hero-dot-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-hero-page-1')));
    await tester.pumpAndSettle();
  }

  for (final size in [
    const Size(1448, 1086),
    const Size(1280, 800),
    const Size(1995, 1248),
  ]) {
    testWidgets('National Day composition fits $size without top favorite', (
      tester,
    ) async {
      await open(tester, size);
      expect(find.byType(DesktopNationalDayPage), findsOneWidget);
      expect(find.text('国庆聚会'), findsOneWidget);
      expect(find.text('桌游清单'), findsOneWidget);
      expect(find.text('收藏'), findsNothing);
      expect(find.byKey(const ValueKey('national-day-add')), findsOneWidget);
      final pageContext = tester.element(find.byType(DesktopNationalDayPage));
      await tester.runAsync(
        () => Future.wait([
          precacheImage(
            const AssetImage('assets/desktop/national_day/background.png'),
            pageContext,
          ),
          for (final game in context.controller.defaultNationalDayGames)
            precacheImage(AssetImage(game.coverAssetPath), pageContext),
        ]),
      );
      await tester.pumpAndSettle();
      for (final game in context.controller.defaultNationalDayGames) {
        final rect = tester.getRect(
          find.byKey(ValueKey('national-day-game-${game.slug}')),
        );
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(size.width));
        expect(rect.bottom, lessThanOrEqualTo(size.height));
      }
      if (size.width == 1448) {
        await _captureDesktopTypography(tester, 'national-day');
      }
      await tester.tap(find.byKey(const ValueKey('national-day-back')));
      await tester.pumpAndSettle();
      expect(find.byType(DesktopNationalDayPage), findsNothing);
      expect(find.byType(DesktopHomePane), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('National Day supports enlarged text', (tester) async {
    await open(
      tester,
      const Size(1280, 800),
      textScaler: const TextScaler.linear(1.25),
    );
    expect(find.byType(DesktopNationalDayPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('National Day list saves additions, removals and an empty list', (
    tester,
  ) async {
    await open(tester, const Size(1448, 1086));
    final game = context.controller.defaultNationalDayGames.first;
    final key = ValueKey('national-day-remove-${game.slug}');
    context.preferences.failNationalDaySave = true;
    await tester.tap(find.byKey(key));
    await tester.pumpAndSettle();
    expect(find.byKey(key), findsOneWidget);
    expect(find.text('清单保存失败，请重试'), findsOneWidget);
    context.preferences.failNationalDaySave = false;
    await tester.tap(find.byKey(key));
    await tester.pumpAndSettle();
    expect(
      context.preferences.nationalDayGameSlugs,
      isNot(contains(game.slug)),
    );

    await tester.tap(find.byKey(const ValueKey('national-day-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('national-day-picker-search')),
      game.title,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('national-day-pick-${game.slug}')));
    await tester.pumpAndSettle();
    expect(context.preferences.nationalDayGameSlugs, contains(game.slug));

    await tester.tap(find.byKey(const ValueKey('national-day-back')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-hero-dot-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-hero-page-1')));
    await tester.pumpAndSettle();
    for (final slug in List<String>.of(
      context.preferences.nationalDayGameSlugs!,
    )) {
      await tester.tap(find.byKey(ValueKey('national-day-remove-$slug')));
      await tester.pumpAndSettle();
    }
    expect(context.preferences.nationalDayGameSlugs, isEmpty);
    await tester.tap(find.byKey(const ValueKey('national-day-back')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-hero-dot-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-hero-page-1')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey('national-day-game-${game.slug}')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('national-day-add')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'National Day share copies the real list and cards open game details',
    (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
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
      await open(tester, const Size(1448, 1086));
      final game = context.controller.defaultNationalDayGames.first;
      await tester.tap(find.byKey(const ValueKey('national-day-share')));
      await tester.pumpAndSettle();
      expect(copied, contains(game.title));
      expect(copied, contains(game.playerCount));
      final likedBefore = context.controller.isFavorite(game);
      await tester.tap(find.byKey(ValueKey('national-day-vote-${game.slug}')));
      // The controller's serialized queue was created in the real setUp zone.
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(context.controller.isFavorite(game), likedBefore);
      expect(context.controller.gameVotes.hasVoted(game.slug), isTrue);
      expect(context.controller.gameVotes.count(game.slug), 1);
      await tester.tap(find.byKey(ValueKey('national-day-vote-${game.slug}')));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(context.controller.gameVotes.count(game.slug), 0);
      final card = tester.getRect(
        find.byKey(ValueKey('national-day-game-${game.slug}')),
      );
      await tester.tapAt(Offset(card.center.dx, card.top + 80));
      await tester.pumpAndSettle();
      expect(find.byType(DesktopNationalDayPage), findsNothing);
      expect(find.byType(DesktopGameDetailPane), findsOneWidget);
      expect(context.controller.selectedGame.slug, game.slug);
      expect(tester.takeException(), isNull);
    },
  );
}
