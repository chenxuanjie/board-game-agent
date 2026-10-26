import 'dart:convert';
import 'dart:io';
import 'package:board_game_agent/features/library/services/remote_asset_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'guest API reads verify publication and hash, preserve cache on failure, and isolate origins',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'board-public-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      var origin = Uri.parse('https://api.test'), body = '{"games": []}';
      var fail = false, corrupt = false;
      final requests = <http.Request>[];
      final client = MockClient((r) async {
        requests.add(r);
        expect(r.headers.containsKey('Authorization'), isFalse);
        expect(r.headers.containsKey('Cookie'), isFalse);
        if (fail) return http.Response('', 503);
        if (r.url.path.endsWith('/library')) {
          return http.Response(
            jsonEncode({
              'version': 1,
              'files': {
                'assets/catalog.json': {
                  'size': utf8.encode(body).length,
                  'sha256': sha256.convert(utf8.encode(body)).toString(),
                },
              },
            }),
            200,
          );
        }
        expect(
          r.url.path,
          '/v1/apps/board_game_agent/library/files/assets/catalog.json',
        );
        return http.Response(corrupt ? 'x' * body.length : body, 200);
      });
      addTearDown(client.close);
      final service = RemoteAssetService(
        client: client,
        cacheDirectory: directory,
        serviceOrigin: () => origin,
      );
      expect(
        await Future.wait([
          service.loadText(sources: [], remotePath: 'assets/catalog.json'),
          service.loadText(sources: [], remotePath: 'assets/catalog.json'),
        ]),
        [body, body],
      );
      expect(requests.where((r) => r.url.path.contains('/files/')).length, 1);
      corrupt = true;
      await expectLater(
        service.ensureCached(
          sources: [],
          remotePath: 'assets/catalog.json',
          forceRefresh: true,
          allowCachedFallback: false,
        ),
        throwsStateError,
      );
      expect(
        utf8.decode((await service.cachedBytesFor('assets/catalog.json'))!),
        body,
      );
      corrupt = false;
      fail = true;
      expect(
        await service.loadText(sources: [], remotePath: 'assets/catalog.json'),
        body,
      );
      fail = false;
      body = '{"games": [{"slug":"cabo"}]}';
      await service.refreshPublishedLibrary();
      expect(
        await service.loadText(sources: [], remotePath: 'assets/catalog.json'),
        body,
      );
      origin = Uri.parse('https://other.test');
      expect(await service.cachedBytesFor('assets/catalog.json'), isNull);
      expect(service.resourceUri('assets/../secret'), isNull);
      expect(service.resourceUri('https://other.test/secret'), isNull);
      expect(requests.every((r) => !r.url.path.contains('/webapi/')), isTrue);
    },
  );
  test(
    'browser uses API prefix; document availability never downloads its body twice',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((r) async {
        requests.add(r);
        return http.Response('', 200);
      });
      addTearDown(client.close);
      final service = RemoteAssetService(
        client: client,
        browser: true,
        serviceOrigin: () => Uri.parse('https://web.test'),
      );
      final file = await service.ensureCached(
        sources: [],
        remotePath: 'assets/games/cabo/docs/rules.pdf',
      );
      expect(file, isNotNull);
      expect(requests.single.method, 'HEAD');
      expect(
        requests.single.url.path,
        '/api/v1/apps/board_game_agent/library/files/assets/games/cabo/docs/rules.pdf',
      );
    },
  );
}
