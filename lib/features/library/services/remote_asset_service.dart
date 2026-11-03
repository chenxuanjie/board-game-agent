import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
// ignore: implementation_imports
import 'package:app_ai_client/src/default_http_client.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/models/connectivity_status.dart';
import '../models/asset_source_config.dart';
import '../models/cached_asset.dart';
import '../models/game_resource.dart';
import '../models/published_catalog.dart';
import '../models/remote_asset_file.dart';
import 'browser_asset_cache_stub.dart'
    if (dart.library.js_interop) 'browser_asset_cache_web.dart';

/// Anonymous SQL publications and content-addressed, origin-scoped caches.
/// Account credentials and legacy JSON manifests never enter this transport.
class RemoteAssetService {
  static const _snapshotMaxBytes = 16 * 1024 * 1024;
  RemoteAssetService({
    http.Client? client,
    Uri? Function()? serviceOrigin,
    this.requestTimeout = const Duration(seconds: 20),
    this.browser = kIsWeb,
    this.cacheDirectory,
  }) : _client = client ?? createDefaultAiHttpClient(),
       _origin = serviceOrigin ?? (() => kIsWeb ? Uri.base : null);

  final http.Client _client;
  final Uri? Function() _origin;
  final bool browser;
  final Directory? cacheDirectory;
  final Duration requestTimeout;
  final _active = <Completer<void>>{};
  final _pending = <String, Future<Uint8List?>>{};
  final _downloads = <String, Future<void>>{};
  String? _scope;
  PublishedCatalog? _catalog;
  Future<void>? _restoreTask;
  Future<bool>? _catalogTask;
  bool _closed = false;
  int _sequence = 0;

  bool get usesPublishedLibrary => _origin() != null;
  bool get accessAllowed => true;
  Uri? get serviceOrigin => _currentOrigin();
  PublishedCatalog? get catalog => _currentOrigin() == null ? null : _catalog;

  Uri? _currentOrigin() {
    if (_closed) return null;
    final value = _origin();
    final next = value?.origin;
    if (_scope != next) {
      for (final abort in _active.toList()) {
        if (!abort.isCompleted) abort.complete();
      }
      _scope = next;
      _catalog = null;
      _restoreTask = null;
      _catalogTask = null;
    }
    return value == null ? null : Uri.parse(value.origin);
  }

  Uri _base(Uri origin) => origin.resolve(
    '${browser ? '/api' : ''}/v1/apps/board_game_agent/catalog',
  );
  String _prefix(Uri origin) =>
      'board-catalog-v1/${sha256.convert(utf8.encode(origin.origin))}';
  String _objectKey(Uri origin, GameResource resource) =>
      '${_prefix(origin)}/objects/${resource.sha256}.${resource.format}';
  bool _current(Uri origin) => _currentOrigin()?.origin == origin.origin;
  bool _sameResource(Uri origin, String path, GameResource resource) =>
      _current(origin) && _catalog?.files[path]?.sha256 == resource.sha256;

  void dispose() {
    _closed = true;
    for (final abort in _active.toList()) {
      if (!abort.isCompleted) abort.complete();
    }
    _client.close();
  }

  static bool validPath(String path) => validCatalogPath(path);

  Uri? resourceUri(String path) {
    final origin = _currentOrigin();
    final resource = _catalog?.files[path];
    if (origin == null || resource == null || !validPath(path)) return null;
    return origin.resolve('${browser ? '/api' : ''}${resource.contentUrl!}');
  }

  Future<http.Response> _request(
    Uri uri, {
    String method = 'GET',
    Completer<void>? abort,
    int maxBytes = 4 * 1024 * 1024,
  }) async {
    if (_closed || abort?.isCompleted == true) {
      throw StateError('Request cancelled');
    }
    final cancellation = Completer<void>();
    _active.add(cancellation);
    abort?.future.then((_) {
      if (!cancellation.isCompleted) cancellation.complete();
    });
    final request = http.AbortableRequest(
      method,
      uri,
      abortTrigger: cancellation.future,
    )..followRedirects = false;
    try {
      return await (() async {
        final stream = await _client.send(request);
        final body = BytesBuilder(copy: false);
        await for (final bytes in stream.stream) {
          if (body.length + bytes.length > maxBytes) {
            throw StateError('request_too_large');
          }
          body.add(bytes);
        }
        if (cancellation.isCompleted) throw StateError('Request cancelled');
        return http.Response.bytes(
          body.takeBytes(),
          stream.statusCode,
          headers: stream.headers,
        );
      })().timeout(requestTimeout);
    } finally {
      if (!cancellation.isCompleted) cancellation.complete();
      _active.remove(cancellation);
    }
  }

