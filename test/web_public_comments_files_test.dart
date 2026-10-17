import 'dart:async';
import 'dart:convert';
import 'package:app_identity/app_identity.dart';
import 'package:board_game_agent/features/community/services/web_public_comments_files.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final path = 'u101/d${'a' * 32}.json';
  test(
    'guest reads native snapshots over same-origin API but cannot write',
    () async {
      var calls = 0;
      final files = WebPublicCommentsFiles(
        uid: 0,
        site: Uri.parse('https://games.example/'),
        client: MockClient((request) async {
          calls++;
          expect(request.method, 'GET');
          expect(request.headers['X-Board-Game-Request'], '1');
          expect(request.headers.containsKey('Authorization'), isFalse);
          expect(request.url.origin, 'https://games.example');
          return http.Response(
            jsonEncode(
              request.url.path.endsWith('entries')
                  ? {
                      'entries': [
                        {'name': 'u101', 'directory': true, 'ownerUid': 101},
                      ],
                    }
                  : {'content': 'snapshot'},
            ),
            200,
          );
        }),
      );
      expect((await files.entries('')).single.ownerUid, 101);
      expect(await files.read(path), 'snapshot');
      await expectLater(
        files.replaceOwn(path, '{}'),
        throwsA(isA<PrivateFileException>()),
      );
      expect(calls, 2);
    },
  );
  test(
    'signed in writes only own snapshot and surfaces expired session',
    () async {
      final files = WebPublicCommentsFiles(
        uid: 101,
        site: Uri.parse('https://games.example/'),
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.queryParameters['path'], path);
          expect(jsonDecode(request.body), {'content': 'snapshot'});
          return http.Response('{"error":"sessionRejected"}', 401);
        }),
      );
      await expectLater(
        files.replaceOwn(path, 'snapshot'),
        throwsA(
          isA<PrivateFileException>().having(
            (e) => e.failure,
            'failure',
            PrivateFileFailure.session,
          ),
        ),
      );
      await expectLater(
        files.replaceOwn('u999/d${'a' * 32}.json', '{}'),
        throwsA(isA<PrivateFileException>()),
      );
    },
  );
  test('cancelled old scope cannot publish a late read result', () async {
    final gate = Completer<http.Response>();
    final files = WebPublicCommentsFiles(
      uid: 0,
      site: Uri.parse('https://games.example/'),
      client: MockClient((_) => gate.future),
    );
    final pending = files.read(path);
    final assertion = expectLater(
      pending,
      throwsA(
        isA<PrivateFileException>().having(
          (e) => e.failure,
          'failure',
          PrivateFileFailure.cancelled,
        ),
      ),
    );
    files.cancelRequests();
    gate.complete(http.Response('{"content":"old"}', 200));
    await assertion;
  });
}
