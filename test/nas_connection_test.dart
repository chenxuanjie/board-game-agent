import 'dart:async';
import 'dart:convert';
import 'package:app_identity/app_identity.dart';
import 'package:board_game_agent/app/state/app_controller.dart';
import 'package:board_game_agent/features/identity/models/account_configuration.dart';
import 'package:board_game_agent/features/identity/services/account_service.dart';
import 'package:board_game_agent/features/library/models/asset_source_config.dart';
import 'package:board_game_agent/ui/shared/account_screen.dart';
import 'package:board_game_agent/ui/shared/account_scope.dart';
import 'package:board_game_agent/core/theme/app_theme.dart';
import 'package:board_game_agent/features/settings/services/preferences_service.dart';
import 'package:board_game_agent/features/settings/services/settings_transfer_service.dart';
import 'package:board_game_agent/features/settings/models/configuration_transfer.dart';
import 'package:board_game_agent/features/library/services/board_game_remote_layout.dart';
import 'package:board_game_agent/features/assistant/services/ai_service.dart';
import 'package:board_game_agent/features/assistant/services/speech_service.dart';
import 'package:board_game_agent/features/assistant/services/tts_service.dart';
import 'package:board_game_agent/features/games/services/game_manifest_service.dart';
import 'package:board_game_agent/features/library/services/remote_asset_service.dart';
import 'package:flutter/services.dart';
import 'package:board_game_agent/core/theme/palette_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webdav_settings/webdav_settings.dart';

class _NoAi extends Fake implements AiService {}

class _App extends AppController {
  _App()
    : super(
        preferencesService: PreferencesService(),
        aiService: _NoAi(),
        gameManifestService: GameManifestService(),
        remoteAssetService: RemoteAssetService(),
        speechService: SpeechService(),
        ttsService: TtsService(),
      );
  List<AssetSourceConfig> get sources => assetSourceConfigs;
}

class _Credentials implements IdentitySessionStorage {
  String? value;
  bool fail = false;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async {
    if (fail) throw const IdentityFailure(IdentityFailureCode.storage);
    value = next;
  }

  @override
  Future<void> delete() async {
    value = null;
  }
}

class _DavStore implements WebDavSettingsStore {
  WebDavSettings? value;
  @override
  Future<WebDavSettings?> load() async => value;
  @override
  Future<void> save(WebDavSettings next) async {
    value = next;
  }
}

class _Check implements WebDavConnectionTester {
  @override
  Future<WebDavConnectionTestResult> test(WebDavSettings settings) async =>
      const WebDavConnectionTestResult.success();
}

class _Gateway implements IdentityGateway, IdentityLocalSessionCleanup {
  _Gateway(this.failure);
  IdentityFailureCode? failure;
  IdentityUser? current;
  Completer<void>? pending;
  Completer<IdentityUser?>? verification;
  final events = StreamController<IdentityEvent>.broadcast();
  int calls = 0;
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
    calls++;
    if (pending != null) await pending!.future;
    if (failure != null &&
        !(failure == IdentityFailureCode.otpRequired && otp != null)) {
      throw IdentityFailure(failure!);
    }
    return current = IdentityUser(
      id: account == 'other' ? 'other-verified-uid' : 'verified-uid',
      displayName: account,
    );
  }

  @override
  Future<IdentityUser?> verifyCurrentUser() async =>
      verification == null ? current : await verification!.future;
  @override
  Future<void> signOut() async {
    current = null;
  }

  @override
  Future<void> clearLocalSession() async {
    current = null;
  }

  @override
  void cancelRequests() {}
  @override
  Future<void> dispose() async {}
}

AccountConfiguration _config() => AccountConfiguration(
  nasOrigin: Uri.parse('https://outside.example:5001'),
  identityOrigin: Uri.parse('https://outside.example:5001'),
  activeServerId: 'outside',
  servers: [
    NasServerAddress(
      id: 'inside',
      name: '内网访问',
      address: 'https://inside.example',
    ),
    NasServerAddress(
      id: 'outside',
      name: '外网访问',
      address: 'https://outside.example',
    ),
  ],
);