  Future<Map<String, dynamic>> _json(Uri uri, Completer<void> abort) async {
    final response = await _request(uri, abort: abort);
    if (response.statusCode == 409) throw const _CatalogChanged();
    if (response.statusCode != 200) throw StateError('公开资料服务暂不可用');
    final value = jsonDecode(utf8.decode(response.bodyBytes));
    if (value is! Map<String, dynamic> ||
        value['protocol'] != 1 ||
        value['revision'] is! int ||
        (value['revision'] as int) < 0) {
      throw const FormatException('Invalid catalog response');
    }
    return value;
  }

  Future<File> _file(String key) async {
    final directory = cacheDirectory ?? await getApplicationSupportDirectory();
    return File('${directory.path}/$key');
  }

  Future<Uint8List?> _read(String key) async {
    if (browser) return readBrowserAsset(key);
    final file = await _file(key);
    if (!await file.exists()) return null;
    if (await file.length() > _snapshotMaxBytes) {
      throw const FormatException('Catalog cache too large');
    }
    return file.readAsBytes();
  }

  Future<void> _write(String key, Uint8List bytes) async {
    if (browser) return writeBrowserAsset(key, bytes);
    final target = await _file(key);
    await target.parent.create(recursive: true);
    final staged = File(
      '${target.path}.${DateTime.now().microsecondsSinceEpoch}.${_sequence++}.tmp',
    );
    try {
      await staged.writeAsBytes(bytes, flush: true);
      await staged.rename(target.path);
    } finally {
      if (await staged.exists()) await staged.delete();
    }
  }

  Future<void> restoreCatalog() async {
    final origin = _currentOrigin();
    if (origin == null || _catalog != null) return;
    if (_restoreTask != null) return _restoreTask;
    final task = () async {
      try {
        final bytes = await _read('${_prefix(origin)}/snapshot.json');
        if (bytes == null) return;
        if (bytes.length > _snapshotMaxBytes) {
          throw const FormatException('Catalog cache too large');
        }
        final decoded = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        final restored = PublishedCatalog.fromJson(decoded);
        if (_current(origin) && _catalog == null) _catalog = restored;
      } on FileSystemException {
        debugPrint('[catalog] saved snapshot is unreadable');
      } on FormatException {
        /* A new network snapshot may replace invalid cache data. */
      } on TypeError {
        /* Never recover through the old bundled catalog. */
      }
    }();
    _restoreTask = task;
    try {
      await task;
    } finally {
      if (identical(_restoreTask, task)) _restoreTask = null;
    }
  }

  Future<PublishedCatalog> loadCatalog({bool refresh = false}) async {
    final origin = _currentOrigin();
    if (origin == null) throw StateError('请配置应用服务地址');
    await restoreCatalog();
    if (!_current(origin)) throw StateError('资料入口已变化');
    if (_catalog == null || refresh) await refreshCatalog();
    if (!_current(origin)) throw StateError('资料入口已变化');
    return _catalog!;
  }

  Future<bool> refreshCatalog({int? knownRevision}) {
    final origin = _currentOrigin();
    if (origin == null) return Future.error(StateError('请配置应用服务地址'));
    if (_catalogTask != null) return _catalogTask!;
    final task = () async {
      await restoreCatalog();
      final abort = Completer<void>();
      final timer = Timer(const Duration(seconds: 60), () {
        if (!abort.isCompleted) abort.complete();
      });
      try {
        for (var attempt = 0; attempt < 2; attempt++) {
          if (!_current(origin) || abort.isCompleted) {
            throw StateError('资料请求已取消');
          }
          try {
            final next = await _fetchCatalog(
              origin,
              abort,
              knownRevision: attempt == 0 ? knownRevision : null,
            );
            if (!_current(origin) || abort.isCompleted) {
              throw StateError('资料入口已变化');
            }
            if (identical(next, _catalog)) return false;
            try {
              await _write(
                '${_prefix(origin)}/snapshot.json',
                Uint8List.fromList(utf8.encode(jsonEncode(next.toJson()))),
              );
            } catch (error) {
              debugPrint('[catalog] cache write failed (${error.runtimeType})');
            }
            if (!_current(origin) || abort.isCompleted) {
              throw StateError('资料入口已变化');
            }
            _catalog = next;
            return true;
          } on _CatalogChanged {
            if (attempt == 1) rethrow;
          }
        }
        throw StateError('资料版本正在变化，请重试');
      } finally {
        timer.cancel();
        if (!abort.isCompleted) abort.complete();
      }
    }();
    _catalogTask = task;
    task
        .whenComplete(() {
          if (identical(_catalogTask, task)) _catalogTask = null;
        })
        .catchError((Object _) => false);
    return task;
  }

