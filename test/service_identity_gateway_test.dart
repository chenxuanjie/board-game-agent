import 'dart:async';
import 'dart:convert';
import 'package:app_client/app_client.dart';
import 'package:app_identity/app_identity.dart';
import 'package:board_game_agent/features/identity/models/service_configuration.dart';
import 'package:board_game_agent/features/identity/services/service_identity_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final userA = 'a' * 64, userB = 'b' * 64;
Map<String, dynamic> response({String? user, bool native = true}) => {
  'app_id': 'board_game_agent',
  'user_id': user ?? userA,
  'display_name': 'Reader',
  'access_token': 'opaque-test-access',
  if (native) 'refresh_token': 'opaque-test-refresh',
};
http.Response json(Map<String, dynamic> value, [int status = 200]) =>
    http.Response(jsonEncode(value), status);

class Vault implements RefreshSessionStore {
  String? value;
  bool rejectWrites = false;
  Completer<void>? hold;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async {
    if (rejectWrites) throw StateError('storage unavailable');
    final waiting = hold;
    hold = null;
    if (waiting != null) await waiting.future;
    value = next;
  }

  @override
  Future<void> delete() async => value = null;
}

ServiceIdentityGateway gateway(
  Vault vault,
  Future<http.Response> Function(http.Request) handler, {
  bool browser = false,
}) {
  final config = ServiceConfiguration(Uri.parse('https://service.example'));
  return ServiceIdentityGateway(
    configuration: config,
    browser: browser,
    store: vault,
    client: AppJsonClient(
      config.origin,
      applicationId: ServiceConfiguration.applicationId,
      baseUri: config.origin.resolve(browser ? '/api/' : '/'),
      client: MockClient((request) async {
        expect(request.headers['X-App-ID'], 'board_game_agent');
        expect(request.url.path, contains('/v1/apps/board_game_agent/auth/'));
        expect(request.url.path, isNot(contains('webapi')));
        return handler(request);
      }),
    ),
  );
}

