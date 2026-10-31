import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:board_game_agent/features/library/services/remote_asset_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'support/catalog_http_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late CatalogHttpFixture fixture;
  late Uri origin;
  late RemoteAssetService service;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('board-sql-catalog-');
    fixture = CatalogHttpFixture();
    origin = Uri.parse('https://api.test');
    service = RemoteAssetService(
      client: fixture.client,
      cacheDirectory: directory,
      serviceOrigin: () => origin,
    );
  });
  tearDown(() async {
    service.dispose();
    await directory.delete(recursive: true);
  });
  test(
    'anonymous SQL snapshot and files use new endpoints, verify hashes and coalesce downloads',
    () async {
      final snapshot = await service.loadCatalog();
      expect(snapshot.games.single.slug, 'cabo');
      final values = await Future.wait([
        service.loadText(
          sources: [],
          remotePath: 'assets/games/cabo/docs/rules.md',
        ),
        service.loadText(
          sources: [],
          remotePath: 'assets/games/cabo/docs/rules.md',
        ),
      ]);
      expect(values, ['rules', 'rules']);
      expect(
        fixture.requests.where(
          (r) => r.url.path.endsWith('/cabo-rules/content'),
        ),
        hasLength(1),
      );
      expect(
        fixture.requests.every(
          (r) =>
              !r.headers.containsKey('Authorization') &&
              !r.headers.containsKey('Cookie'),
        ),
        isTrue,
      );
      expect(
        fixture.requests.every(
          (r) =>
              !r.url.path.contains('/library') && !r.url.path.endsWith('.json'),
        ),
        isTrue,
      );
    },
  );
  test(
    'unchanged revision performs one lightweight read without probing files or editions',
    () async {
      await service.loadCatalog();
      fixture.requests.clear();
      expect(await service.refreshCatalog(), isFalse);
      expect(fixture.requests.single.url.path, endsWith('/catalog/revision'));
    },
  );
  test(
    'changes paginate fully, remove unpublished editions and refresh only affected metadata',
    () async {
      fixture.pageSize = 1;
      fixture.put('second');
      await service.loadCatalog();
      fixture.requests.clear();
      fixture.put('cabo', text: 'next', bump: true);
      fixture.remove('second');
      expect(await service.refreshCatalog(), isTrue);
      expect(service.catalog!.games.map((g) => g.id), ['cabo']);
      expect(service.catalog!.revision, fixture.revision);
      expect(
        fixture.requests
            .where((r) => r.url.path.contains('/editions/'))
            .map((r) => r.url.pathSegments.last),
        ['cabo'],
      );
      expect(
        fixture.requests.any(
          (r) =>
              r.url.path.endsWith('/changes') &&
              r.url.queryParameters.containsKey('cursor'),
        ),
        isTrue,
      );
    },
  );
  test(
    'a delayed availability probe cannot roll back an already applied revision',
    () async {
      await service.loadCatalog();
      fixture.put('cabo', text: 'next', bump: true);
      await service.refreshCatalog();
      expect(await service.refreshCatalog(knownRevision: 1), isFalse);
      expect(service.catalog!.revision, 2);
    },
  );
  test(
    'failed publication refresh retains the last complete catalog and cached document',
    () async {
      await service.loadCatalog();
      await service.loadText(
        sources: [],
        remotePath: 'assets/games/cabo/docs/rules.md',
      );
      fixture.offline = true;
      await expectLater(service.refreshCatalog(), throwsStateError);
      expect(service.catalog!.revision, 1);
      expect(
        await service.loadText(
          sources: [],
          remotePath: 'assets/games/cabo/docs/rules.md',
        ),
        'rules',
      );
    },
  );
  test(
    'restart restores only this origin and changing service origins cannot reuse the prior catalog',
    () async {
      await service.loadCatalog();
      service.dispose();
      service = RemoteAssetService(
        client: fixture.client,
        cacheDirectory: directory,
        serviceOrigin: () => origin,
      );
      await service.restoreCatalog();
      expect(service.catalog!.revision, 1);
      origin = Uri.parse('https://different.test');
      expect(service.catalog, isNull);
      await service.restoreCatalog();
      expect(service.catalog, isNull);
      expect(
        await service.cachedBytesFor('assets/games/cabo/docs/rules.md'),
        isNull,
      );
    },
  );
  test('corrupt download never replaces a confirmed cached object', () async {
    await service.loadCatalog();
    await service.ensureCached(
      sources: [],
      remotePath: 'assets/games/cabo/docs/rules.md',
    );
    fixture.corrupt = true;
    await expectLater(
      service.ensureCached(
        sources: [],
        remotePath: 'assets/games/cabo/docs/rules.md',
        forceRefresh: true,
        allowCachedFallback: false,
      ),
      throwsStateError,
    );
    expect(
      utf8.decode(
        (await service.cachedBytesFor('assets/games/cabo/docs/rules.md'))!,
      ),
      'rules',
    );
  });
  test(
    'new digest gets a new cache entry, and never falls back to an old-version document',
    () async {
      await service.loadCatalog();
      await service.loadText(
        sources: [],
        remotePath: 'assets/games/cabo/docs/rules.md',
      );
      fixture.put('cabo', text: 'new rules', bump: true);
      await service.refreshCatalog();
      expect(
        await service.cachedBytesFor('assets/games/cabo/docs/rules.md'),
        isNull,
      );
      expect(
        await service.loadText(
          sources: [],
          remotePath: 'assets/games/cabo/docs/rules.md',
        ),
        'new rules',
      );
    },
  );
  test(
    'invalid changed edition never advances memory or the persisted watermark',
    () async {
      await service.loadCatalog();
      fixture.put('cabo', bump: true);
      fixture.editions['cabo']!['locales'] = {};
      await expectLater(service.refreshCatalog(), throwsFormatException);
      expect(service.catalog!.revision, 1);
      service.dispose();
      service = RemoteAssetService(
        cacheDirectory: directory,
        serviceOrigin: () => origin,
      );
      await service.restoreCatalog();
      expect(service.catalog!.revision, 1);
    },
  );
  test(
    'late responses from a previous origin cannot replace the new scope',
    () async {
      fixture.gate = Completer<void>();
      final read = service.loadCatalog();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      origin = Uri.parse('https://different.test');
      expect(service.catalog, isNull);
      fixture.gate!.complete();
      await expectLater(read, throwsStateError);
      expect(service.catalog, isNull);
    },
  );
  test(
    'browser remaps same-origin content paths and checks a PDF using HEAD only',
    () async {
      service.dispose();
      fixture = CatalogHttpFixture();
      service = RemoteAssetService(
        client: fixture.client,
        browser: true,
        serviceOrigin: () => origin,
      );
      await service.loadCatalog();
      fixture.requests.clear();
      final pdf = await service.ensureCached(
        sources: [],
        remotePath: 'assets/games/cabo/docs/rules.pdf',
      );
      expect(
        pdf!.localPath,
        contains(
          '/api/v1/apps/board_game_agent/catalog/resources/cabo-pdf/content',
        ),
      );
      expect(fixture.requests.single.method, 'HEAD');
    },
  );
  test(
    'request deadline cancels metadata reads and does not publish a late snapshot',
    () async {
      service.dispose();
      fixture = CatalogHttpFixture()..gate = Completer<void>();
      service = RemoteAssetService(
        client: fixture.client,
        cacheDirectory: directory,
        serviceOrigin: () => origin,
        requestTimeout: const Duration(milliseconds: 10),
      );
      await expectLater(
        service.loadCatalog(),
        throwsA(isA<TimeoutException>()),
      );
      fixture.gate!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(service.catalog, isNull);
    },
  );
  test(
    'an HTTP error cannot masquerade as an empty published catalog',
    () async {
      service.dispose();
      service = RemoteAssetService(
        cacheDirectory: directory,
        serviceOrigin: () => origin,
        client: MockClient((r) async => http.Response('', 503)),
      );
      await expectLater(service.loadCatalog(), throwsStateError);
      expect(service.catalog, isNull);
    },
  );
}
