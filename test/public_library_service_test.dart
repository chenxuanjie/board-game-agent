import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:board_game_agent/features/library/services/remote_asset_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http/testing.dart';
import 'support/catalog_http_fixture.dart';

// Bypass only Flutter's test HTTP stub for the loopback transport regression.
class _NativeHttpOverrides extends HttpOverrides {}

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
    'native HTTP cancellation closes a stalled resource read without closing the client',
    () async {
      service.dispose();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final started = Completer<void>(), finish = Completer<void>();
      addTearDown(() async {
        if (!finish.isCompleted) finish.complete();
        await server.close(force: true);
      });
      origin = Uri.parse('http://127.0.0.1:${server.port}');
      server.listen((request) async {
        try {
          if (request.uri.path.endsWith('/cabo-rules/content')) {
            request.response.bufferOutput = false;
            request.response.write('ru');
            await request.response.flush();
            started.complete();
            await finish.future;
            request.response.write('les');
          } else {
            final response = await fixture.handle(
              http.Request(request.method, request.requestedUri),
            );
            request.response.statusCode = response.statusCode;
            request.response.add(response.bodyBytes);
          }
          await request.response.close();
        } catch (_) {
          // The cancelled request's socket is expected to close during shutdown.
        }
      });
      service = RemoteAssetService(
        client: IOClient(_NativeHttpOverrides().createHttpClient(null)),
        cacheDirectory: directory,
        serviceOrigin: () => origin,
      );
      await service.loadCatalog();
      final abort = Completer<void>();
      final reading = service.loadBytes(
        sources: [],
        remotePath: 'assets/games/cabo/docs/rules.md',
        maxBytes: 100,
        abortTrigger: abort.future,
      );
      final assertion = expectLater(reading, throwsA(isA<TimeoutException>()));
      await started.future.timeout(const Duration(seconds: 2));
      abort.complete();
      await assertion.timeout(const Duration(seconds: 2));
      await service
          .drainReadConsumer(abort.future)
          .timeout(const Duration(seconds: 2));
      expect(await service.refreshCatalog(), isFalse);
      expect(
        directory
            .listSync(recursive: true)
            .where((file) => file.path.endsWith('.knowledge')),
        isEmpty,
      );
    },
  );
  test(
    'cancelling one AI read leaves the viewer transfer and shared client usable',
    () async {
      service.dispose();
      final streams = <StreamController<List<int>>>[];
      final cancelled = <Completer<void>>[];
      final aborted = <bool>[];
      final releaseAiCleanup = Completer<void>();
      final transport = MockClient.streaming((request, _) async {
        if (request.url.path.endsWith('/cabo-rules/content')) {
          final index = streams.length;
          final stopped = Completer<void>();
          final body = StreamController<List<int>>(
            onCancel: () {
              if (!stopped.isCompleted) stopped.complete();
              return index == 0 ? releaseAiCleanup.future : null;
            },
          );
          streams.add(body);
          cancelled.add(stopped);
          aborted.add(false);
          (request as http.Abortable).abortTrigger!.then(
            (_) => aborted[index] = true,
          );
          return http.StreamedResponse(body.stream, 200);
        }
        final result = await fixture.handle(
          http.Request(request.method, request.url),
        );
        return http.StreamedResponse(
          Stream.value(result.bodyBytes),
          result.statusCode,
          headers: result.headers,
        );
      });
      service = RemoteAssetService(
        client: transport,
        cacheDirectory: directory,
        serviceOrigin: () => origin,
      );
      await service.loadCatalog();
      final stop = Completer<void>();
      final reading = service.loadBytes(
        sources: [],
        remotePath: 'assets/games/cabo/docs/rules.md',
        maxBytes: 100,
        abortTrigger: stop.future,
      );
      final assertion = expectLater(reading, throwsA(isA<TimeoutException>()));
      Future<void> waitStreams(int count) async {
        final elapsed = Stopwatch()..start();
        while (streams.length < count) {
          if (elapsed.elapsed > const Duration(seconds: 3)) {
            fail('Missing request');
          }
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      }

      await waitStreams(1);
      final viewer = service.ensureCached(
        sources: [],
        remotePath: 'assets/games/cabo/docs/rules.md',
      );
      await waitStreams(2);
      stop.complete();
      await cancelled[0].future.timeout(const Duration(seconds: 1));
      var drained = false;
      final cleanup = service
          .drainReadConsumer(stop.future)
          .then((_) => drained = true);
      await Future<void>.delayed(Duration.zero);
      expect(drained, isFalse);
      releaseAiCleanup.complete();
      await assertion;
      await cleanup.timeout(const Duration(seconds: 1));
      expect(aborted[0], isTrue);
      expect(aborted[1], isFalse);
      streams[1].add(utf8.encode('rules'));
      await streams[1].close();
      final cached = await viewer;
      expect(await File(cached!.localPath).readAsString(), 'rules');
      // Cancelling AI did not close the common client or the viewer request.
      expect(await service.refreshCatalog(), isFalse);
      expect(
        directory
            .listSync(recursive: true)
            .where(
              (f) =>
                  f.path.endsWith('.knowledge') || f.path.endsWith('.download'),
            ),
        isEmpty,
      );
      await streams[0].close();
    },
  );

  for (final concurrentHeaders in [false, true]) {
    test(
      'cancellation releases unclaimed headers (concurrent=$concurrentHeaders)',
      () async {
        service.dispose();
        final header = Completer<http.StreamedResponse>(),
            started = Completer<void>(),
            cancelled = Completer<void>();
        final body = StreamController<List<int>>(
          onCancel: () => cancelled.complete(),
        );
        service = RemoteAssetService(
          client: MockClient.streaming((request, _) async {
            if (request.url.path.endsWith('/cabo-rules/content')) {
              started.complete();
              return header
                  .future; // deliberately ignores the transport abort signal
            }
            final result = await fixture.handle(
              http.Request(request.method, request.url),
            );
            return http.StreamedResponse(
              Stream.value(result.bodyBytes),
              result.statusCode,
              headers: result.headers,
            );
          }),
          cacheDirectory: directory,
          serviceOrigin: () => origin,
        );
        await service.loadCatalog();
        final abort = Completer<void>();
        final reading = service.loadBytes(
          sources: [],
          remotePath: 'assets/games/cabo/docs/rules.md',
          maxBytes: 100,
          abortTrigger: abort.future,
        );
        final assertion = expectLater(
          reading,
          throwsA(isA<TimeoutException>()),
        );
        await started.future;
        if (concurrentHeaders) {
          header.complete(http.StreamedResponse(body.stream, 200));
        }
        abort.complete();
        await assertion.timeout(const Duration(seconds: 1));
        if (!concurrentHeaders) {
          header.complete(http.StreamedResponse(body.stream, 200));
        }
        await cancelled.future.timeout(const Duration(seconds: 1));
        await body.close();
      },
    );
  }
  test(
    'bounded AI reads reject oversized whole files and reuse verified native cache',
    () async {
      await service.loadCatalog();
      await expectLater(
        service.loadBytes(
          sources: [],
          remotePath: 'assets/games/cabo/docs/rules.md',
          maxBytes: 4,
          timeout: const Duration(seconds: 1),
        ),
        throwsStateError,
      );
      expect(
        utf8.decode(
          (await service.loadBytes(
            sources: [],
            remotePath: 'assets/games/cabo/docs/rules.md',
            maxBytes: 8,
            timeout: const Duration(seconds: 1),
          ))!,
        ),
        'rules',
      );
      fixture.offline = true;
      expect(
        utf8.decode(
          (await service.loadBytes(
            sources: [],
            remotePath: 'assets/games/cabo/docs/rules.md',
            maxBytes: 8,
            timeout: const Duration(seconds: 1),
          ))!,
        ),
        'rules',
      );
      expect(
        directory
            .listSync(recursive: true)
            .where((file) => file.path.endsWith('.knowledge')),
        isEmpty,
      );
    },
  );

  test(
    'browser AI reads use versioned same-origin resource bytes with a bound',
    () async {
      service.dispose();
      service = RemoteAssetService(
        client: fixture.client,
        cacheDirectory: directory,
        browser: true,
        serviceOrigin: () => origin,
      );
      await service.loadCatalog();
      fixture.requests.clear();
      final bytes = await service.loadBytes(
        sources: [],
        remotePath: 'assets/games/cabo/docs/rules.md',
        maxBytes: 20,
        timeout: const Duration(seconds: 1),
      );
      expect(utf8.decode(bytes!), 'rules');
      expect(
        fixture.requests.single.url.path,
        '/api/v1/apps/board_game_agent/catalog/resources/cabo-rules/content',
      );
      expect(
        fixture.requests.single.url.queryParameters['version'],
        service.catalog!.files['assets/games/cabo/docs/rules.md']!.sha256,
      );
    },
  );

  for (final cancelExplicitly in [false, true]) {
    test(
      'bounded input read aborts the underlying HTTP body (explicit=$cancelExplicitly)',
      () async {
        service.dispose();
        final started = Completer<void>(), aborted = Completer<void>();
        final stop = Completer<void>();
        final body = StreamController<List<int>>();
        final client = MockClient.streaming((request, _) async {
          if (request.url.path.endsWith('/cabo-rules/content')) {
            expect(request, isA<http.Abortable>());
            (request as http.Abortable).abortTrigger!.then((_) {
              if (!aborted.isCompleted) aborted.complete();
              if (!body.isClosed) unawaited(body.close());
            });
            started.complete();
            return http.StreamedResponse(body.stream, 200);
          }
          final response = await fixture.handle(
            http.Request(request.method, request.url),
          );
          return http.StreamedResponse(
            Stream.value(response.bodyBytes),
            response.statusCode,
            headers: response.headers,
          );
        });
        service = RemoteAssetService(
          client: client,
          cacheDirectory: directory,
          serviceOrigin: () => origin,
        );
        await service.loadCatalog();
        final read = service.loadBytes(
          sources: [],
          remotePath: 'assets/games/cabo/docs/rules.md',
          maxBytes: 20,
          timeout: Duration(milliseconds: cancelExplicitly ? 1000 : 150),
          abortTrigger: stop.future,
        );
        final assertion = expectLater(read, throwsA(isA<TimeoutException>()));
        await started.future;
        if (cancelExplicitly) stop.complete();
        await assertion;
        await aborted.future;
        expect(
          await service.cachedFileFor('assets/games/cabo/docs/rules.md'),
          isNull,
        );
      },
    );
  }
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
