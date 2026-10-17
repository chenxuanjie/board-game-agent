import 'dart:async';
import 'dart:convert';

import 'package:board_game_agent/core/models/connectivity_status.dart';
import 'package:board_game_agent/features/games/services/game_manifest_service.dart';
import 'package:board_game_agent/features/library/models/asset_source_config.dart';
import 'package:board_game_agent/features/library/services/same_origin_library_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const catalog = '{"version":1,"games":[]}';
const path = 'assets/games/sample/docs/rules.pdf';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  String? scope;
  late List<http.Request> requests;
  late SameOriginLibraryService service;
  late Future<http.Response> Function(http.Request) respond;
  setUp(() {
    scope = 'account-a';
    requests = [];
    respond = (request) async =>
        http.Response(catalog, 200, headers: {'etag': '"v1"'});
    service = SameOriginLibraryService(
      accountScope: () => scope,
      accessAllowed: () => scope != null,
      site: Uri.parse('https://games.example/'),
      client: MockClient((request) async {
        requests.add(request);
        return respond(request);
      }),
    );
  });

  test(
    'guest published PDF uses same-origin HEAD without account credentials',
    () async {
      final guest = SameOriginLibraryService(
        accountScope: () => 'web_guest',
        accessAllowed: () => true,
        site: Uri.parse('https://games.example/'),
        client: MockClient((request) async {
          expect(request.method, 'HEAD');
          expect(request.url.queryParameters['account'], 'web_guest');
          expect(request.headers.containsKey('Authorization'), isFalse);
          return http.Response('', 200, headers: {'etag': '"guest-pdf"'});
        }),
      );
      final cached = await guest.ensureCached(sources: [], remotePath: path);
      expect(cached!.localPath, contains('/library/$path'));
      expect(guest.accessAllowed, isTrue);
    },
  );

  test(
    'resource URI is same-origin, scoped, and never contains credentials',
    () {
      final uri = service.resourceUri(path)!;
      expect(uri.origin, 'https://games.example');
      expect(uri.path, '/library/$path');
      expect(uri.queryParameters['account'], 'account-a');
      scope = 'account-b';
      expect(
        service.resourceUri(path)!.queryParameters['account'],
        'account-b',
      );
      scope = null;
      expect(service.resourceUri(path), isNull);
    },
  );

  test('invalid paths and signed-out reads never issue requests', () async {
    for (final path in [
      'assets/../x',
      'assets/%2e%2e/x',
      'assets/.env',
      'assets/x\\y',
      'assets/games/x/docs/others/x',
      '/etc/passwd',
    ]) {
      expect(service.resourceUri(path), isNull);
    }
    scope = null;
    expect(
      await service.fetchRemoteText(sources: [], remotePath: path),
      isNull,
    );
    expect(requests, isEmpty);
  });

  test(
    'concurrent entrance probes share one request and conditional 304 reuses metadata',
    () async {
      final gate = Completer<http.Response>();
      respond = (_) => gate.future;
      final a = service.fetchRemoteText(
        sources: [],
        remotePath: 'assets/catalog.json',
      );
      final b = service.fetchRemoteText(
        sources: [],
        remotePath: 'assets/catalog.json',
      );
      gate.complete(http.Response(catalog, 200, headers: {'etag': '"v1"'}));
      expect(await Future.wait([a, b]), [catalog, catalog]);
      expect(requests, hasLength(1));
      respond = (request) async {
        expect(request.headers['If-None-Match'], '"v1"');
        expect(request.headers['X-Board-Game-Request'], '1');
        expect(request.headers.containsKey('Authorization'), isFalse);
        return http.Response('', 304);
      };
      expect(
        await service.fetchRemoteText(
          sources: [],
          remotePath: 'assets/catalog.json',
        ),
        catalog,
      );
    },
  );

  test(
    'old account response cannot enter a new scope or a new generation of the same scope',
    () async {
      final gate = Completer<http.Response>();
      respond = (_) => gate.future;
      final pending = service.fetchRemoteText(
        sources: [],
        remotePath: 'assets/catalog.json',
      );
      await Future<void>.delayed(Duration.zero);
      service.clearAccountCache();
      gate.complete(http.Response(catalog, 200));
      expect(await pending, isNull);
      expect(await service.cachedBytesFor('assets/catalog.json'), isNull);
      scope = 'account-b';
      expect(await service.cachedBytesFor('assets/catalog.json'), isNull);
    },
  );

  test(
    'PDF resolution uses HEAD and a URL instead of downloading all bytes',
    () async {
      respond = (request) async {
        expect(request.method, 'HEAD');
        return http.Response('', 200, headers: {'etag': '"pdf-v2"'});
      };
      final document = await service.ensureCached(
        sources: [],
        remotePath: path,
      );
      expect(Uri.parse(document!.localPath).queryParameters['v'], '"pdf-v2"');
      expect(await service.cachedBytesFor(path), isNull);
    },
  );

  test(
    'quick checks reuse already-probed catalog and full checks detect resource edits and deletion',
    () async {
      expect(
        await service.refreshPublishedLibrary(checkedCatalog: catalog),
        isTrue,
      );
      expect(
        await service.refreshPublishedLibrary(checkedCatalog: catalog),
        isFalse,
      );
      expect(requests, isEmpty);
      var version = 'v1';
      var files = [path];
      respond = (request) async {
        expect(request.url.path, '/api/library/versions');
        return http.Response(
          jsonEncode({
            'files': files
                .map((p) => {'path': p, 'exists': true, 'version': version})
                .toList(),
          }),
          200,
        );
      };
      expect(
        await service.refreshPublishedLibrary(
          complete: true,
          checkedCatalog: catalog,
        ),
        isTrue,
      );
      expect(
        await service.refreshPublishedLibrary(
          complete: true,
          checkedCatalog: catalog,
        ),
        isFalse,
      );
      version = 'v2';
      expect(
        await service.refreshPublishedLibrary(
          complete: true,
          checkedCatalog: catalog,
        ),
        isTrue,
      );
      expect(service.resourceUri(path)!.queryParameters['v'], 'v2');
      files = [];
      expect(
        await service.refreshPublishedLibrary(
          complete: true,
          checkedCatalog: catalog,
        ),
        isTrue,
      );
    },
  );

  test(
    'missing published resources fail full check and keep a retry possible',
    () async {
      respond = (_) async => http.Response(
        jsonEncode({
          'files': [
            {'path': path, 'exists': false},
          ],
        }),
        200,
      );
      await expectLater(
        service.refreshPublishedLibrary(
          complete: true,
          checkedCatalog: catalog,
        ),
        throwsStateError,
      );
      respond = (_) async => http.Response('{"files":[]}', 200);
      expect(
        await service.refreshPublishedLibrary(
          complete: true,
          checkedCatalog: catalog,
        ),
        isTrue,
      );
    },
  );

  test('listing rejects paths outside the requested game', () async {
    respond = (_) async => http.Response(
      '{"files":[{"path":"assets/games/other/docs/x.md","name":"x.md"}]}',
      200,
    );
    await expectLater(
      service.listFilesRecursively(
        sources: [],
        remotePath: 'assets/games/sample',
      ),
      throwsFormatException,
    );
  });

  test(
    'permission errors never silently return a stale cached catalog',
    () async {
      await service.fetchRemoteText(
        sources: [],
        remotePath: 'assets/catalog.json',
      );
      respond = (_) async => http.Response('', 403);
      expect(
        await service.fetchRemoteText(
          sources: [],
          remotePath: 'assets/catalog.json',
        ),
        isNull,
      );
      final status = await service.checkAccess(
        AssetSourceConfig(
          id: 'nas',
          name: 'NAS',
          address: 'https://unused.example/',
          testUrl: 'https://unused.example/',
        ),
      );
      expect(status.state, ConnectivityState.failure);
    },
  );

  test(
    'signed-in catalog is authoritative rather than overlaying removed bundled games',
    () async {
      final manifest = await GameManifestService().loadMergedCatalogManifest(
        remoteAssetService: service,
      );
      expect(manifest.games, isEmpty);
      expect(requests.single.url.path, '/library/assets/catalog.json');
    },
  );

  test(
    'catalog change invalidates decoded image URLs, unchanged checks keep URLs stable',
    () async {
      final before = service.resourceUri(path);
      await service.refreshPublishedLibrary(checkedCatalog: catalog);
      final first = service.resourceUri(path);
      expect(first, isNot(before));
      await service.refreshPublishedLibrary(checkedCatalog: catalog);
      expect(service.resourceUri(path), first);
      await service.refreshPublishedLibrary(
        checkedCatalog: '{"version":2,"games":[]}',
      );
      expect(service.resourceUri(path), isNot(first));
    },
  );

  test(
    'small metadata cache is bounded and request timeout remains retryable',
    () async {
      final bounded = SameOriginLibraryService(
        accountScope: () => scope,
        accessAllowed: () => scope != null,
        site: Uri.parse('https://games.example'),
        maxCacheBytes: 5,
        requestTimeout: const Duration(milliseconds: 20),
        client: MockClient((request) => respond(request)),
      );
      respond = (_) async => http.Response('12345', 200);
      await bounded.fetchRemoteText(sources: [], remotePath: 'assets/one.txt');
      await bounded.fetchRemoteText(sources: [], remotePath: 'assets/two.txt');
      expect(await bounded.cachedBytesFor('assets/one.txt'), isNull);
      expect(await bounded.cachedBytesFor('assets/two.txt'), isNotNull);
      respond = (_) => Completer<http.Response>().future;
      await expectLater(
        bounded.fetchRemoteText(sources: [], remotePath: 'assets/slow.txt'),
        throwsA(isA<TimeoutException>()),
      );
      respond = (_) async => http.Response('retry', 200);
      expect(
        await bounded.fetchRemoteText(
          sources: [],
          remotePath: 'assets/slow.txt',
        ),
        'retry',
      );
    },
  );
}