class _Fixture {
  _Fixture({this.failure = IdentityFailureCode.network, this.signInSupported});
  final IdentityFailureCode? failure;
  final bool? signInSupported;
  final app = _App(), store = _DavStore();
  final loginHistory = _Credentials();
  final credentials = <String, _Credentials>{};
  final gateways = <String, _Gateway>{};
  final attempted = <String>[];
  bool disposed = false;
  late final dav = WebDavSettingsController(
    store: store,
    connectionTester: _Check(),
  );
  late AccountService account = create();
  AccountService create() => AccountService(
    controller: app,
    signInSupported: signInSupported,
    webDav: dav,
    savedLoginStorage: loginHistory,
    credentialStore: (scope) =>
        credentials.putIfAbsent(scope, _Credentials.new),
    switchScope: (_) async {},
    gatewayFactory: (config) async => gateways.putIfAbsent(
      config.nasOrigin.host,
      () =>
          _Gateway(config.nasOrigin.host == 'inside.example' ? failure : null),
    ),
  );
  Future<void> start() async {
    await dav.load();
    await account.saveConfiguration(_config());
    expect(account.error, isNull);
  }

  Future<void> login() async {
    await account.signIn(account: 'fixture', password: 'synthetic-secret');
  }

  void dispose() {
    if (disposed) return;
    disposed = true;
    account.dispose();
    dav.dispose();
    app.dispose();
    for (final g in gateways.values) {
      unawaited(g.events.close());
    }
  }
}

class _Journal implements ConfigurationTransferJournal {
  Map<String, dynamic>? value;
  bool failCommit = false;
  @override
  Future<Map<String, dynamic>?> read() async => value;
  @override
  Future<void> clear() async {
    value = null;
  }

