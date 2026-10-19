import 'dart:async';
import 'dart:convert';

import 'package:app_identity/app_identity.dart';
import 'package:board_game_agent/features/identity/services/account_public_reactions.dart';
import 'package:board_game_agent/features/identity/services/web_sync_files.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/account_public_fixture.dart';
import 'support/account_sync_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Web public entries carry optional revision without changing snapshot protocol',
    () async {
      var versioned = true;
      final files = WebPublicSyncFiles(
        WebSyncTransport(
          uid: 101,
          client: MockClient(
            (request) async => http.Response(
              jsonEncode({
                'entries': [
                  {
                    'name': 'd${'a' * 32}.json',
                    'directory': false,
                    'ownerUid': 101,
                    if (versioned) 'revision': '[101,1,2,3]',
                  },
                ],
              }),
              200,
            ),
          ),
          site: Uri.parse('https://games.example'),
          lane: 'public',
          isActive: () => true,
        ),
        uid: 101,
      );
      expect((await files.entries('u101')).single.revision, '[101,1,2,3]');
      versioned = false;
      expect((await files.entries('u101')).single.revision, isNull);
    },
  );
  test(
    'native and Web private logs converge, including cancellation and offline recovery',
    () async {
      final nativeFiles = MemoryPrivateFiles();
      final native = SyncDeviceFixture(), browser = SyncDeviceFixture();
      await native.start();
      await browser.start();
      var offline = false;
      final transport = WebSyncTransport(
        uid: 101,
        site: Uri.parse('https://games.example'),
        lane: 'private',
        isActive: () => true,
        client: MockClient((request) async {
          expect(request.headers['X-BGA-Account-UID'], '101');
          expect(request.url.origin, 'https://games.example');
          if (offline) return http.Response('{"error":"network"}', 502);
          final path = request.url.queryParameters['path']!;
          if (request.method == 'POST') {
            await nativeFiles.createImmutable(
              path,
              jsonDecode(request.body)['content'] as String,
            );
            return http.Response('{"saved":true}', 200);
          }
          return http.Response(
            jsonEncode(
              request.url.path.endsWith('entries')
                  ? {
                      'entries': [
                        for (final entry in await nativeFiles.list(path))
                          {'name': entry.name, 'directory': entry.directory},
                      ],
                    }
                  : {'content': await nativeFiles.read(path)},
            ),
            200,
          );
        }),
      );
      final webFiles = WebPrivateSyncFiles(transport);
      native.entities['favorite|catan'] = {
        'gameSlug': 'catan',
        'createdAt': '2026-10-18T00:00:00Z',
      };
      browser.entities['favorite|splendor'] = {
        'gameSlug': 'splendor',
        'createdAt': '2026-10-18T00:00:00Z',
      };
      expect((await native.sync(nativeFiles)).completed, isTrue);
      expect((await browser.sync(webFiles)).completed, isTrue);
      expect((await native.sync(nativeFiles)).completed, isTrue);
      expect(browser.entities, native.entities);
      browser.entities.remove('favorite|catan');
      offline = true;
      expect((await browser.sync(webFiles)).failed, isTrue);
      await browser.start(); // Browser refresh retains its journal and outbox.
      offline = false;
      expect((await browser.sync(webFiles)).completed, isTrue);
      expect((await native.sync(nativeFiles)).completed, isTrue);
      expect(native.entities.containsKey('favorite|catan'), isFalse);
      expect(native.entities, browser.entities);
    },
  );

  test(
    'Web public snapshots merge native likes without counting devices twice',
    () async {
      final hub = PublicFixtureHub();
      final native = SyncDeviceFixture(), browser = SyncDeviceFixture();
      await native.start();
      await browser.start();
      native.entities['favorite|catan'] = {
        'gameSlug': 'catan',
        'createdAt': '2026-10-18T00:00:00Z',
      };
      browser.entities['favorite|splendor'] = {
        'gameSlug': 'splendor',
        'createdAt': '2026-10-18T00:00:00Z',
      };
      final nativePublic = AccountPublicReactions(MemoryPublicFiles(hub, 101));
      await native.local.capture();
      await nativePublic.synchronize(native.local);
      final files = MemoryPublicFiles(hub, 101);
      final browserPublic = AccountPublicReactions(
        WebPublicSyncFiles(
          WebSyncTransport(
            uid: 101,
            site: Uri.parse('https://games.example'),
            lane: 'public',
            isActive: () => true,
            client: MockClient((request) async {
              final path = request.url.queryParameters['path']!;
              if (request.method == 'POST') {
                await files.replaceOwn(
                  path,
                  jsonDecode(request.body)['content'] as String,
                );
                return http.Response('{"saved":true}', 200);
              }
              return http.Response(
                jsonEncode(
                  request.url.path.endsWith('entries')
                      ? {
                          'entries': [
                            for (final e in await files.entries(path))
                              {
                                'name': e.name,
                                'directory': e.directory,
                                'ownerUid': e.ownerUid,
                              },
                          ],
                        }
                      : {'content': await files.read(path)},
                ),
                200,
              );
            }),
          ),
          uid: 101,
        ),
      );
      await browser.local.capture();
      await browserPublic.synchronize(browser.local);
      await nativePublic.synchronize(native.local);
      expect(native.entities, browser.entities);
      expect(native.entities.keys.toSet(), {
        'favorite|catan',
        'favorite|splendor',
      });
    },
  );

  test(
    'account switch cancels old response and prevents subsequent writes',
    () async {
      var active = true, calls = 0;
      final gate = Completer<http.Response>();
      final files = WebPrivateSyncFiles(
        WebSyncTransport(
          uid: 101,
          site: Uri.parse('https://games.example'),
          lane: 'private',
          isActive: () => active,
          client: MockClient((_) {
            calls++;
            return gate.future;
          }),
        ),
      );
      final pending = expectLater(
        files.read('operations/example.json'),
        throwsA(isA<PrivateFileException>()),
      );
      active = false;
      files.cancelRequests();
      gate.complete(http.Response('{"content":"old-account"}', 200));
      await pending;
      await expectLater(
        files.createImmutable('operations/example.json', '{}'),
        throwsA(isA<PrivateFileException>()),
      );
      expect(calls, 1);
    },
  );

  for (final status in [401, 403, 404, 507]) {
    test(
      'HTTP $status maps to retryable sync failure without leaking credentials',
      () async {
        final files = WebPrivateSyncFiles(
          WebSyncTransport(
            uid: 101,
            site: Uri.parse('https://games.example'),
            lane: 'private',
            isActive: () => true,
            client: MockClient((request) async {
              expect(request.headers.containsKey('Authorization'), isFalse);
              return http.Response('{}', status);
            }),
          ),
        );
        await expectLater(
          files.list('operations'),
          throwsA(
            isA<PrivateFileException>().having(
              (e) => e.failure,
              'failure',
              switch (status) {
                401 => PrivateFileFailure.session,
                403 => PrivateFileFailure.denied,
                404 => PrivateFileFailure.missing,
                _ => PrivateFileFailure.quota,
              },
            ),
          ),
        );
      },
    );
  }
}
