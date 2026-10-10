import 'dart:async';

import 'package:app_identity/app_identity.dart';
import 'package:board_game_agent/app/state/app_controller.dart';
import 'package:board_game_agent/core/localization/app_copy.dart';
import 'package:board_game_agent/core/localization/app_language.dart';
import 'package:board_game_agent/core/models/connectivity_status.dart';
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
import 'package:board_game_agent/features/library/models/asset_source_config.dart';
import 'support/account_sync_fixture.dart';
import 'support/memory_login_storage.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'unsupported Web hides credential fields and sign-in action while keeping guest access',
    (tester) async {
      final app = _MineFixture();
      final service = AccountService(
        savedLoginStorage: MemoryLoginStorage(),
        controller: app,
        signInSupported: false,
      );
      addTearDown(service.dispose);
      addTearDown(app.dispose);
      await _mount(tester, service);
      expect(find.byType(TextFormField), findsNothing);
      expect(find.byKey(const ValueKey('account-sign-in')), findsNothing);
      expect(find.textContaining('Web sign-in is unavailable'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('account tolerates missing scope and theme extension', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: AccountScreen()));
    expect(find.byKey(const ValueKey('account-screen')), findsOneWidget);
    expect(find.byKey(const ValueKey('account-sign-in')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 640.0, 1440.0]) {
    testWidgets('cloud controls stay usable with large text at $width', (
      tester,
    ) async {
      final files = MemoryPrivateFiles();
      final (service, _) = await _configuredService(
        tester,
        signedIn: true,
        files: files,
      );
      await tester.binding.setSurfaceSize(Size(width, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _mount(tester, service, textScale: 1.5);
      expect(
        find.byKey(const ValueKey('account-cloud-enabled')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('account-cloud-sync')), findsOneWidget);
      await _tapAccountAction(tester, 'account-cloud-enabled');
      await tester.pumpAndSettle();
      expect(service.cloud?.enabled, isFalse);
      await _tapAccountAction(tester, 'account-edit-nickname');
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'My name');
      await tester.tap(find.text('Save'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(service.displayName, 'My name');
      expect(tester.takeException(), isNull);
      expect(files.objects, isEmpty);
    });
    testWidgets('account hides deployment fields at $width', (tester) async {
      final service = _service();
      await tester.binding.setSurfaceSize(Size(width, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _mount(tester, service, textScale: 1.5);
      expect(find.byKey(const ValueKey('account-sign-in')), findsOneWidget);
      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(find.textContaining('Supabase'), findsNothing);
      expect(find.byKey(const ValueKey('account-configure')), findsNothing);
      expect(
        find.text('Use your Synology account and password.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('unavailable login stays retryable without deployment fields', (
    tester,
  ) async {
    final app = _MineFixture();
    final service = AccountService(
      savedLoginStorage: MemoryLoginStorage(),
      controller: app,
      gatewayFactory: (_) async =>
          throw const IdentityFailure(IdentityFailureCode.storage),
      switchScope: (_) async {},
    );
    addTearDown(service.dispose);
    addTearDown(app.dispose);
    await tester.runAsync(service.initialize);
    await _mount(tester, service);
    await tester.enterText(
      find.byKey(const ValueKey('account-username')),
      'Shane',
    );
    await tester.enterText(
      find.byKey(const ValueKey('account-password')),
      'fixture-password',
    );
    await _tapAccountAction(tester, 'account-sign-in');
    await tester.pumpAndSettle();
    expect(service.error, '账号或资料连接未完成，请重试');
    expect(find.byKey(const ValueKey('account-error')), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.textContaining('Supabase'), findsNothing);
  });

  testWidgets(
    'OTP appears only when NAS requests it and password clears after success',
    (tester) async {
      final (service, gateway) = await _configuredService(tester);
      await _mount(tester, service);
      expect(find.byKey(const ValueKey('account-otp')), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('account-username')),
        'Shane',
      );
      await tester.enterText(
        find.byKey(const ValueKey('account-password')),
        'fixture-password',
      );
      await _tapAccountAction(tester, 'account-sign-in');
      await tester.pumpAndSettle();
      expect(service.needsOtp, isTrue);
      expect(find.byKey(const ValueKey('account-otp')), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('account-otp')),
        '123456',
      );
      await _tapAccountAction(tester, 'account-sign-in');
      await tester.pumpAndSettle();
      expect(gateway.signInCalls, 2);
      expect(find.byKey(const ValueKey('account-sign-out')), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
      await _tapAccountAction(tester, 'account-sign-out');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('account-password')),
            )
            .controller!
            .text,
        isEmpty,
      );
    },
  );

  testWidgets('signed-in account displays name and signs out', (tester) async {
    final (service, gateway) = await _configuredService(tester, signedIn: true);
    await _mount(tester, service);
    expect(find.text('Shane'), findsOneWidget);
    expect(find.byKey(const ValueKey('account-sign-out')), findsOneWidget);
    await _tapAccountAction(tester, 'account-sign-out');
    await tester.pumpAndSettle();
    expect(gateway.signOutCalls, 1);
    expect(find.byKey(const ValueKey('account-sign-in')), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
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

  testWidgets(
    'profile avatar and name share one account route and refresh after logout',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'mobile_profile_nickname': 'Device guest',
      });
      final (service, _) = await _configuredService(tester, signedIn: true);
      final controller = _MineFixture();
      addTearDown(controller.dispose);
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _mount(
        tester,
        service,
        theme: AppTheme.buildTheme(PaletteRegistry.warmwoodStudy),
        home: Scaffold(body: _mine(controller)),
      );
      expect(find.text('Shane'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('mobile-mine-edit-profile')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('mobile-mine-avatar')));
      await tester.tap(find.byKey(const ValueKey('mobile-mine-profile-name')));
      await tester.pumpAndSettle();
      expect(find.byType(AccountScreen, skipOffstage: false), findsOneWidget);
      await tester.runAsync(() => service.saveNickname('新的账号昵称'));
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('新的账号昵称'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mobile-mine-profile-name')));
      await tester.pumpAndSettle();
      expect(find.byType(AccountScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.runAsync(service.signOut);
      await tester.pumpAndSettle();
      expect(find.text('新的账号昵称'), findsNothing);
      expect(find.text('Device guest'), findsOneWidget);
      expect(find.text('点击登录'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mobile-mine-avatar')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('account-sign-in')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'profile statistics have separate tap actions and enlarged text fits',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'mobile_profile_nickname': '很长的本机访客名称需要正常显示',
      });
      final controller = _MineFixture();
      final service = _service(controller);
      addTearDown(controller.dispose);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var favoriteTaps = 0;
      var conversationTaps = 0;
      for (final width in [320.0, 390.0, 720.0]) {
        await tester.binding.setSurfaceSize(Size(width, 844));
        await _mount(
          tester,
          service,
          textScale: 2,
          theme: AppTheme.buildTheme(PaletteRegistry.classic),
          home: Scaffold(
            body: MobileMineContent(
              key: ValueKey(width),
              controller: controller,
              onOpenGame: (_) {},
              onFavorites: () => favoriteTaps++,
              onConversations: () => conversationTaps++,
              onRecentAll: () {},
              onExplore: () {},
              onActivities: () {},
              onSettings: () {},
            ),
          ),
        );
        await tester.tap(
          find.byKey(const ValueKey('mobile-mine-favorites-stat')),
        );
        await tester.tap(
          find.byKey(const ValueKey('mobile-mine-conversations-stat')),
        );
        expect(find.byType(AccountScreen), findsNothing);
        expect(tester.takeException(), isNull);
      }
      expect(favoriteTaps, 3);
      expect(conversationTaps, 3);
    },
  );

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
    await tester.tap(find.byKey(const ValueKey('mobile-mine-account-entry')));
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
    await tester.tap(find.byKey(const ValueKey('mobile-mine-account-entry')));
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
          find.byKey(const ValueKey('mobile-mine-account-entry')),
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
          find.byKey(const ValueKey('mobile-mine-account-entry')),
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
  final service = AccountService(
    savedLoginStorage: MemoryLoginStorage(),
    controller: app,
  );
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
        theme: theme ?? AppTheme.buildTheme(PaletteRegistry.classic),
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
  ConnectivityStatus get assetConnectivityStatus =>
      ConnectivityStatus.unknown();
  @override
  Map<String, ConnectivityStatus> get assetSourceStatuses => {};
  @override
  List<AssetSourceConfig> get assetSourceConfigs => AssetSourceConfig.defaults;
  @override
  bool get accountCloudIdle => false;
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
  AccountPrivateFiles? files,
}) async {
  final result = await tester.runAsync(() async {
    final controller = _MineFixture();
    final gateway = _UiGateway()
      ..current = signedIn
          ? const IdentityUser(id: 'fixture-user', displayName: 'Shane')
          : null
      ..offline = offline;
    final service = AccountService(
      savedLoginStorage: MemoryLoginStorage(),
      controller: controller,
      gatewayFactory: (_) async => gateway,
      switchScope: (_) async {},
      privateFilesFactory: files == null ? null : (_) => files,
    );
    await service.saveConfiguration(
      AccountConfiguration.fromFields(nasUrl: 'https://nas.example.test:5001'),
    );
    await service.loadSavedLogins();
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
  await tester.ensureVisible(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    await tester.tap(find.byKey(ValueKey(key)));
    final service = AccountScope.maybeOf(
      tester.element(find.byKey(ValueKey(key))),
    );
    for (var i = 0; i < 100 && service?.isBusy == true; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
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
  Future<IdentityUser> signIn({
    required String account,
    required String password,
    String? otp,
  }) async {
    signInCalls++;
    if (otp == null) {
      throw const IdentityFailure(IdentityFailureCode.otpRequired);
    }
    return current = const IdentityUser(
      id: 'fixture-user',
      displayName: 'Shane',
    );
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

  @override
  void cancelRequests() {}
  @override
  Future<void> dispose() async {}
}
