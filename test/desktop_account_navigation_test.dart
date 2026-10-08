import 'dart:async';
import 'package:app_identity/app_identity.dart';
import 'package:board_game_agent/app/state/app_controller.dart';
import 'package:board_game_agent/features/assistant/services/ai_service.dart';
import 'package:board_game_agent/features/assistant/services/speech_service.dart';
import 'package:board_game_agent/features/assistant/services/tts_service.dart';
import 'package:board_game_agent/features/games/services/game_manifest_service.dart';
import 'package:board_game_agent/features/identity/models/account_configuration.dart';
import 'package:board_game_agent/features/identity/services/account_service.dart';
import 'package:board_game_agent/features/library/services/remote_asset_service.dart';
import 'package:board_game_agent/features/settings/services/preferences_service.dart';
import 'package:board_game_agent/main.dart';
import 'package:board_game_agent/ui/desktop/workspace.dart';
import 'package:board_game_agent/ui/desktop/window_controls.dart';
import 'package:board_game_agent/ui/shared/account_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:webdav_settings/webdav_settings.dart';
import 'support/memory_login_storage.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('window_manager'),
          (call) async => call.method == 'isMaximized' ? false : null,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), null);
  });
  for (final slowScope in [false, true]) {
    testWidgets(
      'desktop logout shows login directly without a home frame ($slowScope)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        late _Controller controller;
        late _Gateway gateway;
        late AccountService account;
        Completer<void>? scopeGate;
        await tester.runAsync(() async {
          controller = _Controller();
          gateway = _Gateway();
          account = AccountService(
            controller: controller,
            savedLoginStorage: MemoryLoginStorage(),
            credentialStore: (_) => MemoryLoginStorage(),
            gatewayFactory: (_) async => gateway,
            switchScope: (scope) async {
              if (scope == null && scopeGate != null) await scopeGate.future;
            },
          );
          await account.saveConfiguration(
            AccountConfiguration.fromFields(
              nasUrl: 'https://nas.example.test:5001',
            ),
          );
        });
        final settings = WebDavSettingsController(
          store: _Store(),
          connectionTester: _Tester(),
        );
        await tester.pumpWidget(
          BoardGameAgentApp(
            controller: controller,
            accountService: account,
            updateSettingsController: settings,
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pumpAndSettle();
        expect(account.isSignedIn, isTrue);
        final navigator = Navigator.of(
          tester.element(find.byType(DesktopWorkspace)),
        );
        navigator.push(
          MaterialPageRoute<void>(builder: (_) => const AccountScreen()),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('account-sign-out')), findsOneWidget);
        if (slowScope) scopeGate = Completer<void>();
        late Future<void> logout;
        await tester.runAsync(() async {
          await tester.ensureVisible(
            find.byKey(const ValueKey('account-sign-out')),
          );
          logout = account.signOut();
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await tester.pump();
        expect(find.byType(DesktopWorkspace), findsNothing);
        expect(find.byKey(const ValueKey('app-startup-loading')), findsNothing);
        if (slowScope) {
          expect(account.dataScopeReady, isFalse);
          expect(find.byType(WindowControls), findsOneWidget);
          expect(find.byType(AccountScreen), findsOneWidget);
          expect(
            tester
                .widget<FilledButton>(
                  find.byKey(const ValueKey('account-sign-in')),
                )
                .onPressed,
            isNull,
          );
          await tester.tap(find.byType(BackButton));
          await tester.pump();
          expect(find.byType(AccountScreen), findsOneWidget);
          expect(find.byType(DesktopWorkspace), findsNothing);
          expect(
            find.byKey(const ValueKey('app-startup-loading')),
            findsNothing,
          );
          scopeGate!.complete();
        }
        await tester.runAsync(() => logout);
        // Inspect every transition frame, rather than only its settled result.
        // Neither a rebuilt startup screen nor a home route may be painted.
        for (final frame in [
          Duration.zero,
          const Duration(milliseconds: 1),
          const Duration(milliseconds: 16),
          const Duration(milliseconds: 16),
          const Duration(milliseconds: 32),
          const Duration(milliseconds: 120),
          const Duration(milliseconds: 240),
        ]) {
          await tester.pump(frame);
          expect(find.byType(DesktopWorkspace), findsNothing);
          expect(
            find.byKey(const ValueKey('app-startup-loading')),
            findsNothing,
          );
          expect(find.byKey(const ValueKey('account-sign-in')), findsOneWidget);
          expect(find.byType(WindowControls), findsOneWidget);
        }
        await tester.pumpAndSettle();
        expect(find.byType(AccountScreen), findsOneWidget);
        expect(find.byKey(const ValueKey('account-sign-in')), findsOneWidget);
        expect(find.byKey(const ValueKey('account-sign-out')), findsNothing);
        expect(find.byType(WindowControls), findsOneWidget);
        expect(tester.takeException(), isNull);
        // Signing in again must replace the login root with the account home,
        // without treating its rebuilt Navigator as a fresh application start.
        late Future<void> login;
        await tester.runAsync(() async {
          login = account.signIn(
            account: 'Fixture',
            password: 'fixture-password',
          );
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        for (var frame = 0; frame < 4; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(
            find.byKey(const ValueKey('app-startup-loading')),
            findsNothing,
          );
        }
        await tester.runAsync(() => login);
        await tester.pumpAndSettle();
        expect(find.byType(DesktopWorkspace), findsOneWidget);
        expect(find.byType(AccountScreen), findsNothing);
        // A subsequent logout uses the same direct login root. Only an explicit
        // back action after scope completion may return to the guest workspace.
        await tester.runAsync(() async {
          logout = account.signOut();
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await tester.pump();
        await tester.runAsync(() => logout);
        await tester.pumpAndSettle();
        expect(find.byType(AccountScreen), findsOneWidget);
        expect(find.byType(DesktopWorkspace), findsNothing);
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.byType(AccountScreen), findsNothing);
        expect(find.byType(DesktopWorkspace), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        await gateway.events.close();
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }
}

class _Controller extends AppController {
  _Controller()
    : super(
        preferencesService: PreferencesService(),
        aiService: _Ai(),
        gameManifestService: GameManifestService(),
        remoteAssetService: RemoteAssetService(),
        speechService: _Speech(),
        ttsService: _Tts(),
      );
  @override
  Future<void> initialize() async {}
  @override
  bool get checkForUpdates => false;
}

class _Ai extends Fake implements AiService {
  @override
  void dispose() {}
}

class _Speech extends SpeechService {
  @override
  Future<void> cancelListening() async {}
}

class _Tts extends TtsService {
  @override
  Future<void> stop() async {}
}

class _Store implements WebDavSettingsStore {
  @override
  Future<WebDavSettings?> load() async => null;
  @override
  Future<void> save(WebDavSettings settings) async {}
}

class _Tester implements WebDavConnectionTester {
  @override
  Future<WebDavConnectionTestResult> test(WebDavSettings settings) async =>
      const WebDavConnectionTestResult.success();
}

class _Gateway implements IdentityGateway, IdentityLocalSessionCleanup {
  final events = StreamController<IdentityEvent>.broadcast();
  IdentityUser? current = const IdentityUser(
    id: 'fixture-user',
    displayName: 'Fixture',
  );
  @override
  IdentityUser? get cachedUser => current;
  @override
  Stream<IdentityEvent> get changes => events.stream;
  @override
  Future<IdentityUser?> verifyCurrentUser() async => current;
  @override
  Future<IdentityUser> signIn({
    required String account,
    required String password,
    String? otp,
  }) async =>
      current = const IdentityUser(id: 'fixture-user', displayName: 'Fixture');
  @override
  Future<void> signOut() => clearLocalSession();
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
