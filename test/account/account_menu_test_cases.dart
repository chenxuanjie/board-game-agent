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
