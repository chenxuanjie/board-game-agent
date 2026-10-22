import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../core/models/connectivity_status.dart';
import '../models/asset_source_config.dart';
import '../models/cached_asset.dart';
import '../models/remote_asset_file.dart';
import 'remote_asset_service.dart';

/// Web's transport is same-origin HTTP with an HttpOnly session cookie. It has
/// no WebDAV credentials, filesystem cache, or shared browser CacheStorage.
final class SameOriginLibraryService extends RemoteAssetService {
  SameOriginLibraryService({
    required String? Function() accountScope,
    required super.accessAllowed,
    super.requestTimeout = const Duration(seconds: 20),
    http.Client? client,
    Uri? site,
    this.maxCacheBytes = 8 * 1024 * 1024,
  }) : _scopeProvider = accountScope,
       _http = client ?? http.Client(),
       _site = site ?? Uri.base;

  final String? Function() _scopeProvider;
  final http.Client _http;
  final Uri _site;
  final int maxCacheBytes;
  String? _scope;
  final _bodies = <String, http.Response>{};
  final _versions = <String, String>{};
  Map<String, String> _publishedVersions = {};
  String? _catalog;
  final _pending = <String, Future<http.Response>>{};
  final _aborts = <Completer<void>>{};
  int _bytes = 0;
  int _generation = 0;
  int _contentRevision = 0;

  @override
  bool get usesSameOriginLibrary => true;

  String? _activeScope() {
    final scope = accessAllowed ? _scopeProvider() : null;
    if (scope != _scope) {
      _scope = scope;
      clearAccountCache();
    }
    return scope;
  }

  @override
  void clearAccountCache() {
    _generation++;
    _bodies.clear();
    _versions.clear();
    _publishedVersions = {};
    _catalog = null;
    _pending.clear();
    _bytes = 0;
    for (final abort in _aborts) {
      if (!abort.isCompleted) abort.complete();
    }
    _aborts.clear();
  }

  static bool validPath(String path) =>
      path.length <= 1024 &&
      path.startsWith('assets/') &&
      !path.toLowerCase().contains('docs/others') &&
      !RegExp(r'[\\%?#:\x00-\x1f]').hasMatch(path) &&
      !path.split('/').any((p) => p.isEmpty || p.startsWith('.'));

  @override
  Uri? resourceUri(String path) {
    final scope = _activeScope();
    if (scope == null || !validPath(path)) return null;
    return _site.replace(
      path: '/library/$path',
      queryParameters: {
        'account': scope,
        'revision': '$_generation.$_contentRevision',
        'v': ?(_publishedVersions[path] ?? _versions[path]),
      },
      fragment: '',
    );
  }

  Future<http.Response> _get(String path, {String method = 'GET'}) {
    final scope = _activeScope();
    final generation = _generation;
    final uri = resourceUri(path);
    if (scope == null || uri == null) {
      return Future.value(http.Response('', 401));
    }
    final key = '$generation|$scope|$method|$path';
    return _pending.putIfAbsent(key, () async {
      final abort = Completer<void>();
      _aborts.add(abort);
      final cached = _bodies[path];
      final request = http.AbortableRequest(
        method,
        uri,
        abortTrigger: abort.future,
      )..headers['X-Board-Game-Request'] = '1';
      if (method == 'GET' && cached?.headers['etag'] != null) {
        request.headers['If-None-Match'] = cached!.headers['etag']!;
      }
      try {
        final response = await (() async {
          final stream = await _http.send(request);
          final bytes = <int>[];
          await for (final chunk in stream.stream) {
            if (bytes.length + chunk.length > 64 * 1024 * 1024) {
              throw const FormatException('Resource exceeds download limit');
            }
            bytes.addAll(chunk);
          }
          return http.Response.bytes(
            bytes,
            stream.statusCode,
            headers: stream.headers,
          );
        })().timeout(requestTimeout);
        if (_activeScope() != scope || generation != _generation) {
          return http.Response('', 401);
        }
        if (response.statusCode == 304 && cached != null) return cached;
        if (response.statusCode == 200) {
          _versions[path] =
              response.headers['etag'] ??
              '${response.headers['last-modified']}|${response.headers['content-length']}';
          while (_versions.length > 4096) {
            _versions.remove(_versions.keys.first);
          }
          // Large documents and images stay in the HTTP cache. Only small
          // metadata/text is retained in bounded, account-scoped memory.
          if (method == 'GET' &&
              RegExp(r'\.(json|md|txt)$').hasMatch(path) &&
              response.bodyBytes.length <= maxCacheBytes) {
            _bytes -= _bodies.remove(path)?.bodyBytes.length ?? 0;
            _bodies[path] = response;
            _bytes += response.bodyBytes.length;
            while (_bytes > maxCacheBytes && _bodies.isNotEmpty) {
              _bytes -= _bodies.remove(_bodies.keys.first)!.bodyBytes.length;
            }
          }
        }
        return response;
      } finally {
        if (!abort.isCompleted) abort.complete();
        _aborts.remove(abort);
        _pending.remove(key);
      }
    });
  }