  Future<PublishedCatalog> _fetchCatalog(
    Uri origin,
    Completer<void> abort, {
    int? knownRevision,
  }) async {
    final base = _base(origin);
    final previous = _catalog;
    final target =
        knownRevision != null &&
            (previous == null || knownRevision >= previous.revision)
        ? knownRevision
        : (await _json(Uri.parse('$base/revision'), abort))['revision'] as int;
    if (previous?.revision == target) return previous!;
    if (previous != null && target < previous.revision) {
      throw const FormatException('Catalog revision moved backwards');
    }
    final editions = <String, Map<String, dynamic>>{...?previous?.editions};
    final wanted = <String>{};
    String? cursor;
    final cursors = <String>{};
    for (var page = 0; ; page++) {
      if (page >= 100 || abort.isCompleted) throw StateError('资料目录超过检查范围');
      final uri = (previous == null ? base : Uri.parse('$base/changes'))
          .replace(
            queryParameters: {
              'limit': '200',
              if (previous != null) 'after': '${previous.revision}',
              'cursor': ?cursor,
            },
          );
      final body = await _json(uri, abort);
      if (body['revision'] != target) throw const _CatalogChanged();
      for (final raw in body['items'] as List) {
        final item = (raw as Map).cast<String, dynamic>();
        final id = item[previous == null ? 'id' : 'edition_id'] as String;
        if (id.isEmpty || id.length > 256) {
          throw const FormatException('Invalid edition ID');
        }
        if (previous != null && item['kind'] == 'unpublish') {
          editions.remove(id);
          wanted.remove(id);
        } else if (previous == null || item['kind'] == 'upsert') {
          wanted.add(id);
        } else {
          throw const FormatException('Invalid catalog change');
        }
        if (wanted.length > 10000) {
          throw const FormatException('Catalog too large');
        }
      }
      cursor = body['next_cursor'] as String?;
      if (cursor == null) {
        if (previous != null && body['through_revision'] != target) {
          throw const FormatException('Incomplete catalog changes');
        }
        break;
      }
      if (!cursors.add(cursor)) {
        throw const FormatException('Repeated catalog cursor');
      }
    }
    var metadataBytes = utf8.encode(jsonEncode(editions)).length;
    final ids = wanted.toList();
    for (var start = 0; start < ids.length; start += 4) {
      final batch = await Future.wait(
        ids.skip(start).take(4).map((id) async {
          final uri = base.replace(
            pathSegments: [...base.pathSegments, 'editions', id],
          );
          final body = await _json(uri, abort);
          if (body['revision'] != target) throw const _CatalogChanged();
          final edition = (body['edition'] as Map).cast<String, dynamic>();
          if (edition['id'] != id) {
            throw const FormatException('Edition identity mismatch');
          }
          return MapEntry(id, edition);
        }),
      );
      for (final entry in batch) {
        metadataBytes += utf8.encode(jsonEncode(entry.value)).length;
        if (metadataBytes > _snapshotMaxBytes) {
          throw const FormatException('Catalog metadata budget exceeded');
        }
      }
      editions.addEntries(batch);
    }
    final end = await _json(Uri.parse('$base/revision'), abort);
    if (end['revision'] != target) throw const _CatalogChanged();
    return PublishedCatalog.fromJson({
      'protocol': 1,
      'revision': target,
      'editions': editions.values.toList(),
    });
  }