void main() {
  test(
    'controller deadline cannot leave a restorable late credential write',
    () async {
      final vault = Vault(), hold = Completer<void>();
      final g = gateway(vault, (_) async => json(response()));
      final controller = IdentityController(
        gateway: g,
        requestTimeout: const Duration(milliseconds: 30),
        signInTimeout: const Duration(milliseconds: 30),
      );
      addTearDown(() async {
        controller.dispose();
        await g.dispose();
      });
      vault.hold = hold;
      await controller.signIn(account: 'reader', password: 'fixture');
      expect(controller.user, isNull);
      hold.complete();
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(jsonDecode(vault.value!)['logout_pending'], true);
      expect(g.cachedUser, isNull);
      expect(await g.verifyCurrentUser(), isNull);
      expect(vault.value, isNull);
    },
  );
  test('secure-store failure does not publish a successful login', () async {
    final vault = Vault()..rejectWrites = true;
    var revocations = 0;
    final g = gateway(vault, (request) async {
      if (request.url.path.endsWith('/logout')) revocations++;
      return json(response());
    });
    addTearDown(g.dispose);
    await expectLater(
      g.signIn(account: 'reader', password: 'fixture'),
      throwsA(
        isA<IdentityFailure>().having(
          (e) => e.code,
          'code',
          IdentityFailureCode.storage,
        ),
      ),
    );
    expect(g.cachedUser, isNull);
    expect(revocations, 1);
  });
  test(
    'native login stores only scoped session and restores verified identity',
    () async {
      final vault = Vault();
      var refreshes = 0;
      Future<http.Response> server(http.Request req) async {
        if (req.url.path.endsWith('/refresh')) refreshes++;
        return json(response());
      }

      var g = gateway(vault, server);
      expect(
        (await g.signIn(account: 'reader', password: 'fixture-password')).id,
        userA,
      );
      expect(vault.value, isNot(contains('fixture-password')));
      expect(vault.value, isNot(contains('opaque-test-access')));
      await g.dispose();
      g = gateway(vault, server);
      addTearDown(g.dispose);
      await g.initialize();
      expect(g.cachedUser?.id, userA);
      final restored = await Future.wait([
        g.verifyCurrentUser(),
        g.verifyCurrentUser(),
      ]);
      expect(restored.map((u) => u?.id), [userA, userA]);
      expect(refreshes, 1);
    },
  );
  test(
    'refresh identity changes are rejected and cannot select another workspace',
    () async {
      final vault = Vault();
      var changed = false;
      final g = gateway(
        vault,
        (_) async => json(response(user: changed ? userB : userA)),
      );
      addTearDown(g.dispose);
      await g.signIn(account: 'reader', password: 'fixture');
      changed = true;
      await expectLater(
        g.verifyCurrentUser(),
        throwsA(
          isA<IdentityFailure>().having(
            (e) => e.code,
            'code',
            IdentityFailureCode.sessionRejected,
          ),
        ),
      );
      expect(g.cachedUser, isNull);
      expect(vault.value, isNull);
    },
  );
  test(
    'offline logout persists a tombstone across restart and retries revocation',
    () async {
      final vault = Vault();
      var offline = false;
      var logins = 0;
      Future<http.Response> server(http.Request req) async {
        if (req.url.path.endsWith('/logout') && offline) {
          throw http.ClientException('offline');
        }
        if (req.url.path.endsWith('/login')) logins++;
        return json(req.url.path.endsWith('/logout') ? {} : response());
      }

      var g = gateway(vault, server);
      await g.signIn(account: 'reader', password: 'fixture');
      offline = true;
      await expectLater(g.signOut(), throwsA(isA<IdentityFailure>()));
      expect(g.cachedUser, isNull);
      expect(jsonDecode(vault.value!)['logout_pending'], true);
      await g.dispose();
      g = gateway(vault, server);
      addTearDown(g.dispose);
      await g.initialize();
      expect(g.cachedUser, isNull);
      await expectLater(
        g.signIn(account: 'reader', password: 'fixture'),
        throwsA(isA<IdentityFailure>()),
      );
      expect(logins, 1);
      offline = false;
      expect(await g.verifyCurrentUser(), isNull);
      expect(vault.value, isNull);
      expect(
        (await g.signIn(account: 'reader', password: 'fixture')).id,
        userA,
      );
    },
  );
  test('late credential persistence cannot undo cancellation', () async {
    final vault = Vault(), hold = Completer<void>();
    final g = gateway(vault, (_) async => json(response()));
    addTearDown(g.dispose);
    vault.hold = hold;
    final attempt = g.signIn(account: 'reader', password: 'fixture');
    final assertion = expectLater(attempt, throwsA(isA<IdentityFailure>()));
    while (vault.hold != null) {
      await Future<void>.delayed(Duration.zero);
    }
    final cancel = g.signOut();
    hold.complete();
    await cancel;
    await assertion;
    expect(g.cachedUser, isNull);
    expect(vault.value, isNull);
  });
  test(
    'cancelled network response cannot persist or publish a candidate',
    () async {
      final vault = Vault(),
          held = Completer<http.Response>(),
          entered = Completer<void>();
      final g = gateway(vault, (req) async {
        if (req.url.path.endsWith('/login')) {
          entered.complete();
          return held.future;
        }
        return json({});
      });
      addTearDown(g.dispose);
      final attempt = g.signIn(account: 'reader', password: 'fixture');
      final assertion = expectLater(attempt, throwsA(isA<IdentityFailure>()));
      await entered.future;
      await g.signOut();
      held.complete(json(response()));
      await assertion;
      expect(g.cachedUser, isNull);
      expect(vault.value, isNull);
    },
  );
  test(
    'browser uses scoped CSRF and never persists access or refresh tokens',
    () async {
      final vault = Vault(), paths = <String>[];
      final g = gateway(vault, (req) async {
        paths.add(req.url.path);
        if (req.url.path.endsWith('/bootstrap')) {
          return json({'csrf_token': 'test-csrf', 'authenticated': false});
        }
        expect(req.headers['X-CSRF-Token'], 'test-csrf');
        return json(
          req.url.path.endsWith('/logout') ? {} : response(native: false),
        );
      }, browser: true);
      addTearDown(g.dispose);
      await g.signIn(account: 'reader', password: 'fixture');
      expect(vault.value, isNull);
      await g.verifyCurrentUser();
      await g.signOut();
      expect(
        paths.every(
          (p) => p.startsWith('/api/v1/apps/board_game_agent/auth/browser/'),
        ),
        true,
      );
    },
  );
  test(
    'wrong application response is rejected without local session adoption',
    () async {
      final vault = Vault();
      final g = gateway(
        vault,
        (_) async => json({...response(), 'app_id': 'zheri'}),
      );
      addTearDown(g.dispose);
      await expectLater(
        g.signIn(account: 'reader', password: 'fixture'),
        throwsA(isA<IdentityFailure>()),
      );
      expect(g.cachedUser, isNull);
      expect(vault.value, isNull);
    },
  );
  test(
    'OTP and HTTP classifications are stable and do not leak response text',
    () async {
      for (final (code, status, expected) in [
        ('otp_required', 401, IdentityFailureCode.otpRequired),
        ('invalid_credentials', 401, IdentityFailureCode.invalidCredentials),
        ('rate_limited', 429, IdentityFailureCode.rateLimited),
        ('http_error', 503, IdentityFailureCode.providerUnavailable),
      ]) {
        final g = gateway(Vault(), (_) async => json({'detail': code}, status));
        await expectLater(
          g.signIn(account: 'reader', password: 'fixture'),
          throwsA(
            isA<IdentityFailure>().having((e) => e.code, 'code', expected),
          ),
        );
        await g.dispose();
      }
    },
  );
}
