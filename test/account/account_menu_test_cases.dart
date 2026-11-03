part of '../account_menu_test.dart';

Widget _menuHome({
  VoidCallback? onAccount,
  VoidCallback? onNotifications,
  int unread = 3,
}) => Scaffold(
  body: Align(
    alignment: Alignment.topRight,
    child: AccountMenuButton(
      unreadCount: unread,
      onOpenAccount: onAccount ?? () {},
      onOpenNotifications: onNotifications ?? () {},
    ),
  ),
);

Future<void> _openAccountMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('account-menu-button')));
  await tester.pumpAndSettle();
}

void _registerAccountMenuTests() {
  testWidgets('warm popover is removed when its anchor is disposed', (
    tester,
  ) async {
    final (service, _) = await _configuredService(tester);
    final visible = ValueNotifier(true);
    addTearDown(visible.dispose);
    await _mount(
      tester,
      service,
      theme: AppTheme.buildTheme(PaletteRegistry.warmwoodStudy),
      home: ValueListenableBuilder<bool>(
        valueListenable: visible,
        builder: (_, value, _) => value ? _menuHome() : const Scaffold(),
      ),
    );
    await _openAccountMenu(tester);
    visible.value = false;
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('account-popover-panel')), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('warm popover honors reduced motion', (tester) async {
    final (service, _) = await _configuredService(tester);
    await _mount(
      tester,
      service,
      theme: AppTheme.buildTheme(PaletteRegistry.warmwoodStudy),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: _menuHome(),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('account-menu-button')));
    await tester.pump();
    await tester.pump();
    final panel = find.byKey(const ValueKey('account-popover-panel'));
    final opacity = find
        .ancestor(of: panel, matching: find.byType(Opacity))
        .first;
    expect(tester.widget<Opacity>(opacity).opacity, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump();
    expect(panel, findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('warm popover follows its anchor after resizing', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(900, 700));
    final (service, _) = await _configuredService(tester);
    await _mount(
      tester,
      service,
      theme: AppTheme.buildTheme(PaletteRegistry.warmwoodStudy),
      home: _menuHome(),
    );
    await _openAccountMenu(tester);
    await tester.binding.setSurfaceSize(const Size(500, 700));
    await tester.pumpAndSettle();
    final button = tester.getRect(
      find.byKey(const ValueKey('account-menu-button')),
    );
    final panel = tester.getRect(
      find.byKey(const ValueKey('account-popover-panel')),
    );
    expect(panel.right, lessThanOrEqualTo(500));
    expect(panel.right, closeTo(button.right - 16, 1));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'warm popover cannot reopen stale actions after identity changes',
    (tester) async {
      final (service, _) = await _configuredService(tester, signedIn: true);
      await _mount(
        tester,
        service,
        theme: AppTheme.buildTheme(PaletteRegistry.warmwoodStudy),
        home: _menuHome(),
      );
      await _openAccountMenu(tester);
      await tester.runAsync(service.signOut);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(
        tester.getCenter(find.byKey(const ValueKey('account-menu-button'))),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('account-popover-panel')), findsNothing);
      await _openAccountMenu(tester);
      expect(find.text('Guest'), findsOneWidget);
      expect(find.byKey(const ValueKey('account-menu-signOut')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('warm popover reverses smoothly on rapid reopen', (tester) async {
    final (service, _) = await _configuredService(tester);
    await _mount(
      tester,
      service,
      theme: AppTheme.buildTheme(PaletteRegistry.warmwoodStudy),
      home: _menuHome(),
    );
    await _openAccountMenu(tester);
    final panel = find.byKey(const ValueKey('account-popover-panel'));
    final opacity = find
        .ancestor(of: panel, matching: find.byType(Opacity))
        .first;
    await tester.tapAt(const Offset(20, 400));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final closing = tester.widget<Opacity>(opacity).opacity;
    expect(closing, inExclusiveRange(0.0, 1.0));
    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey('account-menu-button'))),
    );
    await tester.pump();
    final resumed = tester.widget<Opacity>(opacity).opacity;
    expect(resumed, closeTo(closing, .03));
    await tester.pumpAndSettle();
    expect(panel, findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('warm popover moves above an anchor near the bottom', (
    tester,
  ) async {
    final (service, _) = await _configuredService(tester);
    await _mount(
      tester,
      service,
      theme: AppTheme.buildTheme(PaletteRegistry.warmwoodStudy),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomRight,
          child: AccountMenuButton(
            onOpenAccount: () {},
            onOpenNotifications: () {},
          ),
        ),
      ),
    );
    await _openAccountMenu(tester);
    final panel = tester.getRect(
      find.byKey(const ValueKey('account-popover-panel')),
    );
    final button = tester.getRect(
      find.byKey(const ValueKey('account-menu-button')),
    );
    expect(panel.bottom, lessThan(button.top));
    expect(tester.takeException(), isNull);
  });
  testWidgets('warm popover supports keyboard selection', (tester) async {
    final (service, _) = await _configuredService(tester);
    var accounts = 0;
    await _mount(
      tester,
      service,
      theme: AppTheme.buildTheme(PaletteRegistry.warmwoodStudy),
      home: _menuHome(onAccount: () => accounts++),
    );
    await _openAccountMenu(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(accounts, 1);
  });
  testWidgets(
    'warm popover keeps account actions and closes on identity change',
    (tester) async {
      final (service, gateway) = await _configuredService(
        tester,
        signedIn: true,
      );
      var notifications = 0;
      await _mount(
        tester,
        service,
        theme: AppTheme.buildTheme(PaletteRegistry.warmwoodStudy),
        home: _menuHome(onNotifications: () => notifications++),
      );
      final calls = gateway.verifyCalls;
      await _openAccountMenu(tester);
      expect(find.text('Shane'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('account-menu-signOut')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('account-menu-notifications')),
      );
      await tester.pumpAndSettle();
      expect(notifications, 1);
      expect(gateway.verifyCalls, calls);
      await _openAccountMenu(tester);
      await tester.runAsync(service.signOut);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('account-popover-panel')), findsNothing);
      await _openAccountMenu(tester);
      expect(find.text('Guest'), findsOneWidget);
      expect(find.byKey(const ValueKey('account-menu-signOut')), findsNothing);
    },
  );

  for (final size in [const Size(320, 568), const Size(1440, 900)]) {
    testWidgets('warm popover remains within $size with enlarged text', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(size);
      final (service, _) = await _configuredService(tester, signedIn: true);
      await _mount(
        tester,
        service,
        textScale: 2,
        theme: AppTheme.buildTheme(PaletteRegistry.warmwoodStudy),
        home: _menuHome(),
      );
      await _openAccountMenu(tester);
      final rect = tester.getRect(
        find.byKey(const ValueKey('account-popover-panel')),
      );
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(size.width));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(size.height));
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'warm account popover opens from its anchor and closes with Escape',
    (tester) async {
      final (service, gateway) = await _configuredService(tester);
      await _mount(
        tester,
        service,
        theme: AppTheme.buildTheme(PaletteRegistry.warmwoodStudy),
        home: _menuHome(),
      );
      final before = gateway.verifyCalls;
      await tester.tap(find.byKey(const ValueKey('account-menu-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 140));
      final panel = find.byKey(const ValueKey('account-popover-panel'));
      expect(panel, findsOneWidget);
      expect(find.byKey(const ValueKey('account-popover-arrow')), findsNothing);
      final shape =
          tester.widget<Material>(panel).shape! as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(16));
      expect(tester.getSize(panel).width, inInclusiveRange(272, 320));
      expect(
        tester.getRect(panel).top,
        greaterThan(
          tester
              .getRect(find.byKey(const ValueKey('account-menu-button')))
              .bottom,
        ),
      );
      final opacity = find
          .ancestor(of: panel, matching: find.byType(Opacity))
          .first;
      expect(tester.widget<Opacity>(opacity).opacity, closeTo(.875, .03));
      await tester.pumpAndSettle();
      expect(gateway.verifyCalls, before);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(panel, findsNothing);
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('account-menu-button')),
            )
            .focusNode
            ?.hasFocus,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Account menu guest shows login and real unread notifications', (
    tester,
  ) async {
    final (service, gateway) = await _configuredService(tester);
    var accounts = 0, notifications = 0;
    await _mount(
      tester,
      service,
      home: _menuHome(
        onAccount: () => accounts++,
        onNotifications: () => notifications++,
      ),
    );
    final verified = gateway.verifyCalls;
    await _openAccountMenu(tester);
    expect(find.text('Guest'), findsOneWidget);
    expect(find.text('Signed out'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Sign out'), findsNothing);
    expect(find.text('3'), findsOneWidget);
    expect(gateway.verifyCalls, verified);
    await tester.tap(find.byKey(const ValueKey('account-menu-notifications')));
    await tester.pumpAndSettle();
    expect(notifications, 1);
    await _openAccountMenu(tester);
    await tester.tap(find.byKey(const ValueKey('account-menu-account')));
    await tester.pumpAndSettle();
    expect(accounts, 1);
  });

  testWidgets(
    'Account menu signs out once and tracks actual pending completion',
    (tester) async {
      final (service, gateway) = await _configuredService(
        tester,
        signedIn: true,
      );
      gateway.signOutGate = Completer<void>();
      await _mount(tester, service, home: _menuHome());
      await _openAccountMenu(tester);
      expect(find.text('Shane'), findsOneWidget);
      expect(find.text('Signed in'), findsOneWidget);
      expect(find.text('Manage account'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('account-menu-signOut')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(gateway.signOutCalls, 1);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('account-menu-button')));
      await tester.pump(const Duration(milliseconds: 250));
      final login = tester.widget<PopupMenuItem>(
        find.byKey(const ValueKey('account-menu-account')),
      );
      expect(login.enabled, isFalse);
      expect(find.byKey(const ValueKey('account-menu-signOut')), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(() async {
        gateway.signOutGate!.complete();
        for (var i = 0; i < 50 && service.isBusy; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();
      expect(service.isSignedIn, isFalse);
      expect(gateway.signOutCalls, 1);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await _openAccountMenu(tester);
      expect(find.text('Signed out'), findsOneWidget);
    },
  );

  testWidgets(
    'Account menu keeps offline identity and reports unconfirmed logout',
    (tester) async {
      final (service, gateway) = await _configuredService(
        tester,
        signedIn: true,
        offline: true,
      );
      await _mount(tester, service, home: _menuHome());
      await _openAccountMenu(tester);
      expect(find.text('Shane'), findsOneWidget);
      expect(find.text('Offline'), findsOneWidget);
      gateway.failSignOut = true;
      await tester.tap(find.byKey(const ValueKey('account-menu-signOut')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(() async {
        for (var i = 0; i < 50 && service.isBusy; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();
      expect(service.isSignedIn, isFalse);
      expect(service.error, isNotNull);
      expect(find.byKey(const ValueKey('app-failure-notice')), findsOneWidget);
      await _openAccountMenu(tester);
      expect(find.text(service.error!), findsWidgets);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Account menu closes stale actions when identity changes externally',
    (tester) async {
      final (service, _) = await _configuredService(tester, signedIn: true);
      await _mount(tester, service, home: _menuHome());
      await _openAccountMenu(tester);
      await tester.runAsync(service.signOut);
      await tester.pumpAndSettle();
      expect(find.text('Sign out'), findsNothing);
      await _openAccountMenu(tester);
      expect(find.text('Guest'), findsOneWidget);
    },
  );

  testWidgets(
    'Account menu Escape, keyboard selection, outside click and rapid reopen',
    (tester) async {
      final (service, _) = await _configuredService(tester);
      var accounts = 0;
      await _mount(
        tester,
        service,
        home: _menuHome(onAccount: () => accounts++),
      );
      await _openAccountMenu(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('account-menu-button')));
      await tester.pumpAndSettle();
      expect(find.text('Guest'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Guest'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(accounts, 1);
      await _openAccountMenu(tester);
      await tester.tapAt(const Offset(20, 400));
      await tester.pumpAndSettle();
      expect(find.text('Guest'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(320, 568), const Size(1440, 900)]) {
    testWidgets('Account menu adapts to $size at 200 percent text', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(size);
      final (service, _) = await _configuredService(tester, signedIn: true);
      await _mount(
        tester,
        service,
        textScale: 2,
        theme: AppTheme.buildTheme(PaletteRegistry.spatialCinema),
        home: _menuHome(unread: 120),
      );
      await _openAccountMenu(tester);
      expect(find.text('99+'), findsOneWidget);
      expect(
        tester
            .getRect(find.byKey(const ValueKey('account-menu-account')))
            .right,
        lessThanOrEqualTo(size.width),
      );
      expect(tester.takeException(), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    });
  }

  testWidgets('Account menu removal while open leaves no orphan route', (
    tester,
  ) async {
    final (service, _) = await _configuredService(tester);
    final visible = ValueNotifier(true);
    addTearDown(visible.dispose);
    await _mount(
      tester,
      service,
      home: Scaffold(
        body: ValueListenableBuilder(
          valueListenable: visible,
          builder: (_, show, _) => show ? _menuHome() : const SizedBox.shrink(),
        ),
      ),
    );
    await _openAccountMenu(tester);
    visible.value = false;
    await tester.pumpAndSettle();
    expect(find.text('Guest'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  if (const bool.fromEnvironment('RENDER_ACCOUNT_MENU')) {
    for (final size in [const Size(320, 568), const Size(900, 600)]) {
      testWidgets('Account menu render at $size', (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.binding.setSurfaceSize(size);
        final (service, _) = await _configuredService(tester, signedIn: true);
        await tester.runAsync(() async {
          await (FontLoader('Noto Sans SC')..addFont(
                rootBundle.load('assets/fonts/NotoSansSC-Variable.ttf'),
              ))
              .load();
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
        });
        final boundaryKey = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundaryKey,
            child: AccountScope(
              service: service,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: AppTheme.buildTheme(PaletteRegistry.spatialCinema),
                home: _menuHome(),
              ),
            ),
          ),
        );
        await _openAccountMenu(tester);
        await tester.runAsync(() async {
          final boundary =
              boundaryKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          try {
            final bytes = await image.toByteData(format: ImageByteFormat.png);
            await File(
              'build/diagnostics/account-menu-${size.width.toInt()}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
        expect(tester.takeException(), isNull);
      });
    }
  }
}
