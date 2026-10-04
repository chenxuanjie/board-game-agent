import 'dart:async';

import 'package:app_identity/app_identity.dart';
import 'package:board_game_agent/app/state/app_controller.dart';
import 'package:board_game_agent/core/localization/app_copy.dart';
import 'package:board_game_agent/core/localization/app_language.dart';
import 'package:board_game_agent/core/theme/app_theme.dart';
import 'package:board_game_agent/core/theme/palette_registry.dart';
import 'package:board_game_agent/features/assistant/models/ai_conversation.dart';
import 'package:board_game_agent/features/games/models/game_info.dart';
import 'package:board_game_agent/features/games/models/recent_game_record.dart';
import 'package:board_game_agent/features/identity/services/account_service.dart';
import 'package:board_game_agent/features/identity/models/account_configuration.dart';
import 'package:board_game_agent/ui/mobile/mine_content.dart';
import 'package:board_game_agent/ui/shared/account_scope.dart';
import 'package:board_game_agent/ui/shared/account_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('account tolerates missing scope and theme extension', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: AccountScreen()));
    expect(find.byKey(const ValueKey('account-screen')), findsOneWidget);
    expect(find.byKey(const ValueKey('account-sign-in')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 640.0, 1440.0]) {
    testWidgets('account hides deployment fields at $width', (tester) async {
      final service = _service();
      await tester.binding.setSurfaceSize(Size(width, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _mount(tester, service, textScale: 1.5);
      expect(find.byKey(const ValueKey('account-sign-in')), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
      expect(find.textContaining('Supabase'), findsNothing);
      expect(find.byKey(const ValueKey('account-configure')), findsNothing);
      expect(
        find.text('Sign-in is not ready yet. Please retry later.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('unavailable login fails honestly and stays retryable', (
    tester,
  ) async {
    final service = _service();
    await _mount(tester, service);
    await tester.tap(find.byKey(const ValueKey('account-sign-in')));
    await tester.pumpAndSettle();
    expect(service.error, '登录服务尚未就绪，请稍后重试');
    expect(find.byKey(const ValueKey('account-error')), findsOneWidget);
    expect(find.byKey(const ValueKey('account-sign-out')), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('account-sign-in')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('configured login waits for Synology and permits cancellation', (
    tester,
  ) async {
    final (service, gateway) = await _configuredService(tester);
    await _mount(tester, service);
    await _tapAccountAction(tester, 'account-sign-in');
    await tester.pump();
    expect(gateway.signInCalls, 1);
    expect(find.byKey(const ValueKey('account-loading')), findsOneWidget);
    expect(find.byKey(const ValueKey('account-cancel')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('account-sign-in')))
          .onPressed,
      isNull,
    );
    await _tapAccountAction(tester, 'account-cancel');
    await tester.pumpAndSettle();
    expect(service.isAwaitingBrowser, isFalse);
    expect(find.byKey(const ValueKey('account-loading')), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
  });

  testWidgets('signed-in account displays name and signs out', (tester) async {
    final (service, gateway) = await _configuredService(tester, signedIn: true);
    await _mount(tester, service);
    expect(find.text('Shane'), findsOneWidget);
    expect(find.byKey(const ValueKey('account-sign-out')), findsOneWidget);
    await _tapAccountAction(tester, 'account-sign-out');
    await tester.pumpAndSettle();
    expect(gateway.signOutCalls, 1);
    expect(find.byKey(const ValueKey('account-sign-in')), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
  });

  testWidgets('offline account retains reconnect and sign-out actions', (
    tester,
  ) async {
    final (service, gateway) = await _configuredService(
      tester,
      signedIn: true,
      offline: true,
    );
    await _mount(tester, service);
    expect(find.byKey(const ValueKey('account-sign-out')), findsOneWidget);
    gateway.offline = false;
    await _tapAccountAction(tester, 'account-restore');
    await tester.pumpAndSettle();
    expect(gateway.verifyCalls, 2);
    expect(find.text('Signed in'), findsOneWidget);
  });

  testWidgets('settings entry opens account with inherited service', (
    tester,
  ) async {
    final service = _service();
    await _mount(
      tester,
      service,
      home: const Scaffold(body: AccountEntry(title: 'Account')),
    );
    await tester.tap(find.byKey(const ValueKey('account-settings-entry')));
    await tester.pumpAndSettle();
    expect(find.byType(AccountScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('account-sign-in')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings entry without scope leaves old layout empty', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AccountEntry(title: 'Account')),
      ),
    );
    expect(find.byType(ListTile), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mine preserves device guest nickname and opens account', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'mobile_profile_nickname': 'Device guest',
    });
    final controller = _MineFixture();
    addTearDown(controller.dispose);
    final service = _service(controller);
    await _mount(
      tester,
      service,
      theme: AppTheme.buildTheme(PaletteRegistry.warmwoodStudy),
      home: Scaffold(body: _mine(controller)),
    );
    expect(find.text('Device guest'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mobile-mine-account-entry')));
    await tester.pumpAndSettle();
    expect(find.byType(AccountScreen), findsOneWidget);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('mobile_profile_nickname'), 'Device guest');
  });

  testWidgets('mine without scope retains guest editor and legacy key', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'mobile_profile_nickname': 'Device guest',
    });
    final controller = _MineFixture();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.buildTheme(PaletteRegistry.warmwoodStudy),
        home: Scaffold(body: _mine(controller)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Device guest'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mobile-mine-edit-profile')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(AccountScreen), findsNothing);
    await tester.enterText(find.byType(TextField), 'New guest');
    final input = tester.widget<TextField>(find.byType(TextField)).controller!;
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await _finishNicknameTransition(tester, input);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('mobile_profile_nickname'), 'New guest');
    expect(find.text('New guest'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mobile-mine-edit-profile')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'New guest',
    );
  });

  for (final closeWithBack in [false, true]) {
    testWidgets(
      'guest nickname ${closeWithBack ? 'back' : 'cancel'} preserves value and controller until route removal',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'mobile_profile_nickname': 'Device guest',
        });
        final controller = _MineFixture();
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.buildTheme(PaletteRegistry.warmwoodStudy),
            home: Scaffold(body: _mine(controller)),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('mobile-mine-edit-profile')),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Unsaved nickname');
        final input = tester
            .widget<TextField>(find.byType(TextField))
            .controller!;
        if (closeWithBack) {
          await tester.binding.handlePopRoute();
        } else {
          await tester.tap(find.widgetWithText(TextButton, '取消'));
        }
        await _finishNicknameTransition(tester, input);
        final preferences = await SharedPreferences.getInstance();
        expect(
          preferences.getString('mobile_profile_nickname'),
          'Device guest',
        );
        expect(find.text('Device guest'), findsOneWidget);
        await tester.tap(
          find.byKey(const ValueKey('mobile-mine-edit-profile')),
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'Device guest',
        );
      },
    );
  }
}

Future<void> _finishNicknameTransition(
  WidgetTester tester,
  TextEditingController input,
) async {
  await tester.pump();
  expect(find.byType(AlertDialog, skipOffstage: false), findsOneWidget);
  void listener() {}
  // Pop resolves before the outgoing route has removed its TextField.
  expect(() => input.addListener(listener), returnsNormally);
  input.removeListener(listener);
  expect(tester.takeException(), isNull);
  await tester.pumpAndSettle();
  expect(find.byType(AlertDialog, skipOffstage: false), findsNothing);
  expect(() => input.addListener(listener), throwsFlutterError);
  expect(tester.takeException(), isNull);
}

AccountService _service([_MineFixture? controller]) {
  final app = controller ?? _MineFixture();
  if (controller == null) addTearDown(app.dispose);
  final service = AccountService(controller: app);
  addTearDown(service.dispose);
  return service;
}

Future<void> _mount(
  WidgetTester tester,
  AccountService service, {
  Widget home = const AccountScreen(),
  ThemeData? theme,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    AccountScope(
      service: service,
      child: MaterialApp(
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

MobileMineContent _mine(AppController controller) => MobileMineContent(
  controller: controller,
  onOpenGame: (_) {},
  onFavorites: () {},
  onRecentAll: () {},
  onExplore: () {},
  onActivities: () {},
  onSettings: () {},
);

class _MineFixture extends ChangeNotifier implements AppController {
  @override
  AppCopy get copy => AppCopy(AppLanguage.zhHans);
  @override
  List<GameInfo> get recentlyViewedGames => [];
  @override
  List<RecentGameRecord> get recentGameRecords => [];
  @override
  List<AiConversation> get conversations => [];
  @override
  int get favoriteCount => 0;
  @override
  int get unreadActivityCount => 0;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Real account/controller wiring with a deterministic gateway; no live login.
Future<(AccountService, _UiGateway)> _configuredService(
  WidgetTester tester, {
  bool signedIn = false,
  bool offline = false,
}) async {
  final result = await tester.runAsync(() async {
    final controller = _MineFixture();
    final gateway = _UiGateway()
      ..current = signedIn
          ? const IdentityUser(id: 'fixture-user', displayName: 'Shane')
          : null
      ..offline = offline;
    final service = AccountService(
      controller: controller,
      gatewayFactory: (_) async => gateway,
      switchScope: (_) async {},
    );
    await service.saveConfiguration(
      AccountConfiguration.fromFields(
        supabaseUrl: 'https://project.example.test',
        publishableKey: 'sb_publishable_abcdefghijklmnop',
        webCallback: 'https://app.example.test/auth/callback',
      ),
    );
    return (service, gateway, controller);
  });
  final (service, gateway, controller) = result!;
  addTearDown(() async {
    service.dispose();
    controller.dispose();
    await gateway.events.close();
  });
  return (service, gateway);
}

Future<void> _tapAccountAction(WidgetTester tester, String key) async {
  await tester.runAsync(() async {
    await tester.tap(find.byKey(ValueKey(key)));
    await Future<void>.delayed(Duration.zero);
  });
  await tester.pump();
}

class _UiGateway implements IdentityGateway, IdentityLocalSessionCleanup {
  final events = StreamController<IdentityEvent>.broadcast();
  IdentityUser? current;
  bool offline = false;
  int signInCalls = 0;
  int signOutCalls = 0;
  int verifyCalls = 0;

  @override
  IdentityUser? get cachedUser => current;
  @override
  Stream<IdentityEvent> get changes => events.stream;

  @override
  Future<bool> beginSignIn(IdentityProvider provider) async {
    signInCalls++;
    return true;
  }

  @override
  Future<IdentityUser?> verifyCurrentUser() async {
    verifyCalls++;
    if (offline) throw const IdentityFailure(IdentityFailureCode.network);
    return current;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    await clearLocalSession();
  }

  @override
  Future<void> clearLocalSession() async {
    current = null;
    events.add(const IdentityEvent(type: IdentityEventType.signedOut));
  }
}
