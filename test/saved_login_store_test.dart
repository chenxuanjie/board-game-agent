import 'dart:convert';

import 'support/memory_login_storage.dart';
import 'package:board_game_agent/features/identity/services/account_service.dart';
import 'package:board_game_agent/features/identity/services/saved_login_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'account_service_test.dart'
    show FixtureApp, FixtureGateway, configuration;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'keeps ten most recent accounts, deduplicates and isolates NAS',
    () async {
      final memory = MemoryLoginStorage();
      final store = SavedLoginStore(storage: memory);
      for (var i = 0; i < 12; i++) {
        await store.remember(
          environment: 'nas',
          username: 'reader$i',
          password: 'synthetic',
          savePassword: true,
        );
      }
      expect(store.entries.length, 10);
      expect(store.entries.first.username, 'reader11');
      expect(store.entries.last.username, 'reader2');
      await store.remember(
        environment: 'nas',
        username: 'reader5',
        password: 'replacement',
        savePassword: true,
      );
      expect(store.entries.length, 10);
      expect(store.entries.first.username, 'reader5');
      expect(store.entries.where((e) => e.username == 'reader5').length, 1);
      await store.remember(
        environment: 'other',
        username: 'reader5',
        password: 'separate',
        savePassword: true,
      );
      expect(store.entries.where((e) => e.username == 'reader5').length, 2);
      final restarted = SavedLoginStore(storage: memory);
      await restarted.load();
      expect(restarted.entries.first.environment, 'other');
      expect(restarted.entries.first.password, 'separate');
    },
  );

  test(
    'unchecked option removes previous password but keeps account',
    () async {
      final memory = MemoryLoginStorage();
      final store = SavedLoginStore(storage: memory);
      await store.remember(
        environment: 'nas',
        username: 'reader',
        password: 'synthetic',
        savePassword: true,
      );
      await store.remember(
        environment: 'nas',
        username: 'reader',
        password: 'replacement',
        savePassword: false,
      );
      expect(store.entries.single.hasPassword, isFalse);
      expect(
        (jsonDecode(memory.value!)['accounts'] as List).single.containsKey(
          'password',
        ),
        isFalse,
      );
      await store.forget(store.entries.single);
      expect(store.entries, isEmpty);
      final restarted = SavedLoginStore(storage: memory);
      await restarted.load();
      expect(restarted.entries, isEmpty);
    },
  );

  test('failed writes retain last committed history and can retry', () async {
    final memory = MemoryLoginStorage();
    final store = SavedLoginStore(storage: memory);
    await store.remember(
      environment: 'nas',
      username: 'reader',
      password: 'synthetic',
      savePassword: true,
    );
    final original = memory.value;
    memory.failWrite = true;
    await expectLater(store.forget(store.entries.single), throwsStateError);
    expect(memory.value, original);
    expect(store.entries.single.username, 'reader');
    memory.failWrite = false;
    await store.forget(store.entries.single);
    expect(store.entries, isEmpty);
  });

  test('concurrent saves are serialized without losing accounts', () async {
    final store = SavedLoginStore(storage: MemoryLoginStorage());
    await Future.wait([
      for (var i = 0; i < 20; i++)
        store.remember(
          environment: 'nas',
          username: 'reader$i',
          password: '',
          savePassword: false,
        ),
    ]);
    expect(store.entries.map((e) => e.username), [
      for (var i = 19; i >= 10; i--) 'reader$i',
    ]);
  });

  test('malformed history cannot be overwritten by a new login', () async {
    final memory = MemoryLoginStorage()..value = '{"version":2,"accounts":[]}';
    final store = SavedLoginStore(storage: memory);
    await expectLater(
      store.remember(
        environment: 'nas',
        username: 'reader',
        password: '',
        savePassword: false,
      ),
      throwsFormatException,
    );
    expect(memory.value, '{"version":2,"accounts":[]}');
  });

  test(
    'failed initial read can retry without exposing partial history',
    () async {
      final memory = MemoryLoginStorage()..failRead = true;
      final store = SavedLoginStore(storage: memory);
      await expectLater(store.load(), throwsStateError);
      expect(store.entries, isEmpty);
      memory.failRead = false;
      await store.remember(
        environment: 'nas',
        username: 'reader',
        password: '',
        savePassword: false,
      );
      expect(store.entries.single.username, 'reader');
    },
  );

  test(
    'verified saved login survives sign-out and restart without signing in',
    () async {
      final app = FixtureApp(), memory = MemoryLoginStorage();
      AccountService create() => AccountService(
        controller: app,
        savedLoginStorage: memory,
        gatewayFactory: (_) async => FixtureGateway(),
        switchScope: (_) async {},
      );
      var service = create();
      await service.saveConfiguration(configuration());
      await service.signIn(
        account: 'reader',
        password: 'synthetic',
        savePassword: true,
      );
      expect(service.savedLogins.single.password, 'synthetic');
      await service.signOut();
      expect(service.resourceCredentialsReady, isFalse);
      expect(service.savedLogins.single.username, 'reader');
      service.dispose();
      service = create();
      await service.initialize();
      await service.loadSavedLogins();
      expect(service.isSignedIn, isFalse);
      expect(service.savedLogins.single.password, 'synthetic');
      await service.saveConfiguration(configuration('separate.example.test'));
      expect(service.savedLogins, isEmpty);
      service.dispose();
      app.dispose();
    },
  );

  test('OTP challenge and cancellation never save credentials', () async {
    final app = FixtureApp(), memory = MemoryLoginStorage();
    final gateway = FixtureGateway()..otpRequired = true;
    final service = AccountService(
      controller: app,
      savedLoginStorage: memory,
      gatewayFactory: (_) async => gateway,
      switchScope: (_) async {},
    );
    await service.saveConfiguration(configuration());
    await service.signIn(
      account: 'reader',
      password: 'synthetic',
      savePassword: true,
    );
    expect(service.needsOtp, isTrue);
    expect(memory.value, isNull);
    await service.cancelSignIn();
    expect(memory.value, isNull);
    service.dispose();
    app.dispose();
  });

  test(
    'history storage failure does not revoke successful authentication',
    () async {
      final app = FixtureApp(), memory = MemoryLoginStorage()..failWrite = true;
      final service = AccountService(
        controller: app,
        savedLoginStorage: memory,
        gatewayFactory: (_) async => FixtureGateway(),
        switchScope: (_) async {},
      );
      await service.saveConfiguration(configuration());
      await service.signIn(
        account: 'reader',
        password: 'synthetic',
        savePassword: true,
      );
      expect(service.isSignedIn, isTrue);
      expect(service.savedLoginError, contains('未保存'));
      expect(service.savedLogins, isEmpty);
      expect(service.error, isNull);
      service.dispose();
      app.dispose();
    },
  );
}
