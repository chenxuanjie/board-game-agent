import 'dart:async';
import 'dart:convert';

import 'package:app_identity/app_identity.dart';
import 'package:board_game_agent/app/state/app_controller.dart';
import 'package:board_game_agent/features/identity/models/account_configuration.dart';
import 'package:board_game_agent/features/identity/services/account_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

AccountConfiguration configuration([String host = 'project.example.test']) =>
    AccountConfiguration.fromFields(
      supabaseUrl: 'https://$host',
      publishableKey: 'sb_publishable_abcdefghijklmnop',
      webCallback: 'https://app.example.test/auth/callback',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'public configuration roundtrip and project/user scoped identifiers',
    () {
      final first = configuration();
      expect(
        AccountConfiguration.fromJson(first.toJson()).environmentId,
        first.environmentId,
      );
      expect(
        first.accountScope('same-user'),
        isNot(first.accountScope('other')),
      );
      expect(
        configuration('other.example.test').accountScope('same-user'),
        isNot(first.accountScope('same-user')),
      );
      expect(
        first.nativeCallback.toString(),
        'org.dpdns.cznas.boardgame://auth/callback',
      );
    },
  );

  test('rejects management secrets and credential-bearing addresses', () {
    final admin =
        'a.${base64Url.encode(utf8.encode('{"role":"service_role"}'))}.b';
    for (final key in ['sb_secret_private_fixture', admin]) {
      expect(
        () => AccountConfiguration.fromFields(
          supabaseUrl: 'https://project.example.test',
          publishableKey: key,
          webCallback: 'https://app.example.test/auth/callback',
        ),
        throwsFormatException,
      );
    }
    expect(
      () => configuration('user:password@project.example.test'),
      throwsFormatException,
    );
  });

  test('unconfigured startup retains guest access', () async {
    final fixture = _AppFixture();
    final service = AccountService(controller: fixture);
    await service.initialize();
    expect(service.isConfigured, isFalse);
    expect(service.dataScopeReady, isTrue);
    expect(service.nicknameKey, 'mobile_profile_nickname');
    service.dispose();
    fixture.dispose();
  });

  test('login retries deployment configuration without a user form', () async {
    final gateway = _Gateway();
    final fixture = _AppFixture();
    final service = AccountService(
      controller: fixture,
      gatewayFactory: (_) async => gateway,
    );
    await service.initialize();
    expect(service.isConfigured, isFalse);
    await service.signIn();
    expect(service.error, '登录服务尚未就绪，请稍后重试');

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'board_game_agent.identity.configuration.v1',
      jsonEncode(configuration().toJson()),
    );
    await service.signIn();
    expect(service.isConfigured, isTrue);
    expect(service.isAwaitingBrowser, isTrue);
    expect(service.error, isNull);
    service.cancelSignIn();
    await Future<void>.delayed(Duration.zero);
    service.dispose();
    fixture.dispose();
    await gateway.close();
  });

  test(
    'account UI is blocked until old-account writes drain, logout restores guest',
    () async {
      final gateway = _Gateway();
      final drain = Completer<void>();
      final scopes = <String?>[];
      final fixture = _AppFixture();
      final service = AccountService(
        controller: fixture,
        gatewayFactory: (_) async => gateway,
        switchScope: (scope) {
          scopes.add(scope);
          return drain.future;
        },
      );
      await service.saveConfiguration(configuration());
      await service.signIn();
      gateway.authenticate('user-a');
      await Future<void>.delayed(Duration.zero);
      expect(service.user?.id, 'user-a');
      expect(service.dataScopeReady, isFalse);
      expect(scopes, [configuration().accountScope('user-a')]);
      drain.complete();
      await Future<void>.delayed(Duration.zero);
      expect(service.dataScopeReady, isTrue);
      await service.signOut();
      expect(service.user, isNull);
      expect(scopes.last, isNull);
      expect(service.nicknameKey, 'mobile_profile_nickname');
      service.dispose();
      fixture.dispose();
      await gateway.close();
    },
  );

  test('failed scope switch remains covered and retry restores it', () async {
    final gateway = _Gateway();
    var failures = true;
    final fixture = _AppFixture();
    final service = AccountService(
      controller: fixture,
      gatewayFactory: (_) async => gateway,
      switchScope: (_) async {
        if (failures) throw StateError('write failure');
      },
    );
    await service.saveConfiguration(configuration());
    await service.signIn();
    gateway.authenticate('user-a');
    await Future<void>.delayed(Duration.zero);
    expect(service.dataScopeReady, isFalse);
    expect(service.error, '账号数据切换未完成，请重试');
    failures = false;
    await service.restore();
    expect(service.dataScopeReady, isTrue);
    expect(service.error, isNull);
    service.dispose();
    fixture.dispose();
    await gateway.close();
  });

  test(
    'cancel rejects late callbacks and removes the durable pending marker',
    () async {
      final gateway = _Gateway();
      final fixture = _AppFixture();
      final scopes = <String?>[];
      final service = AccountService(
        controller: fixture,
        gatewayFactory: (_) async => gateway,
        switchScope: (scope) async => scopes.add(scope),
      );
      await service.saveConfiguration(configuration());
      await service.signIn();
      expect(service.isAwaitingBrowser, isTrue);
      service.cancelSignIn();
      gateway.authenticate('late-user');
      await Future<void>.delayed(Duration.zero);
      expect(service.user, isNull);
      expect(service.isAwaitingBrowser, isFalse);
      expect(scopes, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getKeys().where((key) => key.endsWith('.pendingAt')),
        isEmpty,
      );
      service.dispose();
      fixture.dispose();
      await gateway.close();
    },
  );
}

class _AppFixture extends ChangeNotifier implements AppController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Gateway implements IdentityGateway, IdentityLocalSessionCleanup {
  final events = StreamController<IdentityEvent>.broadcast();
  IdentityUser? current;
  void authenticate(String id) {
    current = IdentityUser(id: id, displayName: 'Account fixture');
    events.add(IdentityEvent(type: IdentityEventType.signedIn, user: current));
  }

  @override
  IdentityUser? get cachedUser => current;
  @override
  Stream<IdentityEvent> get changes => events.stream;
  @override
  Future<bool> beginSignIn(IdentityProvider provider) async => true;
  @override
  Future<IdentityUser?> verifyCurrentUser() async => current;
  @override
  Future<void> signOut() => clearLocalSession();
  @override
  Future<void> clearLocalSession() async {
    current = null;
    events.add(const IdentityEvent(type: IdentityEventType.signedOut));
  }

  Future<void> close() => events.close();
}
