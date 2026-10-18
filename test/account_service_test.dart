import 'dart:async';
import 'dart:convert';
import 'package:app_identity/app_identity.dart';
import 'package:board_game_agent/app/state/app_controller.dart';
import 'package:board_game_agent/features/identity/models/account_configuration.dart';
import 'package:board_game_agent/features/identity/services/account_service.dart';
import 'package:board_game_agent/features/identity/services/web_account_gateway.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

AccountConfiguration configuration([String host = 'app.example.test']) =>
    AccountConfiguration.fromFields(nasUrl: 'https://$host');
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'cold native login allows three valid DSM requests beyond three seconds',
    (tester) async {
      final app = FixtureApp();
      final config = configuration();
      final methods = <String>[];
      final session = MemoryStorage();
      final service = AccountService(
        controller: app,
        savedLoginStorage: MemoryStorage(),
        switchScope: (scope) async {
          if (scope != null) {
            // Keep this authentication regression independent of cloud sync.
            await (await SharedPreferences.getInstance()).setBool(
              'account_cloud_enabled.$scope',
              false,
            );
          }
        },
        gatewayFactory: (config) async {
          final gateway = SynologyIdentityGateway(
            origin: config.nasOrigin,
            environment: config.environmentId,
            storage: session,
            client: MockClient((request) async {
              final fields = request.method == 'GET'
                  ? request.url.queryParameters
                  : Uri.splitQueryString(request.body);
              final method = fields['method']!;
              methods.add(method);
              if (method != 'logout') {
                await Future<void>.delayed(const Duration(milliseconds: 1100));
              }
              return http.Response(
                jsonEncode({
                  'success': true,
                  'data': switch (method) {
                    'query' => {
                      'SYNO.API.Auth': {
                        'path': 'auth.cgi',
                        'minVersion': 1,
                        'maxVersion': 6,
                      },
                      'SYNO.FileStation.Info': {
                        'path': 'entry.cgi',
                        'minVersion': 1,
                        'maxVersion': 2,
                      },
                    },
                    'login' => {'sid': 'fixture-sid'},
                    'get' => {'uid': 101},
                    'logout' => <String, dynamic>{},
                    _ => throw StateError('Unexpected DSM method'),
                  },
                }),
                200,
              );
            }),
          );
          await gateway.initialize();
          return gateway;
        },
      );
      addTearDown(app.dispose);
      try {
        await service.saveConfiguration(config);
        expect(
          methods,
          isEmpty,
          reason: 'Signed-out startup has no DSM session',
        );
        final attempt = service.signIn(
          account: 'reader',
          password: 'fixture-password',
          serverId: config.activeServer.id,
        );
        await tester.pump();
        for (var i = 0; i < 2; i++) {
          await tester.pump(const Duration(milliseconds: 1100));
          expect(service.isBusy, isTrue);
          expect(service.isSignedIn, isFalse);
          expect(session.value, isNull);
        }
        await tester.pump(const Duration(milliseconds: 1100));
        await attempt;
        expect(service.error, isNull);
        expect(service.isSignedIn, isTrue);
        expect(service.isBusy, isFalse);
        expect(session.value, isNotNull);
        expect(methods, ['query', 'login', 'get']);

        await service.signOut();
        final retry = service.signIn(
          account: 'reader',
          password: 'fixture-password',
          serverId: config.activeServer.id,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1100));
        await tester.pump(const Duration(milliseconds: 1100));
        await retry;
        expect(service.error, isNull);
        expect(service.isSignedIn, isTrue);
        expect(methods, ['query', 'login', 'get', 'logout', 'login', 'get']);
      } finally {
        service.dispose();
        await tester.pump();
      }
    },
  );
  testWidgets('native sign-in deadline rejects a late response', (
    tester,
  ) async {
    final app = FixtureApp();
    final gateway = FixtureGateway()..pending = Completer<IdentityUser>();
    final service = AccountService(
      controller: app,
      gatewayFactory: (_) async => gateway,
      switchScope: (_) async {},
    );
    addTearDown(app.dispose);
    final config = configuration();
    try {
      await service.saveConfiguration(config);
      final attempt = service.signIn(
        account: 'reader',
        password: 'fixture-password',
        serverId: config.activeServer.id,
      );
      await tester.pump();
      await tester.pump(AccountService.authenticationTimeout);
      await attempt;
      expect(service.isBusy, isFalse);
      expect(service.isSignedIn, isFalse);
      expect(service.error, '请求超时，请重试');
      gateway.pending!.complete(const IdentityUser(id: 'late'));
      await tester.pump();
      expect(service.isSignedIn, isFalse);
    } finally {
      service.dispose();
      await tester.pump();
    }
  });
  test(
    'Web comments switch between guest read-only and verified UID without reusing old service',
    () async {
      final app = FixtureApp();
      final id = 'a' * 64;
      var signed = false;
      final gateway = WebAccountGateway(
        site: Uri.parse('https://games.example'),
        client: MockClient((request) async {
          if (request.url.path.endsWith('/login')) signed = true;
          if (request.url.path.endsWith('/logout')) signed = false;
          return http.Response(
            jsonEncode({
              'user': signed
                  ? {'id': id, 'displayName': 'Shane', 'uid': 101}
                  : null,
            }),
            200,
          );
        }),
      );
      final service = AccountService(
        controller: app,
        browserAccounts: true,
        webConfigurationLoader: () async => configuration(),
        gatewayFactory: (_) async => gateway,
        switchScope: (_) async {},
      );
      addTearDown(service.dispose);
      addTearDown(app.dispose);
      await service.initialize();
      final guest = service.comments!;
      expect(guest.readOnly, isTrue);
      expect(guest.uid, 0);
      await service.signIn(account: 'Shane', password: 'fixture');
      expect(service.error, isNull);
      final own = service.comments!;
      expect(identical(guest, own), isFalse);
      expect(own.canWrite, isTrue);
      expect(own.uid, 101);
      expect(service.cloud, isNotNull);
      expect(guest.canWrite, isFalse);
      await service.signOut();
      final nextGuest = service.comments!;
      expect(nextGuest.readOnly, isTrue);
      expect(nextGuest.uid, 0);
      expect(own.canWrite, isFalse);
      expect(identical(nextGuest, own), isFalse);
    },
  );
  test(
    'Web stays guest and never creates a native gateway or prompts for credentials',
    () async {
      final app = FixtureApp();
      var constructed = false;
      final service = AccountService(
        controller: app,
        signInSupported: false,
        gatewayFactory: (_) async {
          constructed = true;
          return FixtureGateway();
        },
      );
      await service.initialize();
      expect(service.isConfigured, isTrue);
      await service.signIn(account: 'User', password: 'fixture');
      expect(constructed, isFalse);
      expect(service.user, isNull);
      expect(service.error, contains('网页版暂不支持'));
      service.dispose();
      app.dispose();
    },
  );
  test('connection metadata roundtrip and NAS/user scopes remain isolated', () {
    final config = configuration();
    expect(
      AccountConfiguration.fromJson(config.toJson()).environmentId,
      config.environmentId,
    );
    expect(config.accountScope('first'), isNot(config.accountScope('second')));
    expect(
      configuration('other.example.test').accountScope('first'),
      isNot(config.accountScope('first')),
    );
    expect(
      () => AccountConfiguration.fromFields(nasUrl: 'http://app.example.test'),
      throwsFormatException,
    );
    expect(
      () => AccountConfiguration.fromFields(
        nasUrl: 'https://user:password@app.example.test',
      ),
      throwsFormatException,
    );
    expect(
      () => AccountConfiguration.fromJson({
        'version': 1,
        'supabaseUrl': 'https://old.example.test',
      }),
      throwsFormatException,
    );
  });
  test(
    'old Supabase settings are retained but cannot configure or authenticate the new provider',
    () async {
      SharedPreferences.setMockInitialValues({
        'board_game_agent.identity.configuration.v1':
            '{"supabaseUrl":"https://old.example.test"}',
      });
      final app = FixtureApp();
      final service = AccountService(
        controller: app,
        gatewayFactory: (_) async => FixtureGateway(),
        switchScope: (_) async {},
      );
      await service.initialize();
      expect(service.isConfigured, isTrue);
      expect(
        service.configuration!.nasOrigin.origin,
        'https://cznas.dpdns.org:5001',
      );
      expect(service.user, isNull);
      expect(service.dataScopeReady, isTrue);
      expect(
        (await SharedPreferences.getInstance()).getString(
          'board_game_agent.identity.configuration.v1',
        ),
        isNotNull,
      );
      service.dispose();
      app.dispose();
    },
  );
  test(
    'native default configuration signs in without a bridge or setup form',
    () async {
      final app = FixtureApp(), gateway = FixtureGateway();
      final service = AccountService(
        controller: app,
        gatewayFactory: (_) async => gateway,
        switchScope: (_) async {},
      );
      await service.initialize();
      await service.signIn(account: 'first', password: 'fixture');
      expect(service.error, isNull);
      expect(
        service.configuration!.nasOrigin.origin,
        'https://192.168.1.55:5001',
      );
      expect(service.user?.id, 'first');
      expect(service.dataScopeReady, isTrue, reason: service.error);
      service.dispose();
      app.dispose();
    },
  );
  test(
    'account is covered until previous writes drain and logout restores guest scope',
    () async {
      final app = FixtureApp(), gateway = FixtureGateway();
      final drain = Completer<void>(), scopes = <String?>[];
      final service = AccountService(
        controller: app,
        gatewayFactory: (_) async => gateway,
        switchScope: (scope) {
          scopes.add(scope);
          return drain.future;
        },
      );
      await service.saveConfiguration(configuration());
      final attempt = service.signIn(account: 'first', password: 'fixture');
      await Future<void>.delayed(Duration.zero);
      expect(service.user?.id, 'first');
      expect(service.dataScopeReady, isFalse);
      drain.complete();
      await attempt;
      expect(service.dataScopeReady, isTrue);
      expect(scopes, [configuration().accountScope('first')]);
      await service.signOut();
      expect(scopes.last, isNull);
      expect(service.nicknameKey, 'mobile_profile_nickname');
      service.dispose();
      app.dispose();
    },
  );
  test(
    'failed scope switch stays covered until an explicit retry completes',
    () async {
      final app = FixtureApp(), gateway = FixtureGateway();
      var fail = true;
      final service = AccountService(
        controller: app,
        gatewayFactory: (_) async => gateway,
        switchScope: (_) async {
          if (fail) throw StateError('fixture');
        },
      );
      await service.saveConfiguration(configuration());
      await service.signIn(account: 'first', password: 'fixture');
      expect(service.dataScopeReady, isFalse);
      fail = false;
      await service.restore();
      expect(service.dataScopeReady, isTrue);
      service.dispose();
      app.dispose();
    },
  );
  test(
    'OTP, password rejection and cancellation never publish a candidate identity',
    () async {
      final app = FixtureApp(), gateway = FixtureGateway()..otpRequired = true;
      final service = AccountService(
        controller: app,
        gatewayFactory: (_) async => gateway,
        switchScope: (_) async {},
      );
      await service.saveConfiguration(configuration());
      await service.signIn(account: 'first', password: 'fixture');
      expect(service.needsOtp, isTrue);
      expect(service.user, isNull);
      await service.signIn(
        account: 'first',
        password: 'fixture',
        otp: '123456',
      );
      expect(service.user?.id, 'first');
      await service.signOut();
      gateway.pending = Completer<IdentityUser>();
      final attempt = service.signIn(
        account: 'late',
        password: 'fixture',
        otp: '123456',
      );
      await Future<void>.delayed(Duration.zero);
      await service.cancelSignIn();
      gateway.pending!.complete(const IdentityUser(id: 'late'));
      await attempt;
      expect(service.user, isNull);
      service.dispose();
      app.dispose();
    },
  );
}

class FixtureApp implements AppController {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
  @override
  void dispose() {}
}

class MemoryStorage implements IdentitySessionStorage {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async => value = next;
  @override
  Future<void> delete() async => value = null;
}

class FixtureGateway implements IdentityGateway, IdentityLocalSessionCleanup {
  IdentityUser? current;
  bool otpRequired = false;
  Completer<IdentityUser>? pending;
  @override
  IdentityUser? get cachedUser => current;
  @override
  Stream<IdentityEvent> get changes => const Stream.empty();
  @override
  Future<IdentityUser> signIn({
    required String account,
    required String password,
    String? otp,
  }) async {
    if (otpRequired && otp == null) {
      throw const IdentityFailure(IdentityFailureCode.otpRequired);
    }
    if (pending != null) return pending!.future;
    return current = IdentityUser(id: account, displayName: account);
  }

  @override
  Future<IdentityUser?> verifyCurrentUser() async => current;
  @override
  Future<void> signOut() => clearLocalSession();
  @override
  Future<void> clearLocalSession() async {
    current = null;
  }

  @override
  void cancelRequests() {}
  @override
  Future<void> dispose() async {}
}