  Future<GameResource?> _record(String path) async {
    if (!validPath(path)) return null;
    if (catalog == null) await loadCatalog();
    return _catalog?.files[path];
  }

  Future<Uint8List?> _fetch(String path) async {
    final resource = await _record(path);
    final origin = _currentOrigin();
    final uri = resourceUri(path);
    if (resource == null || origin == null || uri == null) return null;
    final key = uri.toString();
    return _pending.putIfAbsent(key, () async {
      try {
        final response = await _request(uri, maxBytes: 64 * 1024 * 1024);
        if (response.statusCode != 200 ||
            sha256.convert(response.bodyBytes).toString() != resource.sha256 ||
            !_sameResource(origin, path, resource)) {
          throw StateError('资料完整性校验未通过');
        }
        return response.bodyBytes;
      } finally {
        _pending.remove(key);
      }
    });
  }

  Future<File?> cachedFileFor(String path) async {
    if (browser || !validPath(path)) return null;
    await restoreCatalog();
    final origin = _currentOrigin(), resource = _catalog?.files[path];
    if (origin == null || resource == null) return null;
    final file = await _file(_objectKey(origin, resource));
    if (!await file.exists() || await file.length() > 512 * 1024 * 1024) {
      return null;
    }
    if ((await sha256.bind(file.openRead()).first).toString() !=
            resource.sha256 ||
        !_sameResource(origin, path, resource)) {
      return null;
    }
    return file;
  }

  Future<Uint8List?> cachedBytesFor(String path) async {
    if (!validPath(path)) return null;
    await restoreCatalog();
    final origin = _currentOrigin(), resource = _catalog?.files[path];
    if (origin == null || resource == null) return null;
    if (browser) {
      final bytes = await readBrowserAsset(_objectKey(origin, resource));
      return bytes != null &&
              sha256.convert(bytes).toString() == resource.sha256 &&
              _sameResource(origin, path, resource)
          ? bytes
          : null;
    }
    final file = await cachedFileFor(path);
    if (file == null || await file.length() > 64 * 1024 * 1024) return null;
    return file.readAsBytes();
  }

  Future<void> _downloadNative(
    String path,
    Uri uri,
    GameResource resource,
    File target,
  ) async {
    final origin = Uri.parse(uri.origin);
    final staged = File('${target.path}.${_sequence++}.download');
    await target.parent.create(recursive: true);
    final abort = Completer<void>();
    _active.add(abort);
    final timer = Timer(const Duration(minutes: 5), () {
      if (!abort.isCompleted) abort.complete();
    });
    IOSink? sink;
    try {
      final response = await _client
          .send(
            http.AbortableRequest('GET', uri, abortTrigger: abort.future)
              ..followRedirects = false,
          )
          .timeout(requestTimeout);
      if (response.statusCode != 200) throw StateError('公开资料下载未完成');
      sink = staged.openWrite();
      var size = 0;
      await for (final chunk in response.stream) {
        size += chunk.length;
        if (size > 512 * 1024 * 1024 || abort.isCompleted) {
          throw StateError('公开资料下载未完成');
        }
        sink.add(chunk);
        await sink.flush();
      }
      await sink.close();
      sink = null;
      final digest = (await sha256.bind(staged.openRead()).first).toString();
      if (size == 0 ||
          (response.contentLength != null && size != response.contentLength) ||
          digest != resource.sha256 ||
          abort.isCompleted ||
          !_sameResource(origin, path, resource)) {
        throw StateError('资料完整性校验未通过，请重试');
      }
      await staged.rename(target.path);
    } finally {
      timer.cancel();
      if (!abort.isCompleted) abort.complete();
      _active.remove(abort);
      await sink?.close();
      if (await staged.exists()) await staged.delete();
    }
  }

