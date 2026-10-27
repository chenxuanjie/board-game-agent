import 'dart:async';
import 'package:app_identity/app_identity.dart';
import 'package:board_game_agent/app/state/app_controller.dart';
import 'package:board_game_agent/features/identity/services/account_service.dart';
import 'package:board_game_agent/features/community/services/board_public_sync.dart';
import 'package:board_game_agent/features/identity/models/account_configuration.dart';
import 'package:board_game_agent/features/library/models/asset_source_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

AccountConfiguration configuration([String host = 'service.example.test']) =>
    AccountConfiguration.fromFields(nasUrl: 'https://$host');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'public subscription failure cannot block account switching or logout',
    () async {
      final subscriptions = <FixturePublicSync>[];
      final refreshes = <Future<void> Function(bool, Set<String>)>[];
      final service = AccountService(
        controller: FixtureApp(),
        gatewayFactory: (_) async => FixtureGateway(),
        savedLoginStorage: MemoryStorage(),
        switchScope: (_) async {},
        publicSyncFactory:
            ({
              required client,
              required active,
              required refresh,
              onStatusChanged,
            }) async {
              refreshes.add(refresh);
              final sync = FixturePublicSync();
              subscriptions.add(sync);
              return sync;
            },
      );
      addTearDown(service.dispose);
      await service.configureService('https://service.example.test');
      await Future<void>.delayed(Duration.zero);
      final guest = subscriptions.last, staleRefresh = refreshes.last;
      await service.signIn(account: 'reader', password: 'fixture');
      expect(guest.closes, 1);
      expect(service.isSignedIn, isTrue);
      expect(service.error, isNull);
      await expectLater(staleRefresh(true, {}), throwsStateError);
      final signedIn = subscriptions.last;
      await service.signOut();
      expect(signedIn.closes, 1);
      expect(service.isSignedIn, isFalse);
      expect(service.dataScopeReady, isTrue);
      expect(service.error, isNull);
    },
  );
  test(
    'cancelling an accepted account during scope activation still signs out',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      final service = AccountService(
        controller: FixtureApp(),
        gatewayFactory: (_) async => FixtureGateway(),
        savedLoginStorage: MemoryStorage(),
        switchScope: (scope) async {
          if (scope != null) {
            entered.complete();
            await release.future;
          }
        },
      );
      addTearDown(service.dispose);
      await service.configureService('https://service.example.test');
      final attempt = service.signIn(account: 'reader', password: 'fixture');
      await entered.future;
      final cancellation = service.cancelSignIn();
      release.complete();
      await Future.wait([attempt, cancellation]);
      expect(service.user, isNull);
      expect(service.currentAccountScope, isNull);
    },
  );
  test(
    'API selection, account switching and logout use isolated fresh scopes',
    () async {
      final gateway = FixtureGateway(), app = FixtureApp();
      final scopes = <String?>[];
      final service = AccountService(
        controller: app,
        gatewayFactory: (_) async => gateway,
        savedLoginStorage: MemoryStorage(),
        switchScope: (scope) async => scopes.add(scope),
      );
      addTearDown(service.dispose);
      await service.configureService('https://service.example.test');
      await service.signIn(account: 'first', password: 'fixture');
      final first = service.currentAccountScope;
      expect(service.user?.id, 'first');
      expect(first, isNotNull);

      await service.signOut();
      expect(service.user, isNull);
      expect(scopes.last, isNull);
      await service.signIn(account: 'second', password: 'fixture');
      expect(service.currentAccountScope, isNot(first));
      expect(service.savedLogins.first.username, 'second');
    },
  );
  test('failed scope activation stays covered until retry', () async {
    var fail = true;
    final service = AccountService(
      controller: FixtureApp(),
      gatewayFactory: (_) async => FixtureGateway(),
      savedLoginStorage: MemoryStorage(),
      switchScope: (_) async {
        if (fail) throw StateError('fixture');
      },
    );
    addTearDown(service.dispose);
    await service.configureService('https://service.example.test');
    await service.signIn(account: 'first', password: 'fixture');
    expect(service.dataScopeReady, isFalse);
    fail = false;
    await service.restore();
    expect(service.dataScopeReady, isTrue);
  });
  test('OTP and cancelled attempts never publish a late account', () async {
    final gateway = FixtureGateway()..otpRequired = true;
    final service = AccountService(
      controller: FixtureApp(),
      gatewayFactory: (_) async => gateway,
      savedLoginStorage: MemoryStorage(),
      switchScope: (_) async {},
    );
    addTearDown(service.dispose);
    await service.configureService('https://service.example.test');
    await service.signIn(account: 'first', password: 'fixture');
    expect(service.needsOtp, isTrue);
    expect(service.user, isNull);
    await service.signIn(account: 'first', password: 'fixture', otp: '123456');
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
  });
}

class FixturePublicSync extends Fake implements BoardPublicSync {
  int closes = 0;
  @override
  String? get error => null;
  @override
  Future<void> start() async {}
  @override
  Future<void> close() async {
    closes++;
    throw StateError('Public SQLite close failure');
  }
}

class FixtureApp implements AppController {
  @override
  List<AssetSourceConfig> get assetSourceConfigs => const [];
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
