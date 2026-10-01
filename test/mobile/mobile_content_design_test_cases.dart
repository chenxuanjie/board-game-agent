part of '../mobile_home_test.dart';

class _ContentDesignPreferences extends PreferencesService {
  @override
  Future<void> saveSelectedConversationId(String id) async {}
  @override
  Future<void> clearSelectedConversationId() async {}
  @override
  Future<void> saveRecentGames(Iterable<RecentGameRecord> records) async {}
  @override
  Future<void> saveFavoriteGames(Iterable<FavoriteGameRecord> records) async {}
}

class _ContentDesignController extends AppController {
  _ContentDesignController()
    : super(
        preferencesService: _ContentDesignPreferences(),
        aiService: _UnusedAiService(),
        gameManifestService: GameManifestService(),
        remoteAssetService: _NoNetworkAssetService(),
        speechService: SpeechService(),
        ttsService: _UnavailableTtsService(),
      );

  @override
  List<AiConversation> get conversations => [
    AiConversation(
      id: 'design-test',
      title: '如何安排这次桌游聚会？',
      scope: AiConversationScope.global,
      createdAt: DateTime(2026, 10, 1),
      updatedAt: DateTime.now(),
      messages: [
        ChatMessage(
          id: 'question',
          role: ChatRole.user,
          text: '四位朋友第一次玩桌游，有哪些适合一起玩的游戏？',
          timestamp: DateTime.now(),
        ),
      ],
    ),
  ];
}

void _registerContentDesignTests() {
  setUpAll(() async {
    final font = FontLoader('Noto Sans SC')
      ..addFont(rootBundle.load('assets/fonts/NotoSansSC-Variable.ttf'));
    await font.load();
  });
  testWidgets('unified content cards fit widths, themes and large text', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final controller = _ContentDesignController();
    addTearDown(controller.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    rootBundle.clear();
    await tester.runAsync(controller.reloadGames);
    await controller.recordRecentlyViewed(controller.games.first);
    await controller.recordRecentlyViewed(controller.games[1]);
    for (final width in [320.0, 390.0, 430.0, 720.0]) {
      await tester.binding.setSurfaceSize(Size(width, 1000));

      for (final palette in [
        PaletteRegistry.warmwoodStudy,
        PaletteRegistry.classic,
      ]) {
        for (final scale in [1.0, 1.25, 2.0]) {
          debugPrint(
            'Design verification: $width / $scale / ${palette.nameEn}',
          );
          await tester.pumpWidget(
            MaterialApp(
              key: UniqueKey(),
              theme: AppTheme.buildTheme(palette),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: HomeScreen(controller: controller, onOpenAbout: () {}),
            ),
          );
          await tester.pumpAndSettle();
          final ai = find.byKey(const ValueKey('mobile-recent-ai-design-test'));
          final homeScroll = find
              .descendant(
                of: find.byKey(const ValueKey('mobile-home-scroll')),
                matching: find.byType(Scrollable),
              )
              .first;
          await tester.scrollUntilVisible(ai, 200, scrollable: homeScroll);
          final aiSize = tester.getSize(ai);
          final recommendation = find.byKey(
            ValueKey(
              'mobile-recommendation-${controller.dailyRecommendedGames.first.id}',
            ),
          );
          await tester.scrollUntilVisible(
            recommendation,
            200,
            scrollable: homeScroll,
          );
          await tester.pumpAndSettle();
          final gameSize = tester.getSize(recommendation);
          expect(gameSize.width, inInclusiveRange(240, 280));
          expect(gameSize.height, greaterThanOrEqualTo(154));
          expect(aiSize.width, inInclusiveRange(240, 280));
          if (scale == 1) expect(gameSize.height, lessThanOrEqualTo(165));
          final cardSurface = tester.widget<Material>(
            find
                .descendant(of: recommendation, matching: find.byType(Material))
                .first,
          );
          expect(cardSurface.color, palette.surface);
          expect(
            tester
                .widget<MobileGameCover>(
                  find.descendant(
                    of: recommendation,
                    matching: find.byType(MobileGameCover),
                  ),
                )
                .fit,
            BoxFit.cover,
          );
          final cover = find.descendant(
            of: recommendation,
            matching: find.byType(MobileGameCover),
          );
          expect(tester.getRect(cover).top, tester.getRect(recommendation).top);
          expect(tester.getSize(cover).height, gameSize.height);
          expect(tester.takeException(), isNull);

          await tester.tap(find.byKey(const ValueKey('mobile-tab-mine')));
          await tester.pumpAndSettle();
          final recent = find.byKey(
            ValueKey(
              'mobile-mine-recent-${controller.recentlyViewedGames.first.id}',
            ),
          );
          await tester.scrollUntilVisible(
            recent,
            200,
            scrollable: find
                .descendant(
                  of: find.byKey(const ValueKey('mobile-mine-scroll')),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await tester.pumpAndSettle();
          final recentSize = tester.getSize(recent);
          expect(recentSize.width, inInclusiveRange(88, 112));
          expect(
            find.descendant(of: recent, matching: find.byType(ContentRating)),
            findsNothing,
          );
          final otherRecent = find.byKey(
            ValueKey(
              'mobile-mine-recent-${controller.recentlyViewedGames[1].id}',
            ),
          );
          expect(tester.getSize(otherRecent), recentSize);
          expect(tester.takeException(), isNull);
          await tester.tap(recent);
          await tester.pumpAndSettle();
          expect(find.byType(GameDetailScreen), findsOneWidget);
          expect(tester.takeException(), isNull);

          // Library keeps full covers and exposes favorite as a separate action.
          await tester.tap(find.byTooltip('返回'));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('mobile-tab-library')));
          await tester.pumpAndSettle();
          expect(find.byType(MobileLibraryContent), findsOneWidget);
          final tags = tester.widgetList<ContentAttributeTags>(
            find.byType(ContentAttributeTags),
          );
          expect(tags, isNotEmpty);
          expect(tags.every((item) => item.tags.length <= 2), isTrue);
          expect(tester.takeException(), isNull);
          final favorite = find.byKey(
            ValueKey('mobile-library-favorite-${controller.games.first.id}'),
          );
          final before = controller.isFavorite(controller.games.first);
          await tester.tap(favorite);
          await tester.pumpAndSettle();
          expect(controller.isFavorite(controller.games.first), !before);
          expect(tester.takeException(), isNull);
        }
      }
    }
  });
}