  Future<CachedAsset?> ensureCached({
    required List<AssetSourceConfig> sources,
    required String remotePath,
    bool forceRefresh = false,
    bool allowCachedFallback = true,
  }) async {
    final resource = await _record(remotePath);
    final origin = _currentOrigin(), uri = resourceUri(remotePath);
    if (resource == null || origin == null || uri == null) return null;
    if (browser) {
      final response = await _request(uri, method: 'HEAD');
      if (response.statusCode != 200 ||
          !_sameResource(origin, remotePath, resource)) {
        return null;
      }
      return CachedAsset(
        remotePath: remotePath,
        localPath: uri.toString(),
        exists: true,
        fromRemote: true,
        sourceId: 'app_service',
      );
    }
    final cached = await cachedFileFor(remotePath);
    var downloaded = false;
    final target = await _file(_objectKey(origin, resource));
    if (cached == null || forceRefresh) {
      try {
        await _downloads.putIfAbsent(
          target.path,
          () => _downloadNative(remotePath, uri, resource, target).whenComplete(
            () {
              _downloads.remove(target.path);
            },
          ),
        );
        downloaded = true;
      } catch (_) {
        if (!allowCachedFallback || cached == null) rethrow;
      }
    }
    if (!_sameResource(origin, remotePath, resource)) return null;
    return CachedAsset(
      remotePath: remotePath,
      localPath: target.path,
      exists: true,
      fromRemote: downloaded,
      sourceId: 'app_service',
    );
  }

  Future<List<int>?> fetchRemoteBytes({
    required List<AssetSourceConfig> sources,
    required String remotePath,
  }) => _fetch(remotePath);
  Future<String?> fetchRemoteText({
    required List<AssetSourceConfig> sources,
    required String remotePath,
  }) async {
    final bytes = await _fetch(remotePath);
    return bytes == null ? null : utf8.decode(bytes);
  }

  Future<String?> loadCachedText({required String remotePath}) async {
    final bytes = await cachedBytesFor(remotePath);
    return bytes == null ? null : utf8.decode(bytes);
  }

  Future<List<int>?> loadBytes({
    required List<AssetSourceConfig> sources,
    required String remotePath,
    int maxBytes = 64 * 1024 * 1024,
    Duration? timeout,
    Future<void>? abortTrigger,
  }) async {
    if (maxBytes < 0) throw ArgumentError.value(maxBytes, 'maxBytes');
    if (timeout != null ||
        abortTrigger != null ||
        maxBytes != 64 * 1024 * 1024) {
      return _loadBoundedBytes(
        remotePath,
        maxBytes,
        timeout ?? requestTimeout,
        abortTrigger,
      );
    }
    if (browser) {
      final resource = await _record(remotePath), origin = _currentOrigin();
      if (resource == null || origin == null) return null;
      try {
        final bytes = await _fetch(remotePath);
        if (bytes != null &&
            bytes.length <= 8 * 1024 * 1024 &&
            _sameResource(origin, remotePath, resource)) {
          await writeBrowserAsset(_objectKey(origin, resource), bytes);
        }
        return bytes;
      } catch (_) {
        return cachedBytesFor(remotePath);
      }
    }
    final asset = await ensureCached(sources: sources, remotePath: remotePath);
    if (asset == null) return null;
    final file = File(asset.localPath);
    if (await file.length() > 64 * 1024 * 1024) {
      throw StateError('资料超过单次内存读取上限');
    }
    return file.readAsBytes();
  }

