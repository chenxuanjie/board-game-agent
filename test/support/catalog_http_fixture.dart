import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'catalog_fixture.dart';

class CatalogHttpFixture {
  CatalogHttpFixture() {
    put('cabo');
  }
  int revision = 1;
  bool offline = false, corrupt = false;
  int pageSize = 200;
  Completer<void>? gate;
  final editions = <String, Map<String, dynamic>>{};
  final contents = <String, List<int>>{};
  final requests = <http.Request>[];
  final changes = <Map<String, dynamic>>[];
  void put(
    String id, {
    String? title,
    String text = 'rules',
    bool bump = false,
  }) {
    if (bump) revision++;
    final game = {
      'id': id,
      'slug': id,
      'score': '8.2',
      'supportedPlayers': [2, 3],
      'recommendedPlayer': 2,
      'coverAsset': 'images/cover.jpg',
      'locales': {
        'zhHans': {'title': title ?? id},
        'en': {'title': title ?? id},
      },
    };
    final value = catalogEditionFixture(
      game,
      resourceManifest: {
        'resources': [
          {
            'id': '$id-cover',
            'path': 'images/cover.jpg',
            'documentType': 'cover',
            'enabled': true,
            'status': 'available',
          },
          {
            'id': '$id-rules',
            'path': 'docs/rules.md',
            'documentType': 'rulebook',
            'language': 'cn',
            'aiEnabled': true,
            'enabled': true,
            'status': 'available',
          },
          {
            'id': '$id-pdf',
            'path': 'docs/rules.pdf',
            'documentType': 'rulebook',
            'enabled': true,
            'status': 'available',
          },
        ],
      },
    );
    contents['$id-cover'] = [0xff, 0xd8, 0xff, 1];
    contents['$id-rules'] = utf8.encode(text);
    contents['$id-pdf'] = utf8.encode('%PDF-$text');
    for (final r in value['resources'] as List) {
      final rid = r['id'] as String;
      final digest = sha256.convert(contents[rid]!).toString();
      r['file_sha256'] = digest;
      r['content_url'] =
          '/v1/apps/board_game_agent/catalog/resources/$rid/content?version=$digest';
    }
    editions[id] = value;
    changes.add({'revision': revision, 'edition_id': id, 'kind': 'upsert'});
  }

  void remove(String id) {
    revision++;
    editions.remove(id);
    changes.add({'revision': revision, 'edition_id': id, 'kind': 'unpublish'});
  }

  late final client = MockClient(handle);
  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    await gate?.future;
    if (offline) return http.Response('', 503);
    final path = request.url.path.replaceFirst('/api/', '/');
    final prefix = '/v1/apps/board_game_agent/catalog';
    http.Response json(Object value) => http.Response(
      jsonEncode(value),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
    if (path == '$prefix/revision') {
      return json({'protocol': 1, 'revision': revision});
    }
    if (path == prefix || path == '$prefix/changes') {
      final after = int.parse(request.url.queryParameters['after'] ?? '0');
      final data = path == prefix
          ? [
              for (final id in editions.keys) {'id': id},
            ]
          : changes.where((c) => (c['revision'] as int) > after).toList();
      final offset = int.parse(request.url.queryParameters['cursor'] ?? '0');
      final next = offset + pageSize < data.length
          ? '${offset + pageSize}'
          : null;
      return json({
        'protocol': 1,
        'revision': revision,
        'items': data.skip(offset).take(pageSize).toList(),
        'next_cursor': next,
        'through_revision': next == null ? revision : after,
      });
    }
    if (path.contains('/editions/')) {
      final edition = editions[request.url.pathSegments.last];
      return edition == null
          ? http.Response('', 404)
          : json({'protocol': 1, 'revision': revision, 'edition': edition});
    }
    if (path.contains('/resources/') && path.endsWith('/content')) {
      final id = request.url.pathSegments[request.url.pathSegments.length - 2];
      final data = contents[id];
      if (data == null) return http.Response('', 404);
      if (request.method == 'HEAD') return http.Response('', 200);
      return http.Response.bytes(corrupt ? [0, 1, 2] : data, 200);
    }
    return http.Response('', 404);
  }
}
