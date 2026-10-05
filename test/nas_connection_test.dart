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
  Future<IdentityUser?> verifyCurrentUser() async => current;
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
  _Fixture({this.failure = IdentityFailureCode.network});
  final IdentityFailureCode? failure;
  final app = _App(), store = _DavStore();
  final credentials = <String, _Credentials>{};
  final gateways = <String, _Gateway>{};
  final attempted = <String>[];
  late final dav = WebDavSettingsController(
    store: store,
    connectionTester: _Check(),
  );
  late AccountService account = create();
  AccountService create() => AccountService(
    controller: app,
    webDav: dav,
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