  @override
  Future<ConnectivityStatus> checkAccess(
    AssetSourceConfig source, {
    Completer<void>? abort,
    void Function(String)? onCatalog,
  }) async {
    try {
      final result = await _get('assets/catalog.json');
      if (abort?.isCompleted == true) throw StateError('Cancelled');
      if (result.statusCode != 200 ||
          jsonDecode(result.body)['games'] is! List) {
        throw StateError('Catalog unavailable');
      }
      onCatalog?.call(result.body);
      return ConnectivityStatus(
        state: ConnectivityState.success,
        message: '知识库可读取',
        checkedAt: DateTime.now(),
      );
    } catch (_) {
      return ConnectivityStatus(
        state: ConnectivityState.failure,
        message: '资料服务不可用',
        checkedAt: DateTime.now(),
      );
    }
  }

  @override
  Future<List<int>?> fetchRemoteBytes({
    required List<AssetSourceConfig> sources,
    required String remotePath,
  }) async {
    final result = await _get(remotePath);
    return result.statusCode == 200 ? result.bodyBytes : null;
  }

  @override
  Future<String?> fetchRemoteText({
    required List<AssetSourceConfig> sources,
    required String remotePath,
  }) async {
    final bytes = await fetchRemoteBytes(
      sources: sources,
      remotePath: remotePath,
    );
    return bytes == null ? null : utf8.decode(bytes);
  }

  @override
  Future<String?> loadText({
    required List<AssetSourceConfig> sources,
    required String remotePath,
  }) => fetchRemoteText(sources: sources, remotePath: remotePath);
  @override
  Future<List<int>?> loadBytes({
    required List<AssetSourceConfig> sources,
    required String remotePath,
  }) => fetchRemoteBytes(sources: sources, remotePath: remotePath);
  @override
  Future<Uint8List?> cachedBytesFor(String remotePath) async {
    if (_activeScope() == null) return null;
    return _bodies[remotePath]?.bodyBytes;
  }

  @override
  Future<String?> loadCachedOrBundledText({required String remotePath}) async {
    final bytes = await cachedBytesFor(remotePath);
    return bytes == null ? null : utf8.decode(bytes);
  }

  @override
  Future<CachedAsset?> ensureCached({
    required List<AssetSourceConfig> sources,
    required String remotePath,
    bool forceRefresh = false,
    bool allowCachedFallback = true,
  }) async {
    final response = await _get(remotePath, method: 'HEAD');
    if (response.statusCode != 200) return null;
    return CachedAsset(
      remotePath: remotePath,
      localPath: resourceUri(remotePath)!.toString(),
      exists: true,
      fromRemote: true,
      sourceId: 'same_origin',
    );
  }

  @override
  Future<bool> hasRemoteChanged({
    required List<AssetSourceConfig> sources,
    required String remotePath,
  }) async {
    final before = _versions[remotePath];
    final result = await _get(remotePath, method: 'HEAD');
    if (result.statusCode != 200) {
      throw StateError('Resource verification failed');
    }
    return before != null && before != _versions[remotePath];
  }