  @override
  Future<void> write(Map<String, dynamic> next) async {
    if (failCommit && next['committed'] == true) {
      failCommit = false;
      throw StateError('synthetic failure');
    }
    value = next;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Noto Sans SC',
    )..addFont(rootBundle.load('assets/fonts/NotoSansSC-Variable.ttf'))).load();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'login form saves password, refills after logout and forgets on opt-out at $width',
      (tester) async {
        final f = (await tester.runAsync(() async {
          final fixture = _Fixture();
          await fixture.start();
          await fixture.account.loadSavedLogins();
          return fixture;
        }))!;
        addTearDown(f.dispose);
        await tester.binding.setSurfaceSize(Size(width, 1100));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          AccountScope(
            service: f.account,
            child: MaterialApp(
              theme: AppTheme.buildTheme(PaletteRegistry.classic),
              home: const AccountScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        Finder control(String key) => find.byKey(ValueKey(key));
        TextFormField input(String key) => tester.widget(control(key));
        Future<void> press(String key) async {
          await tester.ensureVisible(control(key));
          await tester.runAsync(() async {
            await tester.tap(control(key));
            await Future<void>.delayed(const Duration(milliseconds: 20));
            for (var i = 0; i < 100 && f.account.isBusy; i++) {
              await Future<void>.delayed(const Duration(milliseconds: 10));
            }
          });
          await tester.pumpAndSettle();
        }

        expect(
          tester
              .widget<CheckboxListTile>(control('account-save-password'))
              .value,
          isFalse,
        );
        await tester.enterText(control('account-username'), 'reader');
        await tester.enterText(control('account-password'), 'fixture-password');
        await press('account-save-password');
        await press('account-sign-in');
        expect(f.account.isSignedIn, isTrue);
        expect(f.account.savedLogins.single.password, 'fixture-password');
        await press('account-sign-out');
        expect(f.account.isSignedIn, isFalse);
        expect(f.account.resourceCredentialsReady, isFalse);
        expect(input('account-username').controller!.text, 'reader');
        expect(input('account-password').controller!.text, 'fixture-password');

        await press('account-save-password');
        await press('account-sign-in');
        expect(f.account.isSignedIn, isTrue);
        expect(f.account.savedLogins.single.hasPassword, isFalse);
        await press('account-sign-out');
        expect(input('account-username').controller!.text, 'reader');
        expect(input('account-password').controller!.text, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets(
      'saved password autofill, account selection and removal at $width',
      (tester) async {
        final f = _Fixture();
        addTearDown(f.dispose);
        await tester.runAsync(() async {
          await f.start();
          await f.account.signIn(
            account: 'first',
            password: 'first-secret',
            savePassword: true,
          );
          await f.account.signOut();
          await f.account.signIn(
            account: 'second',
            password: 'second-secret',
            savePassword: true,
          );
          await f.account.signOut();
        });
        await tester.binding.setSurfaceSize(Size(width, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          AccountScope(
            service: f.account,
            child: MaterialApp(
              theme: AppTheme.buildTheme(PaletteRegistry.classic),
              home: const AccountScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        TextFormField input(String key) =>
            tester.widget<TextFormField>(find.byKey(ValueKey(key)));
        expect(input('account-username').controller!.text, 'second');
        expect(input('account-password').controller!.text, 'second-secret');
        expect(
          tester
              .widget<EditableText>(
                find.descendant(
                  of: find.byKey(const ValueKey('account-password')),
                  matching: find.byType(EditableText),
                ),
              )
              .obscureText,
          isTrue,
        );
        expect(
          tester
              .widget<CheckboxListTile>(
                find.byKey(const ValueKey('account-save-password')),
              )
              .value,
          isTrue,
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('account-saved-logins')),
        );
        await tester.tap(find.byKey(const ValueKey('account-saved-logins')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('first'));
        await tester.pumpAndSettle();
        expect(input('account-password').controller!.text, 'first-secret');
        await tester.tap(find.byKey(const ValueKey('account-forget-login')));
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pumpAndSettle();
        expect(f.account.savedLogins.map((e) => e.username), ['second']);
        expect(input('account-password').controller!.text, isEmpty);
        await tester.enterText(
          find.byKey(const ValueKey('account-username')),
          'new-reader',
        );
        await tester.binding.setSurfaceSize(const Size(640, 1000));
        await tester.pumpAndSettle();
        expect(input('account-username').controller!.text, 'new-reader');
        expect(tester.takeException(), isNull);
      },
    );
  }
  test('old guest credentials never restore without account login', () async {
    final f = _Fixture();
    addTearDown(f.dispose);
    final old = _Credentials()
      ..value = jsonEncode({
        'version': 1,
        'environment': _config().environmentId,
        'username': 'reader',
        'password': 'reader-secret',
      });
    f.credentials['guest_${_config().environmentId}'] = old;
    await f.start();
    expect(f.account.resourceCredentialsReady, isFalse);
    expect(f.dav.saved.password, isEmpty);
    f.account.dispose();
    f.account = f.create();
    await f.account.initialize();
    expect(f.account.resourceCredentialsReady, isFalse);
    expect(f.dav.saved.username, isEmpty);
    await f.login();
    expect(f.account.resourceCredentialsReady, isTrue);
    expect(f.dav.saved.username, 'fixture');
    await f.account.signOut();
    expect(f.account.resourceCredentialsReady, isFalse);
    expect(f.dav.saved.password, isEmpty);
    expect(
      f.account
          .settingsForResource(_config().activeServer.webDavRoot('friend'))
          .password,
      isEmpty,
    );
  });
  test(
    'Web without sign-in cannot restore standalone resource credentials',
    () async {
      final f = _Fixture(signInSupported: false);
      addTearDown(f.dispose);
      f.store.value = const WebDavSettings(
        username: 'reader',
        password: 'reader-secret',
      );
      await f.start();
      expect(f.account.resourceCredentialsReady, isFalse);
      expect(f.dav.saved.username, isEmpty);
      expect(f.gateways, isEmpty);
    },
  );
  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'signed-in NAS address is read-only and WebDAV remains editable at $width',
      (tester) async {
        final f = _Fixture();
        addTearDown(f.dispose);
        await tester.runAsync(() async {
          await f.start();
          await f.login();
        });
        await tester.binding.setSurfaceSize(Size(width, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          AccountScope(
            service: f.account,
            child: MaterialApp(
              theme: AppTheme.buildTheme(PaletteRegistry.classic),
              home: const AccountScreen(showConnections: true),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final server in f.account.configuration!.servers) {
          final address = tester.widget<TextField>(
            find.descendant(
              of: find.byKey(ValueKey('nas-address-${server.id}')),
              matching: find.byType(TextField),
            ),
          );
          expect(address.enabled, isTrue);
          expect(address.readOnly, isTrue);
          expect(address.controller!.text, server.address);
          final davPort = tester.widget<TextField>(
            find.descendant(
              of: find.byKey(ValueKey('nas-dav-port-${server.id}')),
              matching: find.byType(TextField),
            ),
          );
          expect(davPort.enabled, isTrue);
          expect(davPort.readOnly, isFalse);
        }
        final port = find.byKey(const ValueKey('nas-dav-port-outside'));
        await tester.ensureVisible(port);
        await tester.enterText(port, '5443');
        final folder = find.byKey(const ValueKey('nas-resource-folder'));
        await tester.ensureVisible(folder);
        await tester.enterText(folder, 'friend/rules');
        final save = find.byKey(const ValueKey('nas-connections-save'));
        await tester.ensureVisible(save);
        await tester.tap(save);
        for (var attempt = 0; attempt < 100 && f.account.isBusy; attempt++) {
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
        }
        await tester.pumpAndSettle();
        expect(f.account.isSignedIn, isTrue);
        expect(f.account.configuration!.storageFolder, 'friend/rules');
        expect(
          f.account.configuration!.servers
              .firstWhere((server) => server.id == 'outside')
              .webDavPort,
          5443,
        );
        expect(
          f.dav.saved.baseUrl,
          'https://outside.example:5443/friend/rules/',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        f.dispose();
        await tester.pump();
      },
    );
  }
  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets('signed-out resource controls require login at $width', (
      tester,
    ) async {
      final f = _Fixture();
      addTearDown(f.dispose);
      await tester.runAsync(f.start);
      await tester.binding.setSurfaceSize(Size(width, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        AccountScope(
          service: f.account,
          child: MaterialApp(
            theme: AppTheme.buildTheme(PaletteRegistry.warmwoodStudy),
            home: const AccountScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(
          ValueKey(
            width >= 1000 ? 'account-wide-layout' : 'account-compact-layout',
          ),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('account-guest-webdav')), findsNothing);
      expect(
        find.byKey(const ValueKey('account-webdav-username')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('account-webdav-password')),
        findsNothing,
      );
      expect(find.text('Sign in to use the knowledge library'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('account-check-resources')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('resource-access-refresh')),
        findsNothing,
      );
      expect(f.account.resourceCredentialsReady, isFalse);
      expect(f.dav.saved.password, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      f.dispose();
      await tester.pump();
    });
  }
  test(
    'brief revalidation timeout keeps the cached account usable offline',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      await f.start();
      await f.account.signIn(
        account: 'fixture',
        password: 'synthetic-secret',
        serverId: 'outside',
      );
      final gateway = f.gateways['outside.example']!;
      gateway.verification = Completer<IdentityUser?>();
      await f.account.restore();
      expect(f.account.isSignedIn, isTrue);
      expect(f.account.isOffline, isTrue);
      expect(f.account.isBusy, isFalse);
      expect(f.account.dataScopeReady, isTrue);
      gateway.verification!.complete(null);
      await Future<void>.delayed(Duration.zero);
      expect(f.account.isSignedIn, isTrue);
    },
  );
  testWidgets(
    'login displays configured URLs, selects one and validates custom input',
    (tester) async {
      final f = _Fixture(failure: null);
      addTearDown(f.dispose);
      await tester.runAsync(f.start);
      await tester.binding.setSurfaceSize(const Size(390, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        AccountScope(
          service: f.account,
          child: MaterialApp(
            theme: AppTheme.buildTheme(PaletteRegistry.classic),
            home: const AccountScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final picker = find.byType(DropdownButtonFormField<String>);
      expect(find.text('https://outside.example:5001'), findsOneWidget);
      await tester.tap(picker);
      await tester.pumpAndSettle();
      expect(find.text('https://inside.example:5001'), findsWidgets);
      await tester.tap(find.text('Custom address').last);
      await tester.pumpAndSettle();
      final custom = find.byKey(const ValueKey('account-custom-server'));
      expect(custom, findsOneWidget);
      await tester.enterText(custom, 'http://bad.example/friend');
      await tester.enterText(
        find.byKey(const ValueKey('account-username')),
        'fixture',
      );
      await tester.enterText(
        find.byKey(const ValueKey('account-password')),
        'synthetic-secret',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('account-sign-in')));
      await tester.tap(find.byKey(const ValueKey('account-sign-in')));
      await tester.pumpAndSettle();
      expect(find.text('Enter an HTTPS sign-in URL'), findsOneWidget);
      expect(f.gateways.values.every((g) => g.calls == 0), isTrue);
      await tester.ensureVisible(picker);
      await tester.tap(picker);
      await tester.pumpAndSettle();
      await tester.tap(find.text('https://inside.example:5001').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('account-sign-in')));
      await tester.tap(find.byKey(const ValueKey('account-sign-in')));
      for (var attempt = 0; attempt < 40; attempt++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        if (f.account.isSignedIn && !f.account.isBusy) break;
      }
      expect(f.account.isBusy, isFalse, reason: f.account.error);
      await tester.pumpAndSettle();
      expect(f.account.isSignedIn, isTrue);
      expect(f.gateways['inside.example']!.calls, 1);
      expect(f.gateways['outside.example']?.calls ?? 0, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      f.dispose();
    },
  );
  test('cancelled custom OTP restores the previous server choices', () async {
    final f = _Fixture();
    addTearDown(f.dispose);
    await f.start();
    f.gateways['custom.example'] = _Gateway(IdentityFailureCode.otpRequired);
    await f.account.signIn(
      account: 'fixture',
      password: 'synthetic-secret',
      customOrigin: Uri.parse('https://custom.example:5001'),
    );
    expect(f.account.needsOtp, isTrue);
    await f.account.cancelSignIn();
    expect(f.account.needsOtp, isFalse);
    expect(f.account.configuration!.servers.map((s) => s.id), [
      'inside',
      'outside',
    ]);
    expect(f.account.isSignedIn, isFalse);
  });
  test(
    'v3 migration separates ports/folder and preserves account scope across aliases',
    () {
      final previous = AccountConfiguration.fromJson({
        'version': 3,
        'authType': 'synology-direct',
        'nasUrl': 'https://cznas.dpdns.org:5001',
      });
      final next = AccountConfiguration.fromResources(
        sources: AssetSourceConfig.defaults,
        previous: previous,
      );
      expect(next.servers, hasLength(2));
      expect(next.servers.first.address, 'https://192.168.1.55');
      expect(next.servers.last.webDavPort, 5006);
      expect(next.servers.last.loginPort, 5001);
      expect(next.storageFolder, 'friend');
      expect(next.environmentId, previous.environmentId);
      expect(
        next.withServer(next.servers.first.id).accountScope('verified'),
        previous.accountScope('verified'),
      );
      final roundtrip = AccountConfiguration.fromJson(
        jsonDecode(jsonEncode(next.toJson())) as Map<String, dynamic>,
      );
      expect(roundtrip.toJson(), next.toJson());
    },
  );
  test(
    'connections reject credentials, paths, HTTP, traversal and invalid ports',
    () {
      for (final input in [
        'http://nas.example',
        'https://a:b@nas.example',
        'https://nas.example/friend',
        'https://nas.example:5006',
      ]) {
        expect(
          () => NasServerAddress(id: 'one', name: 'NAS', address: input),
          throwsFormatException,
        );
      }
      for (final folder in [
        '../friend',
        'friend/../private',
        '/',
        'friend//sub',
        'friend?query',
      ]) {
        expect(
          () => AccountConfiguration.normalizeFolder(folder),
          throwsFormatException,
        );
      }
      expect(
        AccountConfiguration.normalizeFolder('/friend/rules/'),
        'friend/rules',
      );
      expect(
        () => NasServerAddress(
          id: 'one',
          name: 'NAS',
          address: 'nas.example',
          loginPort: 65536,
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'network failure tries next address and shares verified login credentials with both roots',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      await f.start();
      await f.login();
      expect(f.gateways['inside.example']?.calls, 1);
      expect(f.gateways['outside.example']?.calls, 1);
      expect(f.account.isSignedIn, isTrue);
      expect(f.account.resourceCredentialsReady, isTrue);
      expect(f.dav.saved.username, 'fixture');
      expect(f.dav.saved.password, 'synthetic-secret');
      for (final server in f.account.configuration!.servers) {
        expect(
          f.account
              .settingsForResource(
                server.webDavRoot('friend').resolve('apps/catalog.json'),
              )
              .password,
          'synthetic-secret',
        );
      }
      for (final uri in [
        'https://outside.example:5006/friends/file',
        'https://outside.example:5006/other/file',
        'https://evil.example:5006/friend/file',
      ]) {
        expect(f.account.settingsForResource(Uri.parse(uri)).password, isEmpty);
      }
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys()) {
        expect(prefs.get(key).toString(), isNot(contains('synthetic-secret')));
      }
    },
  );
  for (final failure in [
    IdentityFailureCode.invalidCredentials,
    IdentityFailureCode.otpRequired,
    IdentityFailureCode.rateLimited,
    IdentityFailureCode.accountDenied,
  ]) {
    test(
      'does not retry account denial or challenges on another address: ${failure.name}',
      () async {
        final f = _Fixture(failure: failure);
        addTearDown(f.dispose);
        await f.start();
        await f.login();
        expect(f.gateways['inside.example']?.calls, 1);
        expect(f.gateways['outside.example']?.calls ?? 0, 0);
        expect(f.account.isSignedIn, isFalse);
        expect(f.credentials.values.every((c) => c.value == null), isTrue);
        if (failure == IdentityFailureCode.otpRequired) {
          await f.account.signIn(
            account: 'fixture',
            password: 'synthetic-secret',
            otp: '123456',
          );
          expect(f.gateways['inside.example']?.calls, 2);
          expect(f.account.isSignedIn, isTrue);
        }
      },
    );
  }
  test(
    'restart restores credentials and logout clears caches without affecting other accounts',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      await f.start();
      await f.login();
      final scope = f.account.configuration!.accountScope(f.account.user!.id);
      f.account.dispose();
      f.account = f.create();
      await f.account.initialize();
      expect(f.account.resourceCredentialsReady, isTrue);
      expect(f.account.configuration!.nasOrigin.host, 'outside.example');
      await f.account.signOut();
      expect(f.credentials[scope]!.value, isNull);
      expect(f.dav.saved.password, isEmpty);
      expect(f.account.resourceCredentialsReady, isFalse);
      await f.account.signIn(
        account: 'other',
        password: 'other-synthetic-secret',
      );
      expect(f.account.user!.id, 'other-verified-uid');
      expect(f.dav.saved.username, 'other');
      expect(f.credentials[scope]!.value, isNull);
    },
  );
  test('explicit selection authenticates only the chosen entrance', () async {
    final f = _Fixture();
    addTearDown(f.dispose);
    await f.start();
    await f.account.signIn(
      account: 'fixture',
      password: 'synthetic-secret',
      serverId: 'outside',
    );
    expect(f.account.isSignedIn, isTrue);
    expect(f.gateways['inside.example']?.calls ?? 0, 0);
    expect(f.gateways['outside.example']!.calls, 1);
  });
  test(
    'custom gateway initialization failure leaves original resource addresses intact',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      f.account.dispose();
      f.account = AccountService(
        controller: f.app,
        webDav: f.dav,
        switchScope: (_) async {},
        credentialStore: (scope) =>
            f.credentials.putIfAbsent(scope, _Credentials.new),
        gatewayFactory: (config) async {
          if (config.nasOrigin.host == 'broken.example') {
            throw const IdentityFailure(IdentityFailureCode.storage);
          }
          return f.gateways.putIfAbsent(
            config.nasOrigin.host,
            () => _Gateway(null),
          );
        },
      );
      await f.start();
      final original = f.account.configuration!.toJson();
      final roots = f.app.assetSourceConfigs.map((s) => s.testUrl).toList();
      await f.account.signIn(
        account: 'fixture',
        password: 'synthetic-secret',
        customOrigin: Uri.parse('https://broken.example:5001'),
      );
      expect(f.account.isSignedIn, isFalse);
      expect(f.account.isBusy, isFalse);
      expect(f.account.configuration!.toJson(), original);
      expect(f.app.assetSourceConfigs.map((s) => s.testUrl), roots);
    },
  );
  test(
    'optional cloud setup failure does not block the signed-in account',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      f.account.dispose();
      f.account = AccountService(
        controller: f.app,
        webDav: f.dav,
        switchScope: (_) async {},
        credentialStore: (scope) =>
            f.credentials.putIfAbsent(scope, _Credentials.new),
        gatewayFactory: (config) async =>
            f.gateways.putIfAbsent(config.nasOrigin.host, () => _Gateway(null)),
        privateFilesFactory: (_) => throw StateError('synthetic cloud failure'),
      );
      await f.start();
      await f.account.signIn(
        account: 'fixture',
        password: 'synthetic-secret',
        serverId: 'outside',
      );
      await Future<void>.delayed(Duration.zero);
      expect(f.account.isSignedIn, isTrue);
      expect(f.account.dataScopeReady, isTrue);
      expect(f.account.isBusy, isFalse);
      expect(f.account.error, contains('已登录，云同步暂不可用'));
      expect(f.account.resourceCredentialsReady, isTrue);
    },
  );
  test(
    'custom origin isolates its credentials and does not forward them to old entrances',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      await f.start();
      final previousScope = f.account.configuration!.accountScope(
        'verified-uid',
      );
      await f.account.signIn(
        account: 'fixture',
        password: 'synthetic-secret',
        customOrigin: Uri.parse('https://custom.example:5001'),
      );
      expect(f.account.isSignedIn, isTrue);
      expect(f.account.configuration!.servers, hasLength(1));
      expect(f.account.configuration!.nasOrigin.host, 'custom.example');
      expect(
        f.account.configuration!.accountScope('verified-uid'),
        isNot(previousScope),
      );
      expect(
        f.account
            .settingsForResource(
              Uri.parse('https://outside.example:5006/friend/a'),
            )
            .password,
        isEmpty,
      );
      expect(f.dav.saved.baseUrl, 'https://custom.example:5006/friend/');
    },
  );
  test(
    'failed custom login restores the previous connections without saving the new host',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      await f.start();
      f.gateways['broken.example'] = _Gateway(
        IdentityFailureCode.invalidCredentials,
      );
      final original = f.account.configuration!.toJson();
      await f.account.signIn(
        account: 'fixture',
        password: 'synthetic-secret',
        customOrigin: Uri.parse('https://broken.example:5001'),
      );
      expect(f.account.isSignedIn, isFalse);
      expect(f.account.isBusy, isFalse);
      expect(f.account.configuration!.toJson(), original);
      expect(f.account.error, '账号或密码不正确');
    },
  );
  test(
    'resource credential persistence failure does not revoke successful authentication',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      await f.start();
      f.credentials[f.account.configuration!.accountScope(
        'verified-uid',
      )] = _Credentials()
        ..fail = true;
      await f.account.signIn(
        account: 'fixture',
        password: 'synthetic-secret',
        serverId: 'outside',
      );
      expect(f.account.isSignedIn, isTrue);
      expect(f.account.dataScopeReady, isTrue);
      expect(f.account.isBusy, isFalse);
      expect(f.account.resourceCredentialsReady, isFalse);
      expect(f.account.error, contains('已登录，资料凭据保存失败'));
    },
  );
  test(
    'upgrade adopts legacy credentials only for the restored user and configured root',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      await f.start();
      await f.login();
      final scope = f.account.configuration!.accountScope(f.account.user!.id);
      f.credentials[scope]!.value = null;
      f.account.dispose();
      f.account = f.create();
      await f.account.initialize();
      expect(f.account.resourceCredentialsReady, isTrue);
      expect(f.dav.saved.username, 'fixture');

      f.credentials[scope]!.value = null;
      await f.dav.saveConfiguration(
        f.dav.saved.copyWith(username: 'another-user'),
      );
      f.account.dispose();
      f.account = f.create();
      await f.account.initialize();
      expect(f.account.resourceCredentialsReady, isFalse);
      expect(f.credentials[scope]!.value, isNull);
      expect(f.dav.saved.password, isEmpty);
    },
  );
  test(
    'reordering/folder changes retain identity; address changes require sign-out',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      await f.start();
      await f.login();
      final current = f.account.configuration!;
      final user = f.account.user!.id;
      await f.account.saveConfiguration(
        current.edited(
          servers: current.servers.reversed.toList(),
          folder: 'friend/rules',
        ),
      );
      expect(
        f.account.configuration!.accountScope(user),
        current.accountScope(user),
      );
      expect(f.app.sources.first.id, 'outside');
      expect(f.dav.saved.baseUrl, 'https://outside.example:5006/friend/rules/');
      final changed = current.edited(
        servers: [
          NasServerAddress(
            id: 'changed',
            name: 'Other NAS',
            address: 'https://new.example',
          ),
        ],
        folder: 'friend',
      );
      await expectLater(f.account.saveConfiguration(changed), throwsStateError);
    },
  );
  test(
    'late cancelled login does not persist WebDAV credentials or try another address',
    () async {
      final f = _Fixture(failure: null);
      addTearDown(f.dispose);
      await f.start();
      f.gateways['inside.example'] = _Gateway(null)
        ..pending = Completer<void>();
      final login = f.login();
      for (
        var i = 0;
        i < 100 && f.gateways['inside.example']!.calls == 0;
        i++
      ) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(f.gateways['inside.example']!.calls, 1);
      await f.account.cancelSignIn();
      f.gateways['inside.example']!.pending!.complete();
      await login;
      expect(f.account.isSignedIn, isFalse);
      expect(f.dav.saved.password, isEmpty);
      expect(f.credentials.values.every((c) => c.value == null), isTrue);
      expect(f.gateways['outside.example']?.calls ?? 0, 0);
    },
  );
  test(
    'combined import preserves two entrances, ignores imported credentials and rolls back failures',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      await f.start();
      await f.login();
      final original = f.account.configuration!;
      final next = original.edited(
        servers: original.servers.reversed.toList(),
        folder: 'friend/rules',
      );
      final journal = _Journal();
      final transfer = SettingsTransferService(
        controller: f.app,
        webDav: f.dav,
        account: f.account,
        journal: journal,
      );
      final payload = ConfigurationTransfer.payload(
        f.app.aiApiConfig,
        f.dav.saved,
        ConfigurationScope.webDav,
      );
      payload['webdav'] = {
        'baseUrl': f.dav.saved.baseUrl,
        'connections': jsonEncode(next.toJson()),
      };
      final parsed = ConfigurationTransfer.parse(
        ConfigurationTransfer.encode(payload),
      );
      expect(parsed.unassigned, isEmpty);
      final restored = AccountConfiguration.fromJson(
        jsonDecode(parsed.webDav['connections']!) as Map<String, dynamic>,
      );
      expect(restored.servers, hasLength(2));
      final injected = WebDavSettings(
        baseUrl: f.dav.saved.baseUrl,
        username: 'unverified',
        password: 'unverified-secret',
      );
      journal.failCommit = true;
      await expectLater(
        transfer.apply(dav: injected, connections: restored),
        throwsA(isA<ConfigurationTransferException>()),
      );
      expect(f.account.configuration!.toJson(), original.toJson());
      expect(f.dav.saved.username, 'fixture');
      expect(f.dav.saved.password, 'synthetic-secret');
      expect(journal.value, isNull);
      await transfer.apply(dav: injected, connections: restored);
      expect(f.account.configuration!.servers.first.id, 'outside');
      expect(f.account.configuration!.storageFolder, 'friend/rules');
      expect(f.dav.saved.username, 'fixture');
      expect(f.dav.saved.password, 'synthetic-secret');
      expect(
        BoardGameRemoteLayout.normalizeSettings(f.dav.saved).baseUrl,
        'https://outside.example:5006/friend/rules/',
      );
    },
  );
  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets(
      'shared connection editor fits $width and has only sign-in credential fields',
      (tester) async {
        final f = _Fixture();
        addTearDown(f.dispose);
        await tester.runAsync(f.start);
        await tester.binding.setSurfaceSize(Size(width, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          AccountScope(
            service: f.account,
            child: MaterialApp(
              theme: AppTheme.buildTheme(PaletteRegistry.classic),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.5)),
                child: child!,
              ),
              home: const AccountScreen(showConnections: true),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('nas-resource-folder')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('resource-connection-password')),
          findsNothing,
        );
        expect(find.byKey(const ValueKey('account-password')), findsOneWidget);
        await tester.ensureVisible(
          find.byKey(const ValueKey('nas-connections-save')),
        );
        expect(tester.takeException(), isNull);
        await tester.enterText(
          find.byKey(const ValueKey('nas-resource-folder')),
          '../bad',
        );
        await tester.tap(find.byKey(const ValueKey('nas-connections-save')));
        await tester.pumpAndSettle();
        expect(f.account.configuration!.storageFolder, 'friend');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
