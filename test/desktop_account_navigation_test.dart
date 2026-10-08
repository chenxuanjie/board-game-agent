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
      'desktop logout returns to login after scope drain ($slowScope)',
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
        if (slowScope) {
          expect(account.dataScopeReady, isFalse);
          expect(find.byType(WindowControls), findsOneWidget);
          scopeGate!.complete();
        }
        await tester.runAsync(() => logout);
        await tester.pumpAndSettle();
        expect(find.byType(AccountScreen), findsOneWidget);
        expect(find.byKey(const ValueKey('account-sign-in')), findsOneWidget);
        expect(find.byKey(const ValueKey('account-sign-out')), findsNothing);
        expect(find.byType(WindowControls), findsOneWidget);
        expect(tester.takeException(), isNull);
        // The login page still has a usable back path to the guest workspace.
        await Navigator.of(
          tester.element(find.byType(AccountScreen)),
        ).maybePop();
        await tester.pumpAndSettle();
        expect(find.byType(AccountScreen), findsNothing);
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