  @override
  Future<void> prefetchGameImages({
    required List<AssetSourceConfig> sources,
    required Iterable<String> remotePaths,
  }) async {}
  Future<http.Response> _metadata(
    String endpoint,
    Map<String, String> query,
  ) async {
    final scope = _activeScope();
    final generation = _generation;
    if (scope == null) throw StateError('Sign in first');
    final uri = _site
        .resolve('/api/library/$endpoint')
        .replace(queryParameters: query);
    final abort = Completer<void>();
    _aborts.add(abort);
    late http.Response response;
    try {
      response = await (() async {
        final request = http.AbortableRequest(
          'GET',
          uri,
          abortTrigger: abort.future,
        )..headers['X-Board-Game-Request'] = '1';
        final stream = await _http.send(request);
        final bytes = <int>[];
        await for (final chunk in stream.stream) {
          if (bytes.length + chunk.length > 8 * 1024 * 1024) {
            throw const FormatException('Metadata exceeds limit');
          }
          bytes.addAll(chunk);
        }
        return http.Response.bytes(
          bytes,
          stream.statusCode,
          headers: stream.headers,
        );
      })().timeout(requestTimeout);
    } finally {
      if (!abort.isCompleted) abort.complete();
      _aborts.remove(abort);
    }
    if (scope != _activeScope() ||
        generation != _generation ||
        response.statusCode != 200 ||
        response.bodyBytes.length > 8 * 1024 * 1024) {
      throw StateError('Library metadata unavailable');
    }
    return response;
  }

  @override
  Future<bool> refreshPublishedLibrary({
    bool complete = false,
    String? checkedCatalog,
  }) async {
    final scope = _activeScope();
    final generation = _generation;
    if (scope == null) throw StateError('Sign in first');
    final response = checkedCatalog == null
        ? await _get('assets/catalog.json')
        : http.Response(checkedCatalog, 200);
    if (response.statusCode != 200 ||
        jsonDecode(response.body)['games'] is! List) {
      throw StateError('Catalog unavailable');
    }
    var changed = _catalog != response.body;
    if (complete) {
      final metadata = await _metadata('versions', {});
      final next = <String, String>{};
      for (final file in jsonDecode(metadata.body)['files'] as List) {
        final path = file['path'] as String;
        if (!validPath(path) || file['exists'] != true) {
          throw StateError('Published file missing');
        }
        next[path] = file['version'] as String;
        if (_publishedVersions[path] != next[path]) {
          changed = true;
          _bytes -= _bodies.remove(path)?.bodyBytes.length ?? 0;
        }
      }
      if (scope != _activeScope() || generation != _generation) {
        throw StateError('Account changed');
      }
      if (next.length != _publishedVersions.length ||
          _publishedVersions.keys.any((path) => !next.containsKey(path))) {
        changed = true;
        for (final removed in _publishedVersions.keys.where(
          (path) => !next.containsKey(path),
        )) {
          _bytes -= _bodies.remove(removed)?.bodyBytes.length ?? 0;
        }
      }
      _publishedVersions = next;
    }
    if (scope != _activeScope() || generation != _generation) {
      throw StateError('Account changed');
    }
    _catalog = response.body;
    if (changed) _contentRevision++;
    return changed;
  }

  @override
  Future<List<RemoteAssetFile>> listFilesRecursively({
    required List<AssetSourceConfig> sources,
    required String remotePath,
    int maxDepth = 6,
    int maxEntries = 1000,
  }) async {
    final scope = _activeScope();
    if (scope == null) throw StateError('Sign in first');
    final response = await _metadata('files', {
      'path': remotePath,
      'depth': '$maxDepth',
      'limit': '$maxEntries',
    });
    if (scope != _activeScope() ||
        response.statusCode != 200 ||
        response.bodyBytes.length > 2 * 1024 * 1024) {
      throw StateError('Library listing unavailable');
    }
    return List<RemoteAssetFile>.unmodifiable(
      (jsonDecode(response.body)['files'] as List).map((value) {
        final path = value['path'] as String;
        if (!validPath(path) || !path.startsWith('$remotePath/')) {
          throw const FormatException('Invalid listing path');
        }
        return RemoteAssetFile(
          remotePath: path,
          name: value['name'] as String,
          sourceId: 'same_origin',
          etag: value['etag'] as String?,
        );
      }),
    );
  }
}