  /// Small AI inputs use a bounded, cancellable read on every platform. The
  /// normal PDF viewer's streamed disk-download path stays independent.
  Future<List<int>?> _loadBoundedBytes(
    String path,
    int maxBytes,
    Duration timeout,
    Future<void>? abortTrigger,
  ) async {
    final abort = Completer<void>();
    final timer = Timer(timeout, () {
      if (!abort.isCompleted) abort.complete();
    });
    abortTrigger?.then((_) {
      if (!abort.isCompleted) abort.complete();
    });
    final origin = _currentOrigin();
    void guard() {
      if (abort.isCompleted) {
        throw TimeoutException('Knowledge preparation cancelled or timed out');
      }
      if (origin == null || !_current(origin)) {
        throw StateError('Library source changed');
      }
    }

    Future<List<int>?> read() async {
      final resource = await _record(path);
      guard();
      if (resource == null) return null;
      final key = _objectKey(origin!, resource);
      List<int>? cached;
      if (browser) {
        cached = await readBrowserAsset(key);
      } else {
        final file = await _file(key);
        if (await file.exists()) {
          if (await file.length() > maxBytes) {
            throw StateError('request_too_large');
          }
          cached = await file.readAsBytes();
        }
      }
      guard();
      if (cached != null && cached.length > maxBytes) {
        throw StateError('request_too_large');
      }
      if (cached != null &&
          sha256.convert(cached).toString() == resource.sha256 &&
          _sameResource(origin, path, resource)) {
        return cached;
      }
      final uri = resourceUri(path);
      if (uri == null) return null;
      final response = await _request(uri, abort: abort, maxBytes: maxBytes);
      guard();
      if (response.statusCode != 200) throw StateError('knowledge_unavailable');
      if (response.bodyBytes.isEmpty ||
          sha256.convert(response.bodyBytes).toString() != resource.sha256 ||
          !_sameResource(origin, path, resource)) {
        throw StateError('knowledge_integrity');
      }
      try {
        if (browser) {
          await writeBrowserAsset(key, response.bodyBytes);
        } else {
          final file = await _file(key);
          await file.parent.create(recursive: true);
          final staged = File('${file.path}.${_sequence++}.knowledge');
          try {
            await staged.writeAsBytes(response.bodyBytes, flush: true);
            guard();
            if (!_sameResource(origin, path, resource)) {
              throw StateError('Library changed');
            }
            await staged.rename(file.path);
          } finally {
            if (await staged.exists()) await staged.delete();
          }
        }
      } catch (_) {
        // Caching is optional; identity and digest verification are mandatory.
      }
      guard();
      if (!_sameResource(origin, path, resource)) {
        throw StateError('knowledge_integrity');
      }
      return response.bodyBytes;
    }

    try {
      return await Future.any<List<int>?>([
        read(),
        abort.future.then<List<int>?>(
          (_) => throw TimeoutException(
            'Knowledge preparation cancelled or timed out',
          ),
        ),
      ]);
    } finally {
      timer.cancel();
      if (!abort.isCompleted) abort.complete();
    }
  }

  Future<String?> loadText({
    required List<AssetSourceConfig> sources,
    required String remotePath,
  }) async {
    final bytes = await loadBytes(sources: sources, remotePath: remotePath);
    return bytes == null ? null : utf8.decode(bytes);
  }

  Future<String?> loadTextFromAny({
    required List<AssetSourceConfig> sources,
    required List<String> remotePaths,
  }) async {
    for (final path in remotePaths) {
      final text = await loadText(sources: sources, remotePath: path);
      if (text != null && text.trim().isNotEmpty) return text;
    }
    return null;
  }

  Future<ConnectivityStatus> checkAccess(
    AssetSourceConfig source, {
    Completer<void>? abort,
    void Function(int)? onRevision,
  }) async {
    try {
      final origin = _currentOrigin();
      if (origin == null) throw StateError('No service');
      final value = await _json(
        Uri.parse('${_base(origin)}/revision'),
        abort ?? Completer<void>(),
      );
      if (!_current(origin) || abort?.isCompleted == true) {
        throw StateError('Cancelled');
      }
      onRevision?.call(value['revision'] as int);
      return ConnectivityStatus(
        state: ConnectivityState.success,
        message: '公开资料可读取',
        checkedAt: DateTime.now(),
      );
    } catch (_) {
      return ConnectivityStatus(
        state: ConnectivityState.failure,
        message: '公开资料暂不可用，请检查应用服务地址',
        checkedAt: DateTime.now(),
      );
    }
  }

  Future<void> prefetchGameImages({
    required List<AssetSourceConfig> sources,
    required Iterable<String> remotePaths,
  }) async {
    for (final path in remotePaths.toSet()) {
      await ensureCached(sources: sources, remotePath: path);
    }
  }

  /// A filtered view of SQL metadata, with no filesystem traversal or file probes.
  Future<List<RemoteAssetFile>> listFilesRecursively({
    required List<AssetSourceConfig> sources,
    required String remotePath,
    int maxDepth = 6,
    int maxEntries = 1000,
  }) async {
    final snapshot = await loadCatalog();
    final prefix = '$remotePath/';
    return [
      for (final entry
          in snapshot.files.entries
              .where(
                (e) =>
                    e.key.startsWith(prefix) &&
                    e.key.substring(prefix.length).split('/').length <=
                        maxDepth + 1,
              )
              .take(maxEntries))
        RemoteAssetFile(
          remotePath: entry.key,
          name: entry.value.fileName,
          sourceId: 'app_service',
          etag: entry.value.sha256,
        ),
    ];
  }
}

class _CatalogChanged implements Exception {
  const _CatalogChanged();
}
