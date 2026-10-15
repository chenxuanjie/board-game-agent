import 'dart:async';
import 'dart:convert';

import 'package:app_identity/app_identity.dart';
import 'package:board_game_agent/features/identity/services/web_account_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final id = List.filled(64, 'a').join();
  Map<String, Object?> user([String name = 'Shane']) => {
    'user': {'id': id, 'displayName': name},
  };
  final site = Uri.parse('https://games.example/nested/page');
  http.Response json(Object value, [int status = 200]) =>
      http.Response(jsonEncode(value), status);

  test(
    'Web configuration comes from same origin and exposes no secrets',
    () async {
      final config = await WebAccountGateway.loadConfiguration(
        site: site,
        client: MockClient((request) async {
          expect(
            request.url.toString(),
            'https://games.example/api/account/config',
          );
          expect(request.headers['X-Board-Game-Request'], '1');
          return json({
            'version': 1,
            'nasOrigin': 'https://nas.example:5001',
            'identityOrigin': 'https://canonical.example:5001',
          });
        }),
      );
      expect(config.nasOrigin.toString(), 'https://nas.example:5001');
      expect(
        config.identityOrigin.toString(),
        'https://canonical.example:5001',
      );
    },
  );

  test(
    'login establishes cookie session and returns verified server identity',
    () async {
      final requests = <http.Request>[];
      final gateway = WebAccountGateway(
        site: site,
        client: MockClient((request) async {
          requests.add(request);
          return json(request.method == 'GET' ? {'user': null} : user());
        }),
      );
      addTearDown(gateway.dispose);
      final signedIn = await gateway.signIn(
        account: 'Shane',
        password: 'transient',
        otp: '123456',
      );
      expect(signedIn.id, id);
      expect(gateway, isA<IdentityVerifiedSignInGateway>());
      expect(requests.map((r) => r.url.path), [
        '/api/account/session',
        '/api/account/login',
      ]);
      expect(jsonDecode(requests.last.body), {
        'account': 'Shane',
        'password': 'transient',
        'otp': '123456',
      });
      expect(
        requests.every(
          (r) => r.url.origin == site.origin && r.url.query.isEmpty,
        ),
        isTrue,
      );
      expect(
        requests.every((r) => !r.headers.containsKey('Authorization')),
        isTrue,
      );
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    },
  );

  test(
    'server session restores without storing credentials in preferences',
    () async {
      final gateway = WebAccountGateway(
        site: site,
        client: MockClient((_) async => json(user())),
      );
      addTearDown(gateway.dispose);
      expect((await gateway.verifyCurrentUser())?.displayName, 'Shane');
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    },
  );

  for (final code in [
    IdentityFailureCode.otpRequired,
    IdentityFailureCode.invalidOtp,
    IdentityFailureCode.invalidCredentials,
  ]) {
    test(
      'maps ${code.name} and does not persist rejected credentials',
      () async {
        final gateway = WebAccountGateway(
          site: site,
          client: MockClient(
            (request) async => request.method == 'GET'
                ? json({'user': null})
                : json({'error': code.name}, 403),
          ),
        );
        addTearDown(gateway.dispose);
        await expectLater(
          gateway.signIn(account: 'Shane', password: 'test'),
          throwsA(isA<IdentityFailure>().having((e) => e.code, 'code', code)),
        );
        expect(gateway.cachedUser, isNull);
        expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
      },
    );
  }

  test(
    'logout failure leaves a durable tombstone and blocks restored cookie',
    () async {
      var reachable = false;
      final paths = <String>[];
      final gateway = WebAccountGateway(
        site: site,
        client: MockClient((request) async {
          paths.add(request.url.path);
          if (request.url.path.endsWith('logout')) {
            if (!reachable) throw http.ClientException('offline');
            return json({'user': null});
          }
          return json(user());
        }),
      );
      addTearDown(gateway.dispose);
      await gateway.verifyCurrentUser();
      await expectLater(gateway.signOut(), throwsA(isA<IdentityFailure>()));
      expect(gateway.cachedUser, isNull);
      await expectLater(
        gateway.verifyCurrentUser(),
        throwsA(isA<IdentityFailure>()),
      );
      expect(paths.last, '/api/account/logout');
      reachable = true;
      await gateway.verifyCurrentUser();
      expect(paths.sublist(paths.length - 2), [
        '/api/account/logout',
        '/api/account/session',
      ]);
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    },
  );

  test(
    'late cancelled login cannot replace a newer account or write logout marker',
    () async {
      final pending = Completer<http.Response>();
      final entered = Completer<void>();
      final gateway = WebAccountGateway(
        site: site,
        client: MockClient((request) async {
          if (request.url.path.endsWith('login')) {
            entered.complete();
            return pending.future;
          }
          return json({'user': null});
        }),
      );
      addTearDown(gateway.dispose);
      final signingIn = gateway.signIn(account: 'Shane', password: 'test');
      final failed = expectLater(
        signingIn,
        throwsA(
          isA<IdentityFailure>().having(
            (e) => e.code,
            'code',
            IdentityFailureCode.cancelled,
          ),
        ),
      );
      await entered.future;
      await gateway.signOut();
      pending.complete(json(user()));
      await failed;
      expect(gateway.cachedUser, isNull);
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    },
  );

  test(
    'lost successful response triggers server logout instead of restoring identity',
    () async {
      final paths = <String>[];
      final gateway = WebAccountGateway(
        site: site,
        client: MockClient((request) async {
          paths.add(request.url.path);
          if (request.url.path.endsWith('login')) {
            throw http.ClientException('lost reply');
          }
          return json({'user': null});
        }),
      );
      addTearDown(gateway.dispose);
      await expectLater(
        gateway.signIn(account: 'Shane', password: 'test'),
        throwsA(isA<IdentityFailure>()),
      );
      expect(paths.last, '/api/account/logout');
      expect(gateway.cachedUser, isNull);
    },
  );

  test('malformed, oversized and HTML responses are sanitized', () async {
    for (final response in [
      http.Response('<html>bad proxy</html>', 502),
      json({
        'user': {'id': 'unverified-account-name', 'displayName': 'Shane'},
      }),
      http.Response('x' * 17000, 200),
    ]) {
      final gateway = WebAccountGateway(
        site: site,
        client: MockClient((_) async => response),
      );
      await expectLater(
        gateway.verifyCurrentUser(),
        throwsA(
          isA<IdentityFailure>().having(
            (e) => e.code,
            'code',
            IdentityFailureCode.providerUnavailable,
          ),
        ),
      );
      await gateway.dispose();
    }
  });
}
