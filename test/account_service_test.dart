import 'dart:async';
import 'dart:convert';
import 'package:app_identity/app_identity.dart';
import 'package:board_game_agent/app/state/app_controller.dart';
import 'package:board_game_agent/features/identity/models/account_configuration.dart';
import 'package:board_game_agent/features/identity/services/account_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

AccountConfiguration configuration([String host = 'app.example.test']) =>
    AccountConfiguration.fromFields(
      serviceUrl: 'https://$host',
      nasId: 'nas_fixture_identity_2026',
    );
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
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
      () => AccountConfiguration.fromFields(
        serviceUrl: 'http://app.example.test',
        nasId: config.nasId,
      ),
      throwsFormatException,
    );
    expect(
      () => AccountConfiguration.fromFields(
        serviceUrl: 'https://user:password@app.example.test',
        nasId: config.nasId,
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
      final service = AccountService(controller: app);
      await service.initialize();
      expect(service.isConfigured, isFalse);
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
    'unconfigured login stays guest and can retry new deployment configuration',
    () async {
      final app = FixtureApp(), gateway = FixtureGateway();
      final service = AccountService(
        controller: app,
        gatewayFactory: (_) async => gateway,
        switchScope: (_) async {},
      );
      await service.initialize();
      await service.signIn(account: 'first', password: 'fixture');
      expect(service.error, '登录服务尚未就绪，请稍后重试');
      expect(service.user, isNull);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'board_game_agent.identity.synology.configuration.v2',
        jsonEncode(configuration().toJson()),
      );
      await service.signIn(account: 'first', password: 'fixture');
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
