part of '../desktop_workspace_test.dart';

void _registerDesktopShellTests(_DesktopWorkspaceTestContext context) {
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
    Size(1100, 800),
    Size(720, 700),
    Size(1440, 900),
    Size(1920, 1080),
  ]) {
    testWidgets('home, games and settings navigate without overflow at $size', (
      tester,
    ) async {
      await _mount(tester, context.controller, size);
      expect(find.byType(DesktopHomePane), findsOneWidget);
      final home = find.byType(DesktopHomePane);
      expect(context.controller.games, isNotEmpty);
      for (final game in context.controller.games.take(5)) {
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
      for (final game in context.controller.games) {
        expect(
          find.byKey(ValueKey('desktop-poster-${game.id}')),
          findsOneWidget,
        );
      }
      // These titles occur in the reference mock data, not the bundled manifest.
      for (final title in ['卡坦岛', '璀璨王国']) {
        expect(
          context.controller.games.where((game) => game.title == title),
          isEmpty,
        );
        expect(find.text(title), findsNothing);
      }
      expect(tester.takeException(), isNull);
      await _navigate(tester, '设置');
      expect(find.byType(DesktopSettingsPane), findsOneWidget);
      expect(find.text('通用'), findsOneWidget);
      expect(find.text('AI 服务'), findsOneWidget);
      expect(find.text('外观与主题'), findsOneWidget);
      expect(find.text('通知设置'), findsOneWidget);
      expect(find.text('同步与备份'), findsOneWidget);
      expect(find.text('关于与更新'), findsOneWidget);
      final Finder settingsPane = find.byType(DesktopSettingsPane);
      final int columns = DesktopResponsive.settingsColumnsFor(
        tester.getSize(settingsPane).width,
      );
      const List<String> cardTitles = <String>[
        '通用',
        'AI 服务',
        '外观与主题',
        '通知设置',
        '同步与备份',
        '关于与更新',
      ];
      for (int start = 0; start < cardTitles.length; start += columns) {
        final int end = (start + columns).clamp(0, cardTitles.length);
        final List<Rect> rowRects = <Rect>[
          for (int index = start; index < end; index++)
            tester.getRect(
              find.byKey(
                ValueKey<String>('desktop-settings-card-${cardTitles[index]}'),
              ),
            ),
        ];
        for (final Rect rect in rowRects.skip(1)) {
          expect(rect.top, closeTo(rowRects.first.top, 0.1));
        }
        for (int index = 1; index < rowRects.length; index++) {
          expect(rowRects[index].left, greaterThan(rowRects[index - 1].right));
        }
      }
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('desktop-settings-ai-save-check')),
      );
      await tester.pumpAndSettle();
      expect(
        find
            .byKey(const ValueKey<String>('desktop-settings-ai-save-check'))
            .hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await _navigate(tester, '首页');
      expect(find.byType(DesktopHomePane), findsOneWidget);
      expect(find.byType(DesktopSettingsPane), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('home right rail grids grow with a wider column', (tester) async {
    await _mount(tester, context.controller, const Size(1280, 800));
    final profile = find.byKey(
      const ValueKey<String>('desktop-home-profile-panel'),
    );
    final quick = find.byKey(
      const ValueKey<String>('desktop-home-quick-panel'),
    );
    final baseProfileSize = tester.getSize(profile);
    final baseQuickSize = tester.getSize(quick);

    await tester.binding.setSurfaceSize(const Size(2560, 1440));
    await tester.pumpAndSettle();

    expect(tester.getSize(profile).width, greaterThan(baseProfileSize.width));
    expect(tester.getSize(profile).height, greaterThan(baseProfileSize.height));
    expect(tester.getSize(quick).width, greaterThan(baseQuickSize.width));
    expect(tester.getSize(quick).height, greaterThan(baseQuickSize.height));
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop top bar uses the enlarged baseline metrics', (
    tester,
  ) async {
    await _mount(tester, context.controller, const Size(1280, 800));

    expect(
      tester
          .getSize(find.byKey(const ValueKey<String>('desktop-top-bar')))
          .height,
      104,
    );
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey<String>('desktop-home-search-shell')),
          )
          .height,
      55,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('hidden and unsupported desktop routes stay unavailable', (
    tester,
  ) async {
    await _mount(tester, context.controller, const Size(1280, 800));
    expect(
      find.descendant(
        of: find.byType(DesktopSidebar),
        matching: find.text('排行榜'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(DesktopSidebar),
        matching: find.text('社区'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey<String>('desktop-sidebar-icon-sidebar_community.png'),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}
